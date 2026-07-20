// supabase/functions/index_memory/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*", // for MVP. later restrict to your domains
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function chunkText(text: string, maxChars = 900) {
  const clean = (text || "").trim();
  if (!clean) return [];
  const chunks: string[] = [];
  for (let i = 0; i < clean.length; i += maxChars) {
    chunks.push(clean.slice(i, i + maxChars));
  }
  return chunks;
}

serve(async (req) => {
  // ✅ CORS preflight
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // user token from the request
    const authHeader = req.headers.get("authorization") || "";

    // client with user auth (RLS-enforced checks)
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    // ✅ Verify user is valid (works when Verify JWT = ON)
    const { data: u, error: uErr } = await userClient.auth.getUser();
    if (uErr || !u?.user) {
      return json(401, { error: "Invalid/missing JWT" });
    }

    const { vault_id, memory_id } = await req.json().catch(() => ({}));
    if (!vault_id || !memory_id) {
      return json(400, { error: "Missing vault_id or memory_id" });
    }

    // ✅ Check the user can actually see this memory (RLS will enforce)
    const { data: mem, error: memErr } = await userClient
      .from("memories")
      .select("id, vault_id, prompt_text, body, memory_date_label, people, location, mood")
      .eq("id", memory_id)
      .eq("vault_id", vault_id)
      .maybeSingle();

    if (memErr) return json(500, { error: memErr.message });
    if (!mem) return json(403, { error: "Not allowed or not found" });

    const { data: voiceNotes, error: voiceErr } = await userClient
      .from("memory_voice_notes")
      .select("title, transcript, created_at")
      .eq("vault_id", vault_id)
      .eq("memory_id", memory_id)
      .order("created_at", { ascending: true });
    if (voiceErr) return json(500, { error: voiceErr.message });

    const voiceContext = (voiceNotes || [])
      .map((note: any, index: number) => {
        const transcript = (note?.transcript || "").toString().trim();
        if (!transcript) return "";
        const title = (note?.title || "Voice note").toString().trim();
        return `Voice note ${index + 1} (${title}):\n${transcript}`;
      })
      .filter(Boolean);

    const fullText = [
      mem.prompt_text ? `Title: ${mem.prompt_text}` : "",
      mem.body ? `Memory: ${mem.body}` : "",
      mem.memory_date_label ? `When: ${mem.memory_date_label}` : "",
      mem.people ? `People: ${mem.people}` : "",
      mem.location ? `Location: ${mem.location}` : "",
      mem.mood ? `Mood: ${mem.mood}` : "",
      ...voiceContext,
    ].filter(Boolean).join("\n");

    const chunks = chunkText(fullText, 900);

    // service role client to write chunks (bypasses RLS on insert)
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Upsert chunks deterministically by (vault_id, memory_id, chunk_index)
    const payload = chunks.map((t, i) => ({
      vault_id,
      memory_id,
      chunk_index: i,
      chunk_text: t, // <-- make sure your table column is named chunk_text
    }));

    // delete old chunks for this memory first (optional but clean)
    await admin.from("memory_chunks").delete().eq("vault_id", vault_id).eq("memory_id", memory_id);

    const { error: insErr } = await admin.from("memory_chunks").insert(payload);
    if (insErr) return json(500, { error: insErr.message });

    return json(200, { ok: true, chunk_count: payload.length });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});
