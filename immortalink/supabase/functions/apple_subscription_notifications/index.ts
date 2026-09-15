import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { productMap } from "../_shared/apple_subscription_products.ts";
import {
  createNotificationVerifier,
  notificationErrorStatus,
  verifyNotification,
} from "./notification_verifier.ts";

const bundleId = Deno.env.get("APPLE_BUNDLE_ID") || "com.everroots.app";
const configuredEnvironment =
  (Deno.env.get("APPLE_IAP_ENVIRONMENT") || "sandbox").trim().toLowerCase();
let verifier: ReturnType<typeof createNotificationVerifier> | undefined;

function getVerifier() {
  return verifier ??= createNotificationVerifier(
    configuredEnvironment,
    bundleId,
    Deno.env.get("APPLE_APP_ID"),
  );
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
    throw new Error(`Apple transaction lookup failed ${response.status}`);
  }
  const payload = await response.json();
  return await getVerifier().verifyAndDecodeTransaction(
    String(payload.signedTransactionInfo || ""),
  );
}

function entitlementStatus(transaction: any, notificationType: string) {
  if (transaction.revocationDate || notificationType === "REFUND") {
    return "refunded";
  }
  if (notificationType === "REVOKE") return "revoked";
  const expiresDate = Number(transaction.expiresDate || 0);
  if (!expiresDate || expiresDate <= Date.now()) return "expired";
  return "active";
}

export async function handleNotification(req: Request) {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const body = await req.json().catch(() => ({}));
    const { notification, transaction: notificationTransaction } =
      await verifyNotification(
        body?.signedPayload,
        getVerifier(),
      );
    const notificationType = clean(notification.notificationType);
    const subtype = clean(notification.subtype);
    if (!notificationTransaction) {
      return json(202, { ok: true, ignored: "No signed transaction" });
    }

    const transactionId = clean(notificationTransaction.transactionId);
    if (!transactionId) {
      return json(202, { ok: true, ignored: "No transaction id" });
    }

    const transaction = await fetchAppleTransaction(transactionId);
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

    const { data: existing, error: existingError } = await admin
      .from("family_entitlements")
      .select("family_id, billing_owner_user_id")
      .eq("apple_original_transaction_id", originalTransactionId)
      .maybeSingle();
    if (existingError) throw new Error(existingError.message);

    const familyId = clean(existing?.family_id);
    if (!familyId) {
      const { error: eventError } = await admin.from(
        "apple_subscription_events",
      ).insert({
        event_source: "server_notification",
        apple_environment: configuredEnvironment,
        apple_product_id: productId,
        apple_original_transaction_id: originalTransactionId,
        apple_transaction_id: clean(transaction.transactionId),
        notification_type: notificationType || null,
        subtype: subtype || null,
        entitlement_status: "unmatched",
        raw_payload: notification,
      });
      if (eventError) throw new Error(eventError.message);
      return json(202, { ok: true, ignored: "No matching family entitlement" });
    }

    const status = entitlementStatus(transaction, notificationType);
    const currentPeriodEnd = Number(transaction.expiresDate || 0)
      ? new Date(Number(transaction.expiresDate)).toISOString()
      : null;

    const { error: eventError } = await admin
      .from("apple_subscription_events")
      .insert({
        family_id: familyId,
        user_id: existing?.billing_owner_user_id || null,
        event_source: "server_notification",
        apple_environment: configuredEnvironment,
        apple_product_id: productId,
        apple_original_transaction_id: originalTransactionId,
        apple_transaction_id: clean(transaction.transactionId),
        notification_type: notificationType || null,
        subtype: subtype || null,
        entitlement_status: status,
        raw_payload: notification,
      });
    if (eventError) throw new Error(eventError.message);

    const { error } = await admin
      .from("family_entitlements")
      .update({
        plan: status === "active" ? plan : "free",
        status,
        provider: "apple",
        provider_entitlement_id: clean(transaction.transactionId),
        provider_subscription_id: originalTransactionId,
        current_period_end: currentPeriodEnd,
        apple_product_id: productId,
        apple_environment: configuredEnvironment,
        offer_type: transaction.offerType
          ? String(transaction.offerType)
          : null,
        offer_identifier: transaction.offerIdentifier
          ? String(transaction.offerIdentifier)
          : null,
        updated_at: new Date().toISOString(),
      })
      .eq("family_id", familyId);
    if (error) throw new Error(error.message);

    return json(200, { ok: true, status, family_id: familyId });
  } catch (e) {
    const status = notificationErrorStatus(e);
    console.error("Apple notification rejected", {
      status,
      reason: e instanceof Error ? e.name : "Unknown",
    });
    return json(status, {
      error: status === 400
        ? "Invalid Apple signed notification"
        : "Notification processing temporarily unavailable",
    });
  }
}

if (import.meta.main) serve(handleNotification);
