import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function cleanText(value: unknown, fallback = "") {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text || fallback;
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
    },
  );

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw new Error(`FCM send failed ${response.status}: ${errorText}`);
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

    const payload = await req.json().catch(() => ({}));
    const type = cleanText(payload.type);

    let familyId = "";
    let title = "New family update";
    let body = "Open Ever Roots to see the family feed.";

    if (type === "memory_added") {
      const memoryId = cleanText(payload.memory_id);
      if (!memoryId) return json(400, { error: "Missing memory_id" });

      const { data: memory, error: memoryError } = await userClient
        .from("memories")
        .select("id, vault_id, share_to_family_feed")
        .eq("id", memoryId)
        .maybeSingle();
      if (memoryError) return json(500, { error: memoryError.message });
      if (!memory?.share_to_family_feed) {
        return json(403, { error: "Memory is not shared to the family feed" });
      }

      const { data: vault, error: vaultError } = await admin
        .from("vaults")
        .select("id, owner_id, family_id")
        .eq("id", memory.vault_id)
        .maybeSingle();
      if (vaultError) return json(500, { error: vaultError.message });
      if (!vault || vault.owner_id !== user.id || !vault.family_id) {
        return json(403, { error: "Not allowed to notify this family" });
      }

      familyId = vault.family_id;
      title = "A new memory was added";
      body = "Open Ever Roots to see it in your family feed.";
    } else if (type === "family_joined") {
      familyId = cleanText(payload.family_id);
      if (!familyId) return json(400, { error: "Missing family_id" });

      const { data: membership, error: membershipError } = await admin
        .from("family_members")
        .select("family_id, user_id")
        .eq("family_id", familyId)
        .eq("user_id", user.id)
        .maybeSingle();
      if (membershipError) return json(500, { error: membershipError.message });
      if (!membership) return json(403, { error: "Not a member of this family" });

      title = "Someone joined your family";
      body = "Open Ever Roots to welcome them.";
    } else {
      return json(400, { error: "Unsupported notification type" });
    }

    const { data: members, error: membersError } = await admin
      .from("family_members")
      .select("user_id")
      .eq("family_id", familyId)
      .neq("user_id", user.id);
    if (membersError) return json(500, { error: membersError.message });

    const recipientIds = [...new Set((members || []).map((row: any) => row.user_id))];
    if (recipientIds.length === 0) return json(200, { sent: 0, failed: 0 });

    const { data: tokenRows, error: tokensError } = await admin
      .from("user_push_tokens")
      .select("token")
      .in("user_id", recipientIds);
    if (tokensError) return json(500, { error: tokensError.message });

    const tokens = [...new Set((tokenRows || []).map((row: any) => row.token))]
      .filter(Boolean);
    if (tokens.length === 0) return json(200, { sent: 0, failed: 0 });

    const firebase = await getFirebaseConfig();
    let sent = 0;
    let failed = 0;

    await Promise.all(
      tokens.map(async (token) => {
        try {
          await sendToFirebase({
            ...firebase,
            token,
            title,
            body: body.length > 120 ? `${body.slice(0, 117)}...` : body,
            familyId,
          });
          sent += 1;
        } catch (error) {
          failed += 1;
          console.error(String(error));
        }
      }),
    );

    return json(200, { sent, failed });
  } catch (error) {
    console.error(error);
    return json(500, { error: String(error) });
  }
});
