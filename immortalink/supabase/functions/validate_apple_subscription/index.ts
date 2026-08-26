import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const bundleId = Deno.env.get("APPLE_BUNDLE_ID") || "com.everroots.app";
const configuredEnvironment =
  (Deno.env.get("APPLE_IAP_ENVIRONMENT") || "sandbox").toLowerCase() ===
    "production"
    ? "production"
    : "sandbox";

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

function base64UrlDecodeJson(segment: string) {
  const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    "=",
  );
  return JSON.parse(new TextDecoder().decode(
    Uint8Array.from(atob(padded), (char) => char.charCodeAt(0)),
  ));
}

function decodeJwsPayload(jws: string) {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Invalid Apple JWS payload");
  return base64UrlDecodeJson(parts[1]);
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

function productMap() {
  const familyMonthly =
    Deno.env.get("APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID") ||
    "everroots.family.monthly";
  const familyAnnual =
    Deno.env.get("APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID") ||
    "everroots.family.annual";
  const legacyMonthly =
    Deno.env.get("APPLE_EVER_ROOTS_LEGACY_MONTHLY_PRODUCT_ID") ||
    "everroots.legacy.monthly";
  const legacyAnnual =
    Deno.env.get("APPLE_EVER_ROOTS_LEGACY_ANNUAL_PRODUCT_ID") ||
    "everroots.legacy.annual";

  return new Map<string, string>([
    [familyMonthly, "everroot_family"],
    [familyAnnual, "everroot_family"],
    [legacyMonthly, "everroot_legacy"],
    [legacyAnnual, "everroot_legacy"],
  ]);
}

async function fetchAppleTransaction(transactionId: string) {
  const token = await createAppleServerToken();
  const host = configuredEnvironment === "production"
    ? "https://api.storekit.itunes.apple.com"
    : "https://api.storekit-sandbox.itunes.apple.com";
  const response = await fetch(
    `${host}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`Apple transaction lookup failed ${response.status}: ${text}`);
  }
  const payload = await response.json();
  return decodeJwsPayload(String(payload.signedTransactionInfo || ""));
}

function entitlementStatus(transaction: any) {
  if (transaction.revocationDate) return "refunded";
  const expiresDate = Number(transaction.expiresDate || 0);
  if (!expiresDate || expiresDate <= Date.now()) return "expired";
  return "active";
}

async function applyEntitlement({
  admin,
  familyId,
  userId,
  transaction,
  source,
  notificationType,
  subtype,
}: {
  admin: any;
  familyId: string;
  userId: string | null;
  transaction: any;
  source: "client_validation" | "server_notification";
  notificationType?: string;
  subtype?: string;
}) {
  if (transaction.bundleId !== bundleId) {
    throw new Error("Apple transaction bundle id does not match this app");
  }

  const productId = clean(transaction.productId);
  const plan = productMap().get(productId);
  if (!plan) throw new Error("Unsupported Apple subscription product");

  const status = entitlementStatus(transaction);
  const originalTransactionId = clean(transaction.originalTransactionId);
  const transactionId = clean(transaction.transactionId);
  if (!originalTransactionId || !transactionId) {
    throw new Error("Apple transaction is missing required identifiers");
  }

  const currentPeriodEnd = Number(transaction.expiresDate || 0)
    ? new Date(Number(transaction.expiresDate)).toISOString()
    : null;

  const { error: eventError } = await admin
    .from("apple_subscription_events")
    .insert({
      family_id: familyId || null,
      user_id: userId,
      event_source: source,
      apple_environment: configuredEnvironment,
      apple_product_id: productId,
      apple_original_transaction_id: originalTransactionId,
      apple_transaction_id: transactionId,
      notification_type: notificationType || null,
      subtype: subtype || null,
      entitlement_status: status,
      raw_payload: transaction,
    });
  if (eventError) throw new Error(eventError.message);

  const { error } = await admin.from("family_entitlements").upsert(
    {
      family_id: familyId,
      plan: status === "active" ? plan : "free",
      status,
      provider: "apple",
      provider_entitlement_id: transactionId,
      provider_subscription_id: originalTransactionId,
      billing_owner_user_id: userId,
      current_period_end: currentPeriodEnd,
      apple_original_transaction_id: originalTransactionId,
      apple_product_id: productId,
      apple_environment: configuredEnvironment,
      offer_type: transaction.offerType ? String(transaction.offerType) : null,
      offer_identifier: transaction.offerIdentifier
        ? String(transaction.offerIdentifier)
        : null,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "family_id" },
  );
  if (error) throw new Error(error.message);

  return { plan, status, product_id: productId, current_period_end: currentPeriodEnd };
}

async function assertOwner(admin: any, familyId: string, userId: string) {
  const { data, error } = await admin
    .from("family_members")
    .select("family_id, user_id, role")
    .eq("family_id", familyId)
    .eq("user_id", userId)
    .eq("role", "owner")
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("Only a family owner can buy this family plan");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

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

    await assertOwner(admin, familyId, user.id);
    const transaction = await fetchAppleTransaction(transactionId);
    const result = await applyEntitlement({
      admin,
      familyId,
      userId: user.id,
      transaction,
      source: "client_validation",
    });

    return json(200, { ok: true, entitlement: result });
  } catch (e) {
    console.error(e);
    return json(400, { error: e instanceof Error ? e.message : String(e) });
  }
});
