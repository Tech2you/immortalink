// supabase/functions/vault_ai_chat/index.ts
// Edge Function: vault_ai_chat
// ✅ Uses caller JWT so RLS applies (secure)
// ✅ Uses memory_chunks.chunk_text + chunk_index (matches your schema)
// ✅ Viewer context: owner vs visitor + relationship (relative to vault owner)
// ✅ Forces correct “speaker” perspective: AI speaks as vault owner (“I/me”), visitor is “you”
// ✅ Strict grounding + labeled Era context

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") || "";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function textClean(s: string) {
  return (s || "").replace(/\s+/g, " ").trim();
}

async function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  const res = await Promise.race([
    p,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms),
    ),
  ]);
  return res as T;
}

/**
 * Viewer relation to OWNER from the viewer's slot_key.
 * IMPORTANT: slot_key is assigned to the *viewer* in family_members.
 */
function viewerRelationFromSlotKey(slotKeyRaw: string): string {
  const slotKey = (slotKeyRaw || "").toLowerCase().trim();
  if (!slotKey) return "unknown";

  // Parents of the owner
  if (slotKey === "mother" || slotKey === "father") return "parent";

  // Children of the owner
  if (slotKey.startsWith("child_") || slotKey === "child_left" || slotKey === "child_right") return "child";

  // Descendants layers (children of children etc)
  if (slotKey.startsWith("grandchild_")) return "grandchild";
  if (slotKey.startsWith("greatgrandchild_")) return "great-grandchild";

  // Grandparents of the owner
  if (
    slotKey === "maternal_gm" ||
    slotKey === "maternal_gf" ||
    slotKey === "paternal_gm" ||
    slotKey === "paternal_gf"
  ) return "grandparent";

  // Great-grandparents of the owner (your slot keys)
  if (
    slotKey === "maternal_ggm" ||
    slotKey === "maternal_ggf" ||
    slotKey === "paternal_ggm" ||
    slotKey === "paternal_ggf"
  ) return "great-grandparent";

  if (slotKey === "spouse_1") return "spouse";
  if (slotKey.startsWith("sibling_")) return "sibling";

  return "unknown";
}

/**
 * Invert viewer->owner relation into owner->viewer relation.
 * Example: viewer is "great-grandchild" => owner is "great-grandparent"
 */
function invertRelation(viewerRel: string): string {
  const r = (viewerRel || "").toLowerCase().trim();

  if (r === "owner") return "owner";
  if (r === "parent") return "child";
  if (r === "child") return "parent";

  if (r === "grandparent") return "grandchild";
  if (r === "grandchild") return "grandparent";

  if (r === "great-grandparent") return "great-grandchild";
  if (r === "great-grandchild") return "great-grandparent";

  if (r === "sibling") return "sibling";
  if (r === "spouse") return "spouse";

  return "family member";
}

async function openaiChat({
  question,
  context,
  displayName,
  viewerContextLine,
}: {
  question: string;
  context: string;
  displayName: string;
  viewerContextLine: string;
}) {
  if (!OPENAI_API_KEY) {
    return {
      ok: false,
      error:
        "OPENAI_API_KEY is not set in Edge Function secrets (Supabase Dashboard → Edge Functions → Secrets).",
    };
  }

  const system = `
You are the ImmortaLink "Vault Companion".

CRITICAL ROLE RULE:
- You are speaking AS ${displayName} (the vault owner).
- The person chatting is the viewer/visitor ("you").
- Never describe yourself as the viewer (do NOT say "as your grandchild..." if the viewer is the grandchild).
- If relationship is known, use one of these exact patterns:
  1) "I am your <owner_to_viewer_relation>."
  2) "You are my <viewer_to_owner_relation>."
- If relationship is unknown, say: "You are a family member with access to this vault."

Viewer context:
${viewerContextLine}

Grounding rules:
- Use ONLY the vault context for personal facts, memories, life events, names, dates, places, sports, hobbies.
- If it is not explicitly in vault context, say you’re not sure and suggest what memory to add.
- You MAY give general historical context, but label it as "Era context" and never claim it as a personal memory unless it's in the vault.
- Be warm, human, and concise. Avoid long essays.
- Never invent details.
`;

  const user = `
Vault context (may be empty):
${context || "(no saved memories found)"}

User question:
${question}
`;

  const body = {
    model: "gpt-4o-mini",
    temperature: 0.4,
    max_tokens: 260,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);

  try {
    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify(body),
    });

    if (!resp.ok) {
      const errTxt = await resp.text().catch(() => "");
      return { ok: false, error: `OpenAI error ${resp.status}: ${errTxt}` };
    }

    const data = await resp.json();
    const answer = data?.choices?.[0]?.message?.content?.toString() ?? "";
    return {
      ok: true,
      answer: answer.trim() || "I’m not sure yet — add more memories to this vault.",
    };
  } catch (e: any) {
    return { ok: false, error: `OpenAI request failed: ${e?.message ?? String(e)}` };
  } finally {
    clearTimeout(timeout);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || req.headers.get("authorization") || "";

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) return json({ error: "Not authenticated" }, 401);

    const viewerUserId = userData.user.id;

    const payload = await req.json().catch(() => ({}));
    const vaultId = textClean(payload?.vaultId || payload?.vault_id || "");
    const question = textClean(payload?.question || payload?.prompt || payload?.message || "");
    const displayName = textClean(payload?.displayName || payload?.display_name || "this person");

    // Optional future (safe now): viewerDisplayName
    const viewerDisplayName = textClean(payload?.viewerDisplayName || payload?.viewer_display_name || "");

    if (!vaultId) return json({ error: "vaultId is required" }, 400);
    if (!question) return json({ error: "question is required" }, 400);

    // Fetch vault owner + family_id (RLS must allow viewer to see this vault)
    const { data: vaultRow, error: vErr } = await withTimeout(
      supabase
        .from("vaults")
        .select("id, owner_id, family_id")
        .eq("id", vaultId)
        .maybeSingle(),
      4_000,
      "DB(vaults)"
    );

    if (vErr) return json({ error: `DB error: ${vErr.message}` }, 500);
    if (!vaultRow) return json({ error: "Vault not found or not allowed" }, 403);

    const vaultOwnerUserId = textClean(vaultRow.owner_id || "");
    const familyId = textClean(vaultRow.family_id || "");
    const isOwnerAsking = viewerUserId === vaultOwnerUserId;

    // Relationship relative to vault owner (MVP reliable source: family_members.slot_key)
    let viewerRole = isOwnerAsking ? "owner" : "visitor";
    let viewerSlotKey = "";
    let viewerToOwner = isOwnerAsking ? "owner" : "unknown";
    let ownerToViewer = isOwnerAsking ? "owner" : "family member";

    if (!isOwnerAsking && familyId) {
      try {
        const { data: fm, error: fmErr } = await withTimeout(
          supabase
            .from("family_members")
            .select("role, slot_key")
            .eq("family_id", familyId)
            .eq("user_id", viewerUserId)
            .maybeSingle(),
          3_000,
          "DB(family_members)"
        );

        if (!fmErr && fm) {
          viewerRole = textClean(fm.role || viewerRole) || viewerRole;
          viewerSlotKey = textClean(fm.slot_key || "");
          viewerToOwner = viewerRelationFromSlotKey(viewerSlotKey);
          ownerToViewer = invertRelation(viewerToOwner);
        }
      } catch (_) {
        // ignore MVP
      }
    }

    const whoLine = viewerDisplayName
      ? `Viewer name: ${viewerDisplayName}`
      : "Viewer name: (not provided)";

    const viewerContextLine = isOwnerAsking
      ? `The person asking is the VAULT OWNER.\n${whoLine}`
      : `The person asking is the viewer/visitor.\nRelationship (viewer → owner): ${viewerToOwner}\nRelationship (owner → viewer): ${ownerToViewer}\nSlot key (viewer): ${viewerSlotKey || "(unknown)"}\nRole (viewer): ${viewerRole}\n${whoLine}`;

    // Context fetch: memory_chunks first (chunk_text), then fallback to memories
    let contextParts: string[] = [];

    try {
      const { data: chunks, error: chunkErr } = await withTimeout(
        supabase
          .from("memory_chunks")
          .select("chunk_text, chunk_index, created_at")
          .eq("vault_id", vaultId)
          .order("created_at", { ascending: false })
          .order("chunk_index", { ascending: true })
          .limit(14),
        4_000,
        "DB(memory_chunks)"
      );

      if (!chunkErr && Array.isArray(chunks) && chunks.length > 0) {
        for (const c of chunks) {
          const content = textClean((c as any)?.chunk_text || "");
          if (content) contextParts.push(content);
        }
      }
    } catch (_) {
      // ignore, fallback below
    }

    if (contextParts.length === 0) {
      const { data: memories, error: memErr } = await withTimeout(
        supabase
          .from("memories")
          .select("prompt_text, body")
          .eq("vault_id", vaultId)
          .order("created_at", { ascending: false })
          .limit(8),
        4_000,
        "DB(memories)"
      );

      if (memErr) return json({ error: `DB error: ${memErr.message}` }, 500);

      const list = (memories as any[]) || [];
      for (const m of list) {
        const p = textClean(m?.prompt_text || "");
        const b = textClean(m?.body || "");
        if (p || b) contextParts.push(`Q: ${p}\nA: ${b}`.trim());
      }
    }

    const context = contextParts.join("\n\n").slice(0, 6500);

    const ai = await openaiChat({
      question,
      context,
      displayName,
      viewerContextLine,
    });

    if (!ai.ok) {
      console.error("vault_ai_chat OpenAI failure:", ai.error);
      return json(
        {
          answer: "Sorry — I couldn’t generate a reply right now. Please try again in a moment.",
          debug: ai.error,
        },
        200
      );
    }

    return json({ answer: ai.answer }, 200);
  } catch (e: any) {
    console.error("vault_ai_chat fatal:", e);
    return json({ error: e?.message ?? String(e) }, 500);
  }
});