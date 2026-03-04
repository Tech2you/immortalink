import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
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

function textClean(s: string) {
  return (s || "").replace(/\s+/g, " ").trim();
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

async function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return (await Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms),
    ),
  ])) as T;
}

async function downloadVoiceNoteBytes({
  admin,
  storagePath,
}: {
  admin: any;
  storagePath: string;
}): Promise<Uint8Array> {
  // Try a few likely buckets (MVP safe)
  const buckets = [
    "voice_notes",
    "vault_voice_notes",
    "memory_voice_notes",
    "vault_media",
    "vault_voice_notes",
  ];

  let lastErr = "";

  for (const bucket of buckets) {
    try {
      // 1 hour signed URL
      const { data, error } = await admin.storage
        .from(bucket)
        .createSignedUrl(storagePath, 60 * 60);

      if (error || !data?.signedUrl) {
        lastErr = error?.message || "No signedUrl";
        continue;
      }

      const resp = await fetch(data.signedUrl);
      if (!resp.ok) {
        lastErr = `Fetch failed ${resp.status}`;
        continue;
      }

      const buf = new Uint8Array(await resp.arrayBuffer());
      if (!buf.length) {
        lastErr = "Empty audio file";
        continue;
      }

      return buf;
    } catch (e) {
      lastErr = String(e);
    }
  }

  throw new Error(
    `Could not download audio from storage_path="${storagePath}". Last error: ${lastErr}`,
  );
}

async function transcribeWithOpenAI({
  apiKey,
  audioBytes,
}: {
  apiKey: string;
  audioBytes: Uint8Array;
}): Promise<string> {
  // OpenAI Whisper transcription endpoint
  const form = new FormData();
  form.append("model", "gpt-4o-mini-transcribe");

  // name is important for MIME inference sometimes
  const file = new File([audioBytes], "voice_note.m4a", { type: "audio/mp4" });
  form.append("file", file);

  const resp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
    body: form,
  });

  if (!resp.ok) {
    const t = await resp.text().catch(() => "");
    throw new Error(`OpenAI transcription failed ${resp.status}: ${t}`);
  }

  const data = await resp.json().catch(() => ({}));
  const text = (data?.text ?? "").toString();
  return textClean(text);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Use POST" });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") || "";

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
      return json(500, { error: "Missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY in function env." });
    }
    if (!OPENAI_API_KEY) {
      return json(500, { error: "Missing OPENAI_API_KEY in Edge Function secrets." });
    }

    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization") || "";

    // User client (RLS enforced)
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    // Admin client (bypass RLS for inserts into chunks, signed URL, etc.)
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Verify JWT
    const { data: u, error: uErr } = await userClient.auth.getUser();
    if (uErr || !u?.user) return json(401, { error: "Invalid/missing JWT" });

    const payload = await req.json().catch(() => ({}));
    const vaultId = textClean(payload?.vault_id || payload?.vaultId || "");
    const voiceNoteId = textClean(payload?.voice_note_id || payload?.voiceNoteId || "");

    if (!vaultId) return json(400, { error: "vault_id is required" });
    if (!voiceNoteId) return json(400, { error: "voice_note_id is required" });

    // Fetch voice note (RLS must allow owner/family as you decide)
    const { data: vn, error: vnErr } = await withTimeout(
      userClient
        .from("voice_notes")
        .select("id, vault_id, storage_path, prompt_text, life_stage")
        .eq("id", voiceNoteId)
        .eq("vault_id", vaultId)
        .maybeSingle(),
      5000,
      "DB(voice_notes)"
    );

    if (vnErr) return json(500, { error: vnErr.message });
    if (!vn) return json(403, { error: "Not allowed or not found" });

    const storagePath = textClean(vn.storage_path || "");
    if (!storagePath) return json(400, { error: "voice note storage_path is empty" });

    // 1) Download audio
    const audioBytes = await withTimeout(
      downloadVoiceNoteBytes({ admin, storagePath }),
      12000,
      "download audio"
    );

    // 2) Transcribe
    const transcript = await withTimeout(
      transcribeWithOpenAI({ apiKey: OPENAI_API_KEY, audioBytes }),
      25000,
      "transcription"
    );

    if (!transcript) {
      return json(200, { ok: true, transcript: "", chunk_count: 0, note: "No speech detected." });
    }

    // 3) Find or create a memory row for this voice note
    let memoryId = "";

    const { data: mapping } = await admin
      .from("voice_note_memories")
      .select("memory_id")
      .eq("voice_note_id", voiceNoteId)
      .maybeSingle();

    if (mapping?.memory_id) {
      memoryId = textClean(mapping.memory_id);
    }

    const memPrompt = textClean(vn.prompt_text || "") || "Voice note";
    const lifeStage = textClean(vn.life_stage || "");
    const fullPrompt = lifeStage
      ? `Voice note (${lifeStage}): ${memPrompt}`
      : `Voice note: ${memPrompt}`;

    if (!memoryId) {
      const { data: inserted, error: insErr } = await admin
        .from("memories")
        .insert({
          vault_id: vaultId,
          prompt_text: fullPrompt,
          body: transcript,
        })
        .select("id")
        .maybeSingle();

      if (insErr) return json(500, { error: `memories insert failed: ${insErr.message}` });

      memoryId = textClean(inserted?.id || "");
      if (!memoryId) return json(500, { error: "Failed to create memory id" });

      await admin.from("voice_note_memories").insert({
        voice_note_id: voiceNoteId,
        memory_id: memoryId,
        vault_id: vaultId,
      });
    } else {
      // Update existing memory for this voice note
      await admin
        .from("memories")
        .update({
          prompt_text: fullPrompt,
          body: transcript,
        })
        .eq("id", memoryId);
    }

    // 4) Chunk into memory_chunks (your AI already reads this)
    const chunks = chunkText(`Q: ${fullPrompt}\nA: ${transcript}`, 900);

    // delete old chunks for this memory first (clean)
    await admin
      .from("memory_chunks")
      .delete()
      .eq("vault_id", vaultId)
      .eq("memory_id", memoryId);

    const payloadChunks = chunks.map((t, i) => ({
      vault_id: vaultId,
      memory_id: memoryId,
      chunk_index: i,
      chunk_text: t,
    }));

    if (payloadChunks.length) {
      const { error: cErr } = await admin.from("memory_chunks").insert(payloadChunks);
      if (cErr) return json(500, { error: `memory_chunks insert failed: ${cErr.message}` });
    }

    return json(200, {
      ok: true,
      voice_note_id: voiceNoteId,
      memory_id: memoryId,
      chunk_count: payloadChunks.length,
      transcript_preview: transcript.slice(0, 220),
    });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});