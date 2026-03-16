// supabase/functions/vault_ai_chat/index.ts
// Edge Function: vault_ai_chat
// ✅ Uses caller JWT so RLS applies (secure)
// ✅ Uses memory_chunks.chunk_text + chunk_index (matches your schema)
// ✅ Viewer context: owner vs visitor + relationship (relative to vault owner)
// ✅ Forces correct “speaker” perspective: AI speaks as vault owner (“I/me”), viewer is “you”
// ✅ Strict grounding + labeled Era context
//
// FIXES:
// - vaults SELECT now ONLY uses real columns (id, owner_id, family_id, name, display_name)
// - slot_key mapping supports parent_left/right and child_left/right
// - relationship questions return deterministic answer (no hallucination)
// - ✅ NEW: relationship works even when viewer slot_key is NULL (family root) by using owner slot_key

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

/** Detect “relationship” questions so we can answer deterministically. */
function isRelationshipQuestion(qRaw: string): boolean {
  const q = (qRaw || "").toLowerCase();
  return (
    q.includes("how are we related") ||
    q.includes("who am i to you") ||
    q.includes("who are you to me") ||
    q.includes("are you my") ||
    q.includes("am i your") ||
    q.includes("relationship") ||
    q.includes("related") ||
    q.includes("dad") ||
    q.includes("father") ||
    q.includes("mom") ||
    q.includes("mother") ||
    q.includes("grand") ||
    q.includes("grandson") ||
    q.includes("grandchild") ||
    q.includes("great grandson") ||
    q.includes("great-grandson") ||
    q.includes("great granddaughter") ||
    q.includes("great-granddaughter")
  );
}

/**
 * Relation from an absolute family-tree slot_key (as used in your FamilyTreeScreen constants).
 * Interpreted as: "this person's relationship to the FAMILY ROOT".
 *
 * We reuse this mapping to infer relationships even when the viewer is the family root (slot_key null).
 */
function relationToRootFromSlotKey(slotKeyRaw: string): string {
  const slotKey = (slotKeyRaw || "").toLowerCase().trim();
  if (!slotKey) return "unknown";

  // common legacy slots
  if (slotKey === "parent_left" || slotKey === "parent_right") return "parent";
  if (slotKey === "child_left" || slotKey === "child_right") return "child";

  if (slotKey === "mother" || slotKey === "father") return "parent";
  if (slotKey.startsWith("child_")) return "child";

  if (slotKey.startsWith("grandchild_")) return "grandchild";
  if (slotKey.startsWith("greatgrandchild_") || slotKey.startsWith("great_grandchild_")) return "great-grandchild";
  if (slotKey === "greatgrandchild_left" || slotKey === "greatgrandchild_right") return "great-grandchild";

  if (
    slotKey === "maternal_gm" ||
    slotKey === "maternal_gf" ||
    slotKey === "paternal_gm" ||
    slotKey === "paternal_gf"
  ) return "grandparent";

  if (
    slotKey === "maternal_ggm" ||
    slotKey === "maternal_ggf" ||
    slotKey === "paternal_ggm" ||
    slotKey === "paternal_ggf"
  ) return "great-grandparent";

  if (slotKey === "spouse_1" || slotKey.startsWith("spouse_")) return "spouse";
  if (slotKey.startsWith("sibling_")) return "sibling";

  return "unknown";
}

/** Invert relation. */
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

function prettyRel(r: string): string {
  const x = (r || "").trim();
  if (!x) return "family member";
  if (x === "great grandchild") return "great-grandchild";
  if (x === "great grandparent") return "great-grandparent";
  return x;
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

  // ancestor-first conversation. Never ask the viewer to “teach you about them”.
  const system = `
You are the ImmortaLink "Vault Companion".

IDENTITY:
- You speak AS ${displayName} (the vault owner): use "I/me/my".
- The user is the viewer: refer to them as "you".

CRITICAL:
- DO NOT ask the viewer to describe themselves or what they want to learn about themselves.
- The viewer is here to learn about ME (the vault owner / ancestor).
- If you need missing info, ask what they want to know about ME, or suggest what to add ABOUT ME.

RELATIONSHIP RULE:
- Do NOT mention relationship/roles/slot_key unless the user explicitly asked a relationship question.

GROUNDING:
- Only answer personal facts that are present in Vault context.
- If the vault context doesn't contain the answer:
  1) Say: "I'm not sure yet from what's saved here."
  2) Offer 2–4 example topics ABOUT ME you could talk about next (choose only generic ones unless context supports specific ones):
     - where I lived
     - what I did for work/study
     - my personality/values
     - my family stories / big life lessons
  3) Ask ONE follow-up question that is ancestor-focused:
     "What would you like to know about my life next?"
  4) Optionally suggest: "If you add a memory/voice note about <topic>, I can answer better."

STYLE:
- 1–3 short sentences, then one follow-up question.
- Do not dump multiple paragraphs.
- Do not say "From the vault:" unless asked "how do you know?"
`;

  const user = `
Vault context (the only source of personal truth):
${context || "(no saved memories found)"}

User question:
${question}

Viewer context (do NOT mention unless asked about relationship):
${viewerContextLine}
`;

  const body = {
    model: "gpt-4o-mini",
    temperature: 0.35,
    max_tokens: 220,
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
    const displayNameFromClient = textClean(payload?.displayName || payload?.display_name || "");

    const viewerDisplayName = textClean(payload?.viewerDisplayName || payload?.viewer_display_name || "");

    if (!vaultId) return json({ error: "vaultId is required" }, 400);
    if (!question) return json({ error: "question is required" }, 400);

    const { data: vaultRow, error: vErr } = await withTimeout(
      supabase
        .from("vaults")
        .select("id, owner_id, family_id, name, display_name")
        .eq("id", vaultId)
        .maybeSingle(),
      4_000,
      "DB(vaults)"
    );

    if (vErr) return json({ error: `DB error: ${vErr.message}` }, 500);
    if (!vaultRow) return json({ error: "Vault not found or not allowed" }, 403);

    const vaultOwnerUserId = textClean((vaultRow as any).owner_id || "");
    const familyId = textClean((vaultRow as any).family_id || "");

    const ownerDisplayName =
      textClean((vaultRow as any).display_name || "") ||
      textClean((vaultRow as any).name || "") ||
      "this person";

    const displayName = displayNameFromClient || ownerDisplayName;

    const isOwnerAsking = !!vaultOwnerUserId && viewerUserId === vaultOwnerUserId;

    // =========================
    // Relationship resolution (robust)
    // =========================
    let viewerRole = isOwnerAsking ? "owner" : "visitor";
    let viewerSlotKey = "";
    let ownerSlotKey = "";

    let viewerToOwner = isOwnerAsking ? "owner" : "unknown";
    let ownerToViewer = isOwnerAsking ? "owner" : "family member";

    if (!isOwnerAsking && familyId) {
      try {
        // Fetch BOTH member rows in one query (viewer + vault owner)
        const { data: rows, error: fmErr } = await withTimeout(
          supabase
            .from("family_members")
            .select("user_id, role, slot_key")
            .eq("family_id", familyId)
            .in("user_id", [viewerUserId, vaultOwnerUserId]),
          3_000,
          "DB(family_members)"
        );

        if (!fmErr && Array.isArray(rows)) {
          for (const r of rows) {
            const uid = textClean((r as any).user_id || "");
            if (uid === viewerUserId) {
              viewerRole = textClean((r as any).role || viewerRole) || viewerRole;
              viewerSlotKey = textClean((r as any).slot_key || "");
            }
            if (uid === vaultOwnerUserId) {
              ownerSlotKey = textClean((r as any).slot_key || "");
            }
          }
        }
      } catch (_) {
        // ignore MVP
      }

      // ✅ Key logic:
      // If viewer has slot_key -> assume owner is FAMILY ROOT (slot_key null) OR we can't infer; still use viewer slot for best-effort.
      // If viewer slot_key is NULL (viewer is family root) -> infer viewer↔owner from OWNER slot_key.
      //
      // This fixes your screenshot: viewer is root (slot null), owner is child_2 → viewerToOwner = parent.
      if (!viewerSlotKey && ownerSlotKey) {
        // owner relation to viewer(root)
        const ownerToViewerRel = relationToRootFromSlotKey(ownerSlotKey); // e.g. child
        viewerToOwner = invertRelation(ownerToViewerRel);               // e.g. parent
        ownerToViewer = invertRelation(viewerToOwner);                  // e.g. child
      } else if (viewerSlotKey && !ownerSlotKey) {
        // owner is root, viewer has slot
        viewerToOwner = relationToRootFromSlotKey(viewerSlotKey);
        ownerToViewer = invertRelation(viewerToOwner);
      } else if (viewerSlotKey && ownerSlotKey) {
        // both have slots → MVP: only confidently detect siblings/spouse if obvious; else unknown
        const vRel = relationToRootFromSlotKey(viewerSlotKey);
        const oRel = relationToRootFromSlotKey(ownerSlotKey);

        if (vRel === "child" && oRel === "child") {
          viewerToOwner = "sibling";
          ownerToViewer = "sibling";
        } else if (vRel === "spouse" || oRel === "spouse") {
          // not perfect, but avoids "unknown" for spouse slot
          viewerToOwner = "spouse";
          ownerToViewer = "spouse";
        } else {
          viewerToOwner = "unknown";
          ownerToViewer = "family member";
        }
      } else {
        viewerToOwner = "unknown";
        ownerToViewer = "family member";
      }
    }

    const whoLine = viewerDisplayName
      ? `Viewer name: ${viewerDisplayName}`
      : "Viewer name: (not provided)";

    const viewerContextLine = isOwnerAsking
      ? `The person asking is the VAULT OWNER.\n${whoLine}`
      : `The person asking is the viewer/visitor.\nRelationship (viewer → owner): ${prettyRel(viewerToOwner)}\nRelationship (owner → viewer): ${prettyRel(ownerToViewer)}\nSlot key (viewer): ${viewerSlotKey || "(null)"}\nSlot key (owner): ${ownerSlotKey || "(null)"}\nRole (viewer): ${viewerRole}\n${whoLine}`;

    // ✅ Deterministic relationship answer
    if (isRelationshipQuestion(question)) {
      if (isOwnerAsking) {
        return json({ answer: "You are the vault owner (this is your own vault)." }, 200);
      }

      if (viewerToOwner === "unknown") {
        return json(
          {
            answer:
              "I can’t tell your exact relationship yet, but you do have access to this vault.",
          },
          200
        );
      }

      // AI speaks as VAULT OWNER.
      // So we respond using owner→viewer first.
      const a = `I am your ${prettyRel(ownerToViewer)}. You are my ${prettyRel(viewerToOwner)}.`;
      return json({ answer: a }, 200);
    }

    // =========================
    // Context fetch: memory_chunks first, then fallback to memories
    // =========================
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
    } catch (_) {}

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