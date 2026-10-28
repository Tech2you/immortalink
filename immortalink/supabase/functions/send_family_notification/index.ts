import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
import { claimNotification, readNotificationPayload, recipientTokens, sendBounded } from "./dispatch_guard.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const firebaseMessagingScope =
  "https://www.googleapis.com/auth/firebase.messaging";
const oauthTokenUrl = "https://oauth2.googleapis.com/token";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

async function createFirebaseAccessToken(serviceAccount: any) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: serviceAccount.client_email,
    scope: firebaseMessagingScope,
    aud: oauthTokenUrl,
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaims = base64UrlEncode(JSON.stringify(claims));
  const unsignedToken = `${encodedHeader}.${encodedClaims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken),
  );

  const assertion = `${unsignedToken}.${base64UrlEncode(signature)}`;
  const response = await fetch(oauthTokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    throw new Error(`Firebase token request failed: ${response.status}`);
  }

  const payload = await response.json();
  if (!payload?.access_token) {
    throw new Error("Firebase token response did not include an access token");
  }
  return String(payload.access_token);
}

async function getFirebaseConfig() {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new Error("Missing FIREBASE_SERVICE_ACCOUNT_JSON Edge Function secret");
  }

  const serviceAccount = JSON.parse(raw);
  if (
    !serviceAccount?.project_id ||
    !serviceAccount?.client_email ||
    !serviceAccount?.private_key
  ) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is missing required fields");
  }

  const accessToken = await createFirebaseAccessToken(serviceAccount);
  return {
    accessToken,
    projectId: String(serviceAccount.project_id),
  };
}

async function sendToFirebase({
  accessToken,
  projectId,
  token,
  title,
  body,
  familyId,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  familyId: string;
}) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: {
            type: "family_feed",
            family_id: familyId,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
      signal: AbortSignal.timeout(10000),
    },
  );

  if (!response.ok) {
    throw new Error(`FCM send failed ${response.status}`);
  }
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

    let event;
    try { event = await readNotificationPayload(req); }
    catch { return json(400, { error: "Invalid notification request" }); }
    const audience = await claimNotification(admin, event, user.id);
    if (audience.code === "DENIED") return json(403, { error: "Notification not available" });
    if (audience.code === "RATE_LIMIT") return json(429, { error: "Notification rate limit reached" });
    if (audience.code !== "CLAIMED") return json(200, { sent: 0, failed: 0, skipped: audience.code });
    const familyId = audience.familyId;
    const recipientIds = audience.recipientIds;
    if (typeof familyId !== "string" || !Array.isArray(recipientIds)) {
      throw new Error("Invalid notification audience");
    }
    const title = event.type === "memory_added" ? "A new memory was added" : "Someone joined your family";
    const body = event.type === "memory_added" ? "Open Heiro to see it in your family feed." : "Open Heiro to welcome them.";
    if (recipientIds.length === 0) return json(200, { sent: 0, failed: 0 });

    const tokens = await recipientTokens(admin, recipientIds);
    if (tokens.length === 0) return json(200, { sent: 0, failed: 0 });

    const firebase = await getFirebaseConfig();
    const result = await sendBounded(tokens, (token: string) => sendToFirebase({
      ...firebase, token, title, body, familyId,
    }));
    return json(200, result);
  } catch {
    console.error("Family notification failed; no provider response or recipient data logged.");
    return json(503, { error: "Notification service unavailable" });
  }
});
