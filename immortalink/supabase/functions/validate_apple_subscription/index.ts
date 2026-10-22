import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { productValidationError } from "./product_validation.ts";
import { productMap } from "../_shared/apple_subscription_products.ts";
import { appleVerificationDiagnostic, createNotificationVerifier } from "../apple_subscription_notifications/notification_verifier.ts";
import { AppleEnvironment, AppleTransactionLookupError, lookupAppleTransaction } from "../_shared/apple_environment.ts";
import { transactionEnvironment } from "./transaction_environment.ts";
import { ownershipDiagnostic } from "./ownership_diagnostic.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const bundleId = Deno.env.get("APPLE_BUNDLE_ID") || "com.everroots.app";
const appAppleId = Deno.env.get("APPLE_APP_ID") || "6802720270";
const verifiers = new Map<AppleEnvironment, ReturnType<typeof createNotificationVerifier>>();

function getVerifier(environment: AppleEnvironment) {
  let verifier = verifiers.get(environment);
  if (!verifier) {
    verifier = createNotificationVerifier(environment, bundleId, appAppleId);
    verifiers.set(environment, verifier);
  }
  return verifier;
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown) {
  return String(value || "").trim();
}

function base64UrlEncode(input: string | ArrayBuffer) {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function decodePrivateKey(privateKey: string) {
  const normalized = privateKey.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0)).buffer;
}

async function createAppleServerToken() {
  const issuerId = Deno.env.get("APPLE_IAP_ISSUER_ID");
  const keyId = Deno.env.get("APPLE_IAP_KEY_ID");
  const privateKey = Deno.env.get("APPLE_IAP_PRIVATE_KEY");
  if (!issuerId || !keyId || !privateKey) {
    throw new Error("Missing Apple App Store Server API secrets");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const claims = {
    iss: issuerId,
    iat: now,
    exp: now + 900,
    aud: "appstoreconnect-v1",
    bid: bundleId,
  };
  const unsigned = `${base64UrlEncode(JSON.stringify(header))}.${
    base64UrlEncode(JSON.stringify(claims))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64UrlEncode(signature)}`;
}

async function fetchAppleTransaction(transactionId: string, environment?: AppleEnvironment) {
  const token = await createAppleServerToken();
  return await lookupAppleTransaction({ transactionId, token, environment,
    verify: (signed, environment) => getVerifier(environment)
      .verifyAndDecodeTransaction(signed),
  });
}


serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  let verifiedEnvironment: string | undefined;
  let ownership: Awaited<ReturnType<typeof ownershipDiagnostic>> | undefined;
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("authorization") || "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: auth, error: authError } = await userClient.auth.getUser();
    const user = auth?.user;
    if (authError || !user) return json(401, { error: "Invalid or missing JWT" });

    const body = await req.json().catch(() => ({}));
    const familyId = clean(body.family_id);
    const transactionId = clean(body.transaction_id || body.purchase_id);
    if (!familyId) return json(400, { error: "Missing family_id" });
    if (!transactionId) return json(400, { error: "Missing Apple transaction id" });

    const { data: membership, error: membershipError } = await admin.from("family_members")
      .select("family_id").eq("family_id", familyId).eq("user_id", user.id).maybeSingle();
    if (membershipError || !membership) {
      return json(403, { code: "FAMILY_MEMBERSHIP_REQUIRED", error: "Join this family before sponsoring it." });
    }
    const environment = await transactionEnvironment({
      transactionId,
      signedTransaction: body.server_verification_data,
      verify: (signed, selected) => getVerifier(selected)
        .verifyAndDecodeTransaction(signed),
      previousEnvironments: async () => {
        const { data, error } = await admin.from("apple_subscription_events")
          .select("apple_environment").eq("apple_transaction_id", transactionId)
          .in("apple_environment", ["sandbox", "production"]);
        if (error) throw error;
        return (data ?? []).map((event) => event.apple_environment);
      },
    });
    const transaction = await fetchAppleTransaction(transactionId, environment);
    verifiedEnvironment = transaction.environment?.toLowerCase();
    const validationError = productValidationError({
      transaction,
      bundleId,
      transactionId,
      requestedProductId: clean(body.product_id),
      supportedProducts: productMap(),
    });
    if (validationError) return json(400, validationError);
    const originalTransactionId = clean(transaction.originalTransactionId);
    if (!originalTransactionId) {
      return json(400, { code: "APPLE_TRANSACTION_INVALID", error: "Could not verify this purchase." });
    }
    const { data: result, error } = await admin.rpc("apply_verified_family_subscription", {
      p_transaction: transaction,
      p_family_id: familyId,
      p_user_id: user.id,
      p_source: "client_validation",
    });
    if (error) {
      if (["APPLE_PURCHASE_ALREADY_BOUND", "APPLE_PURCHASER_MISMATCH"].includes(error.message)) {
        ownership = await ownershipDiagnostic({ transaction, userId: user.id, familyId,
          lookupBinding: async (originalId) => {
            const { data, error: lookupError } = await admin.from("apple_sponsor_bindings")
              .select("purchaser_id,family_id,environment,retired")
              .eq("original_transaction_id", originalId).maybeSingle();
            if (lookupError) throw lookupError;
            return data;
          },
        });
      }
      throw error;
    }
    if (!result?.applied) return json(409, { code: result?.code || "APPLE_VALIDATION_FAILED",
      environment: verifiedEnvironment,
      error: "This purchase could not be applied. Do not purchase again; contact support or manage the subscription with Apple." });

    return json(200, { ok: true, entitlement: result });
  } catch (e) {
    const message = e && typeof e === "object" && "message" in e ? String(e.message) : "";
    const allowed = ["FAMILY_MEMBERSHIP_REQUIRED", "APPLE_PURCHASE_ALREADY_BOUND", "APPLE_PURCHASER_MISMATCH",
      "APPLE_PURCHASER_UNVERIFIED", "APPLE_ENVIRONMENT_MISMATCH"];
    const code = allowed.includes(message) ? message
      : e instanceof AppleTransactionLookupError && e.status === 401
      ? "APPLE_API_AUTHENTICATION_FAILED" : "APPLE_VALIDATION_FAILED";
    const lookupStatus = /^Apple transaction lookup failed (\d{3})/.exec(message)?.[1];
    console.error("Apple validation rejected", { code,
      ...appleVerificationDiagnostic(e),
      ...ownership,
      ...(lookupStatus ? { apple_http_status: Number(lookupStatus) } : {}),
      ...(e instanceof AppleTransactionLookupError ? { lookup_environment: e.environment } : {}),
    });
    return json(code === "APPLE_API_AUTHENTICATION_FAILED" ? 502 : 400, { code,
      ...(allowed.includes(message) && verifiedEnvironment ? { environment: verifiedEnvironment } : {}),
      error: "Could not verify this purchase for this account and family. Do not purchase again; retry restore or contact support." });
  }
});
