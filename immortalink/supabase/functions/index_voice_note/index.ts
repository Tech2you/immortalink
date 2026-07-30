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

function guessFileForPath(storagePath: string): { filename: string; mime: string } {
  const lower = (storagePath || "").toLowerCase();
  if (lower.endsWith(".webm")) return { filename: "voice_note.webm", mime: "audio/webm" };
  if (lower.endsWith(".m4a")) return { filename: "voice_note.m4a", mime: "audio/mp4" };
  if (lower.endsWith(".mp3")) return { filename: "voice_note.mp3", mime: "audio/mpeg" };
  if (lower.endsWith(".wav")) return { filename: "voice_note.wav", mime: "audio/wav" };
  if (lower.endsWith(".aac")) return { filename: "voice_note.aac", mime: "audio/aac" };
  if (lower.endsWith(".ogg")) return { filename: "voice_note.ogg", mime: "audio/ogg" };
  // fallback
  return { filename: "voice_note.bin", mime: "application/octet-stream" };
}

async function downloadVoiceNoteBytes({
  admin,
  storagePath,
}: {
  admin: any;
  storagePath: string;
}): Promise<Uint8Array> {
  // ✅ Your actual bucket for memory voice notes
  const bucket = "memory_voice";

  const { data, error } = await admin.storage
    .from(bucket)
    .createSignedUrl(storagePath, 60 * 60);

  if (error || !data?.signedUrl) {
    throw new Error(`Signed URL failed for bucket="${bucket}" path="${storagePath}": ${error?.message || "No signedUrl"}`);
  }

  const resp = await fetch(data.signedUrl);
  if (!resp.ok) throw new Error(`Fetch audio failed ${resp.status}`);

  const buf = new Uint8Array(await resp.arrayBuffer());
  if (!buf.length) throw new Error("Empty audio file");
  return buf;
}

async function transcribeWithOpenAI({
  apiKey,
  audioBytes,
  storagePath,
}: {
  apiKey: string;
  audioBytes: Uint8Array;
  storagePath: string;
}): Promise<string> {
  const form = new FormData();
  form.append("model", "gpt-4o-mini-transcribe");

  const { filename, mime } = guessFileForPath(storagePath);
  const file = new File([audioBytes], filename, { type: mime });
  form.append("file", file);

  const resp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });

  if (!resp.ok) {
    const t = await resp.text().catch(() => "");
    throw new Error(`OpenAI transcription failed ${resp.status}: ${t}`);
  }

  const data = await resp.json().catch(() => ({}));
  return textClean((data?.text ?? "").toString());
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
      return json(500, {
        error:
          "Missing SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY in function env.",
      });
    }
    if (!OPENAI_API_KEY) {
      return json(500, { error: "Missing OPENAI_API_KEY in Edge Function secrets." });
    }

    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization") || "";

    // User client (RLS enforced)
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    // Admin client (bypass RLS)
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Verify JWT (this is why your Flutter invoke MUST send Authorization header)
    const { data: u, error: uErr } = await userClient.auth.getUser();
    if (uErr || !u?.user) return json(401, { error: "Invalid/missing JWT" });

    const payload = await req.json().catch(() => ({}));

    const vaultId = textClean(payload?.vault_id || payload?.vaultId || "");
    const memoryVoiceNoteId = textClean(
      payload?.memory_voice_note_id || payload?.memoryVoiceNoteId || payload?.memory_voice_noteId || ""
    );
    const legacyMemoryVoiceNoteId = textClean(
      payload?.legacy_memory_voice_note_id || payload?.legacyMemoryVoiceNoteId || ""
    );
    const legacyMemberId = textClean(
      payload?.legacy_member_id || payload?.legacyMemberId || ""
    );
    const familyId = textClean(payload?.family_id || payload?.familyId || "");

    if (legacyMemoryVoiceNoteId) {
      let legacyQuery = userClient
        .from("legacy_memory_voice_notes")
        .select("id, legacy_memory_id, legacy_member_id, family_id, title, path, created_at")
        .eq("id", legacyMemoryVoiceNoteId);
      if (legacyMemberId) legacyQuery = legacyQuery.eq("legacy_member_id", legacyMemberId);
      if (familyId) legacyQuery = legacyQuery.eq("family_id", familyId);

      const { data: legacyVn, error: legacyVnErr } = await withTimeout(
        legacyQuery.maybeSingle(),
        5000,
        "DB(legacy_memory_voice_notes)"
      );

      if (legacyVnErr) return json(500, { error: legacyVnErr.message });
      if (!legacyVn) return json(403, { error: "Not allowed or not found" });

      const legacyMemoryId = textClean(legacyVn.legacy_memory_id || "");
      const storagePath = textClean(legacyVn.path || "");

      if (!legacyMemoryId) return json(400, { error: "legacy_memory_id is empty on legacy_memory_voice_notes row" });
      if (!storagePath) return json(400, { error: "path is empty on legacy_memory_voice_notes row" });

      const audioBytes = await withTimeout(
        downloadVoiceNoteBytes({ admin, storagePath }),
        15000,
        "download audio"
      );

      const transcript = await withTimeout(
        transcribeWithOpenAI({ apiKey: OPENAI_API_KEY, audioBytes, storagePath }),
        30000,
        "transcription"
      );

      if (!transcript) {
        return json(200, {
          ok: true,
          legacy_memory_voice_note_id: legacyMemoryVoiceNoteId,
          legacy_memory_id: legacyMemoryId,
          chunk_count: 0,
          note: "No speech detected.",
        });
      }

      await admin
        .from("legacy_memory_voice_notes")
        .update({ transcript })
        .eq("id", legacyMemoryVoiceNoteId);

      return json(200, {
        ok: true,
        legacy_memory_voice_note_id: legacyMemoryVoiceNoteId,
        legacy_memory_id: legacyMemoryId,
        chunk_count: 0,
        transcript_preview: transcript.slice(0, 240),
      });
    }

    if (!vaultId) return json(400, { error: "vault_id is required" });
    if (!memoryVoiceNoteId) return json(400, { error: "memory_voice_note_id is required" });

    // ✅ Fetch from *your* VN table
    const { data: vn, error: vnErr } = await withTimeout(
      userClient
        .from("memory_voice_notes")
        .select("id, vault_id, memory_id, title, path, created_at")
        .eq("id", memoryVoiceNoteId)
        .eq("vault_id", vaultId)
        .maybeSingle(),
      5000,
      "DB(memory_voice_notes)"
    );

    if (vnErr) return json(500, { error: vnErr.message });
    if (!vn) return json(403, { error: "Not allowed or not found" });

    const memoryId = textClean(vn.memory_id || "");
    const storagePath = textClean(vn.path || "");
    const title = textClean(vn.title || "Voice note");

    if (!memoryId) return json(400, { error: "memory_id is empty on memory_voice_notes row" });
    if (!storagePath) return json(400, { error: "path is empty on memory_voice_notes row" });

    // 1) Download audio
    const audioBytes = await withTimeout(
      downloadVoiceNoteBytes({ admin, storagePath }),
      15000,
      "download audio"
    );

    // 2) Transcribe
    const transcript = await withTimeout(
      transcribeWithOpenAI({ apiKey: OPENAI_API_KEY, audioBytes, storagePath }),
      30000,
      "transcription"
    );

    if (!transcript) {
      return json(200, {
        ok: true,
        memory_voice_note_id: memoryVoiceNoteId,
        memory_id: memoryId,
        chunk_count: 0,
        note: "No speech detected.",
      });
    }

    await admin
      .from("memory_voice_notes")
      .update({ transcript })
      .eq("id", memoryVoiceNoteId);

    // 3) Rebuild the complete memory context so a new voice note never
    // replaces the written memory or an earlier voice note.
    const { data: memory, error: memoryErr } = await admin
      .from("memories")
      .select("prompt_text, body, memory_date_label, people, location, mood")
      .eq("id", memoryId)
      .eq("vault_id", vaultId)
      .maybeSingle();
    if (memoryErr) return json(500, { error: memoryErr.message });

    const { data: allVoiceNotes, error: notesErr } = await admin
      .from("memory_voice_notes")
      .select("title, transcript, created_at")
      .eq("vault_id", vaultId)
      .eq("memory_id", memoryId)
      .order("created_at", { ascending: true });
    if (notesErr) return json(500, { error: notesErr.message });

    const voiceContext = (allVoiceNotes || [])
      .map((note: any, index: number) => {
        const noteTranscript = (note?.transcript || "").toString().trim();
        if (!noteTranscript) return "";
        const noteTitle = (note?.title || "Voice note").toString().trim();
        return `Voice note ${index + 1} (${noteTitle}):\n${noteTranscript}`;
      })
      .filter(Boolean);

    const fullText = [
      memory?.prompt_text ? `Title: ${memory.prompt_text}` : "",
      memory?.body ? `Memory: ${memory.body}` : "",
      memory?.memory_date_label ? `When: ${memory.memory_date_label}` : "",
      memory?.people ? `People: ${memory.people}` : "",
      memory?.location ? `Location: ${memory.location}` : "",
      memory?.mood ? `Mood: ${memory.mood}` : "",
      ...voiceContext,
    ].filter(Boolean).join("\n");
    const chunks = chunkText(fullText, 900);

    // Clean old chunks for this memory before inserting the complete rebuild.
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
      memory_voice_note_id: memoryVoiceNoteId,
      memory_id: memoryId,
      chunk_count: payloadChunks.length,
      transcript_preview: transcript.slice(0, 240),
    });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});
