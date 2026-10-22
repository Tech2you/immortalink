import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { productMap } from "../_shared/apple_subscription_products.ts";
import { AppleEnvironment, lookupAppleTransaction } from "../_shared/apple_environment.ts";
import {
  createNotificationVerifier,
  appleVerificationDiagnostic,
  notificationErrorStatus,
  verifyNotification,
  selectNotificationEnvironment,
} from "./notification_verifier.ts";

const bundleId = Deno.env.get("APPLE_BUNDLE_ID") || "com.everroots.app";
const verifiers = new Map<AppleEnvironment, ReturnType<typeof createNotificationVerifier>>();

function getVerifier(environment: AppleEnvironment) {
  let verifier = verifiers.get(environment);
  if (!verifier) {
    verifier = createNotificationVerifier(environment, bundleId, Deno.env.get("APPLE_APP_ID") || "6802720270");
    verifiers.set(environment, verifier);
  }
  return verifier;
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function clean(value: unknown) {
  return String(value || "").trim();
}

function base64UrlEncode(input: string | ArrayBuffer) {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
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
  const unsigned = `${
    base64UrlEncode(JSON.stringify({
      alg: "ES256",
      kid: keyId,
      typ: "JWT",
    }))
  }.${
    base64UrlEncode(JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + 900,
      aud: "appstoreconnect-v1",
      bid: bundleId,
    }))
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

async function fetchAppleTransaction(transactionId: string, environment: AppleEnvironment) {
  const token = await createAppleServerToken();
  return await lookupAppleTransaction({ transactionId, token, environment,
    verify: (signed, selected) => getVerifier(selected).verifyAndDecodeTransaction(signed),
  });
}

export async function handleNotification(req: Request) {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const body = await req.json().catch(() => ({}));
    const environment = selectNotificationEnvironment(body?.signedPayload);
    const { notification, transaction: notificationTransaction } =
      await verifyNotification(
        body?.signedPayload,
        getVerifier(environment),
      );
    const notificationType = clean(notification.notificationType);
    if (!notificationTransaction) {
      return json(202, { ok: true, ignored: "No signed transaction" });
    }

    const transactionId = clean(notificationTransaction.transactionId);
    if (!transactionId) {
      return json(202, { ok: true, ignored: "No transaction id" });
    }

    const transaction = await fetchAppleTransaction(transactionId, environment);
    if (transaction.bundleId !== bundleId) {
      throw new Error("Apple transaction bundle id does not match this app");
    }
    if (
      transaction.transactionId !== transactionId ||
      transaction.originalTransactionId !==
        notificationTransaction.originalTransactionId ||
      transaction.productId !== notificationTransaction.productId
    ) {
      throw new Error("Apple transaction identity mismatch");
    }

    const originalTransactionId = clean(transaction.originalTransactionId);
    const productId = clean(transaction.productId);
    const plan = productMap().get(productId);
    if (!originalTransactionId || !plan) {
      return json(202, { ok: true, ignored: "Unknown subscription" });
    }

    // No database access until both Apple signatures and transaction identity pass.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: result, error } = await admin.rpc("apply_verified_family_subscription", {
      p_transaction: transaction,
      p_family_id: null,
      p_user_id: null,
      p_source: "server_notification",
      p_notification_type: notificationType || null,
    });
    if (error) throw error;
    // The notification can arrive before the app submits its first verified
    // purchase. Keep the recovery record and ask Apple to retry after binding.
    if (result?.code === "APPLE_PURCHASE_UNMATCHED") {
      return json(503, { error: "Purchase assignment pending" });
    }
    // Retired sponsor chains must never overwrite the replacement entitlement.
    return json(200, { ok: true, applied: result?.applied, code: result?.code });
  } catch (e) {
    const status = notificationErrorStatus(e);
    console.error("Apple notification rejected", {
      status,
      reason: e instanceof Error ? e.name : "Unknown",
      ...appleVerificationDiagnostic(e),
    });
    return json(status, {
      error: status === 400
        ? "Invalid Apple signed notification"
        : "Notification processing temporarily unavailable",
    });
  }
}

if (import.meta.main) serve(handleNotification);
