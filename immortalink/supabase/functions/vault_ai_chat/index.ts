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

function cosineSimilarity(a: number[], b: number[]) {
  let dot = 0;
  let aLength = 0;
  let bLength = 0;
  const length = Math.min(a.length, b.length);
  for (let i = 0; i < length; i++) {
    dot += a[i] * b[i];
    aLength += a[i] * a[i];
    bLength += b[i] * b[i];
  }
  if (!aLength || !bLength) return 0;
  return dot / (Math.sqrt(aLength) * Math.sqrt(bLength));
}

async function rankContextByMeaning(
  question: string,
  parts: string[],
  maximum = 14,
) {
  if (!OPENAI_API_KEY || parts.length <= maximum) return parts.slice(0, maximum);

  const candidates = parts.slice(0, 60);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: [question, ...candidates],
      }),
    });
    if (!response.ok) return candidates.slice(0, maximum);

    const payload = await response.json();
    const vectors = Array.isArray(payload?.data)
      ? payload.data.map((row: any) => row?.embedding as number[])
      : [];
    const queryVector = vectors[0];
    if (!Array.isArray(queryVector)) return candidates.slice(0, maximum);

    return candidates
      .map((text, index) => ({
        text,
        score: cosineSimilarity(queryVector, vectors[index + 1] || []),
        recency: index,
      }))
      .sort((a, b) => b.score - a.score || a.recency - b.recency)
      .slice(0, maximum)
      .map((item) => item.text);
  } catch (_) {
    return candidates.slice(0, maximum);
  } finally {
    clearTimeout(timeout);
  }
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
    q.includes("sibling") ||
    q.includes("brother") ||
    q.includes("sister") ||
    q.includes("uncle") ||
    q.includes("aunt") ||
    q.includes("niece") ||
    q.includes("nephew") ||
    q.includes("cousin") ||
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

type RelationshipRow = {
  parent_type?: string;
  parent_id?: string;
  child_type?: string;
  child_id?: string;
  relationship_kind?: string;
};

type GraphRelation = {
  viewerToOwner: string;
  ownerToViewer: string;
};

function generationRelation(depth: number, ancestor: boolean): string {
  if (depth <= 0) return "owner";
  if (depth === 1) return ancestor ? "parent" : "child";
  if (depth === 2) return ancestor ? "grandparent" : "grandchild";
  if (depth === 3) {
    return ancestor ? "great-grandparent" : "great-grandchild";
  }
  return `${depth - 2}x great-${ancestor ? "grandparent" : "grandchild"}`;
}

function ancestorDepths(
  start: string,
  parentsByChild: Map<string, string[]>,
): Map<string, number> {
  const depths = new Map<string, number>([[start, 0]]);
  const queue: string[] = [start];

  while (queue.length > 0) {
    const current = queue.shift()!;
    const nextDepth = (depths.get(current) ?? 0) + 1;
    for (const parent of parentsByChild.get(current) ?? []) {
      const existing = depths.get(parent);
      if (existing !== undefined && existing <= nextDepth) continue;
      depths.set(parent, nextDepth);
      queue.push(parent);
    }
  }

  return depths;
}

function cousinLabel(viewerDepth: number, ownerDepth: number): string {
  const degree = Math.min(viewerDepth, ownerDepth) - 1;
  const removed = Math.abs(viewerDepth - ownerDepth);
  const degreeWord = degree === 1
    ? "first"
    : degree === 2
    ? "second"
    : degree === 3
    ? "third"
    : `${degree}th`;
  if (removed === 0) return `${degreeWord} cousin`;
  const removedWord = removed === 1 ? "once" : removed === 2 ? "twice" : `${removed} times`;
  return `${degreeWord} cousin ${removedWord} removed`;
}

function resolveRelationshipFromGraph(
  viewerVaultId: string,
  ownerId: string,
  rows: RelationshipRow[],
  ownerType = "vault",
): GraphRelation | null {
  const viewerKey = `vault:${viewerVaultId}`;
  const ownerKey = `${ownerType}:${ownerId}`;
  if (viewerKey === ownerKey) {
    return { viewerToOwner: "owner", ownerToViewer: "owner" };
  }

  const parentsByChild = new Map<string, string[]>();
  const siblingLinks = new Map<string, Set<string>>();
  let directSpouse = false;
  let directSibling = false;

  for (const row of rows) {
    const first = `${textClean(row.parent_type || "")}:${textClean(row.parent_id || "")}`;
    const second = `${textClean(row.child_type || "")}:${textClean(row.child_id || "")}`;
    const kind = textClean(row.relationship_kind || "");
    if (first === ":" || second === ":") continue;

    const isDirectPair =
      (first === viewerKey && second === ownerKey) ||
      (first === ownerKey && second === viewerKey);
    if (kind === "spouse" && isDirectPair) directSpouse = true;
    if (kind === "sibling") {
      if (isDirectPair) directSibling = true;
      const firstLinks = siblingLinks.get(first) ?? new Set<string>();
      const secondLinks = siblingLinks.get(second) ?? new Set<string>();
      firstLinks.add(second);
      secondLinks.add(first);
      siblingLinks.set(first, firstLinks);
      siblingLinks.set(second, secondLinks);
    }

    if (kind === "parent_child") {
      const parents = parentsByChild.get(second) ?? [];
      if (!parents.includes(first)) parents.push(first);
      parentsByChild.set(second, parents);
    }
  }

  // A direct sibling edge may exist when their shared parent is unknown.
  // Model each connected sibling group with an internal synthetic parent so
  // extended relationships (parent's sibling, cousins, removals) still work.
  const visitedSiblings = new Set<string>();
  let siblingGroupIndex = 0;
  for (const member of siblingLinks.keys()) {
    if (visitedSiblings.has(member)) continue;
    const component: string[] = [];
    const queue = [member];
    visitedSiblings.add(member);
    while (queue.length > 0) {
      const current = queue.shift()!;
      component.push(current);
      for (const sibling of siblingLinks.get(current) ?? []) {
        if (visitedSiblings.has(sibling)) continue;
        visitedSiblings.add(sibling);
        queue.push(sibling);
      }
    }
    if (component.length < 2) continue;
    const syntheticParent = `sibling-group:${siblingGroupIndex++}`;
    for (const sibling of component) {
      const parents = parentsByChild.get(sibling) ?? [];
      if (!parents.includes(syntheticParent)) parents.push(syntheticParent);
      parentsByChild.set(sibling, parents);
    }
  }

  if (directSpouse) {
    return { viewerToOwner: "spouse", ownerToViewer: "spouse" };
  }
  if (directSibling) {
    return { viewerToOwner: "sibling", ownerToViewer: "sibling" };
  }

  const viewerAncestors = ancestorDepths(viewerKey, parentsByChild);
  const ownerAncestors = ancestorDepths(ownerKey, parentsByChild);

  let commonKey = "";
  let bestTotal = Number.MAX_SAFE_INTEGER;
  for (const [key, viewerDepth] of viewerAncestors.entries()) {
    const ownerDepth = ownerAncestors.get(key);
    if (ownerDepth === undefined) continue;
    const total = viewerDepth + ownerDepth;
    if (total < bestTotal) {
      bestTotal = total;
      commonKey = key;
    }
  }

  if (!commonKey) return null;
  const viewerDepth = viewerAncestors.get(commonKey)!;
  const ownerDepth = ownerAncestors.get(commonKey)!;

  if (viewerDepth === 0 && ownerDepth > 0) {
    return {
      viewerToOwner: generationRelation(ownerDepth, true),
      ownerToViewer: generationRelation(ownerDepth, false),
    };
  }
  if (ownerDepth === 0 && viewerDepth > 0) {
    return {
      viewerToOwner: generationRelation(viewerDepth, false),
      ownerToViewer: generationRelation(viewerDepth, true),
    };
  }
  if (viewerDepth === 1 && ownerDepth === 1) {
    return { viewerToOwner: "sibling", ownerToViewer: "sibling" };
  }
  if (viewerDepth === 1 && ownerDepth >= 2) {
    return {
      viewerToOwner: "parent's sibling",
      ownerToViewer: "sibling's child",
    };
  }
  if (ownerDepth === 1 && viewerDepth >= 2) {
    return {
      viewerToOwner: "sibling's child",
      ownerToViewer: "parent's sibling",
    };
  }
  if (viewerDepth >= 2 && ownerDepth >= 2) {
    const label = cousinLabel(viewerDepth, ownerDepth);
    return { viewerToOwner: label, ownerToViewer: label };
  }

  return null;
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
- Connect concrete facts to their natural broader topics when the link is clear.
  For example, exams, grades and studying are academic experiences; jobs and
  qualifications are career experiences. Do not say a broad topic is missing
  when the context contains a directly related concrete fact.
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
- If the relevant memory includes a Mood, gently reflect that emotional character
  (for example warm, playful, restrained, sad, or surprised).
- Never exaggerate the mood, turn it into a performance, or invent an emotion
  that is not present in the Vault context.
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
    const legacyMemberId = textClean(
      payload?.legacyMemberId || payload?.legacy_member_id || "",
    );
    const question = textClean(payload?.question || payload?.prompt || payload?.message || "");
    const displayNameFromClient = textClean(payload?.displayName || payload?.display_name || "");
    const requestedFamilyId = textClean(payload?.familyId || payload?.family_id || "");

    const viewerDisplayName = textClean(payload?.viewerDisplayName || payload?.viewer_display_name || "");

    const isLegacyChat = !vaultId && !!legacyMemberId;

    if (!vaultId && !legacyMemberId) {
      return json({ error: "vaultId or legacyMemberId is required" }, 400);
    }
    if (!question) return json({ error: "question is required" }, 400);

    let familyId = requestedFamilyId;
    let vaultOwnerUserId = "";
    let ownerDisplayName = "this person";
    let legacyRow: any = null;

    if (isLegacyChat) {
      let legacyQuery = supabase
        .from("legacy_family_members")
        .select("id, family_id, slot_key, name, display_name, about_me_text")
        .eq("id", legacyMemberId);
      if (requestedFamilyId) {
        legacyQuery = legacyQuery.eq("family_id", requestedFamilyId);
      }

      const { data: row, error: legacyErr } = await withTimeout(
        legacyQuery.maybeSingle(),
        4_000,
        "DB(legacy_family_members)"
      );

      if (legacyErr) return json({ error: `DB error: ${legacyErr.message}` }, 500);
      if (!row) return json({ error: "Legacy profile not found or not allowed" }, 403);

      legacyRow = row;
      familyId = requestedFamilyId || textClean((legacyRow as any).family_id || "");
      ownerDisplayName =
        textClean((legacyRow as any).display_name || "") ||
        textClean((legacyRow as any).name || "") ||
        "this person";
    } else {
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

      vaultOwnerUserId = textClean((vaultRow as any).owner_id || "");
      familyId = requestedFamilyId || textClean((vaultRow as any).family_id || "");

      if (requestedFamilyId) {
        const { data: sharedRows, error: sharedErr } = await withTimeout(
          supabase
            .from("family_members")
            .select("user_id")
            .eq("family_id", requestedFamilyId)
            .in("user_id", [viewerUserId, vaultOwnerUserId]),
          3_000,
          "DB(active family membership)",
        );
        const sharedIds = new Set(
          Array.isArray(sharedRows)
            ? sharedRows.map((row) => textClean((row as any).user_id || ""))
            : [],
        );
        if (
          sharedErr ||
          !sharedIds.has(viewerUserId) ||
          !sharedIds.has(vaultOwnerUserId)
        ) {
          return json({ error: "Vault is not part of the selected family" }, 403);
        }
      }

      ownerDisplayName =
        textClean((vaultRow as any).display_name || "") ||
        textClean((vaultRow as any).name || "") ||
        "this person";
    }

    const displayName = displayNameFromClient || ownerDisplayName;

    const isOwnerAsking = !isLegacyChat && !!vaultOwnerUserId && viewerUserId === vaultOwnerUserId;

    // =========================
    // Relationship resolution (robust)
    // =========================
    let viewerRole = isOwnerAsking ? "owner" : "visitor";
    let viewerSlotKey = "";
    let ownerSlotKey = "";

    let viewerToOwner = isOwnerAsking ? "owner" : "unknown";
    let ownerToViewer = isOwnerAsking ? "owner" : "family member";
    let resolvedByGraph = false;

    if (!isOwnerAsking && familyId) {
      try {
        const { data: viewerVault } = await withTimeout(
          supabase
            .from("vaults")
            .select("id")
            .eq("owner_id", viewerUserId)
            .maybeSingle(),
          3_000,
          "DB(viewer vault)"
        );

        const viewerVaultId = textClean((viewerVault as any)?.id || "");
        if (viewerVaultId) {
          const { data: graphRows, error: graphErr } = await withTimeout(
            supabase
              .from("family_relationships")
              .select(
                "parent_type, parent_id, child_type, child_id, relationship_kind",
              )
              .eq("family_id", familyId),
            4_000,
            "DB(family relationship graph)"
          );

          if (!graphErr && Array.isArray(graphRows)) {
            const graphRelation = resolveRelationshipFromGraph(
              viewerVaultId,
              isLegacyChat ? legacyMemberId : vaultId,
              graphRows as RelationshipRow[],
              isLegacyChat ? "legacy" : "vault",
            );
            if (graphRelation) {
              viewerToOwner = graphRelation.viewerToOwner;
              ownerToViewer = graphRelation.ownerToViewer;
              resolvedByGraph = true;
            }
          }
        }
      } catch (_) {
        // Keep the proven slot-key resolver below as a compatibility fallback.
      }

      try {
        // Fetch BOTH member rows in one query (viewer + vault owner)
        const { data: rows, error: fmErr } = await withTimeout(
          supabase
            .from("family_members")
            .select("user_id, role, slot_key")
            .eq("family_id", familyId)
            .in(
              "user_id",
              isLegacyChat ? [viewerUserId] : [viewerUserId, vaultOwnerUserId],
            ),
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
            if (!isLegacyChat && uid === vaultOwnerUserId) {
              ownerSlotKey = textClean((r as any).slot_key || "");
            }
          }
        }
      } catch (_) {
        // ignore MVP
      }
      if (isLegacyChat) {
        ownerSlotKey = textClean((legacyRow as any)?.slot_key || "");
      }

      // ✅ Key logic:
      // If viewer has slot_key -> assume owner is FAMILY ROOT (slot_key null) OR we can't infer; still use viewer slot for best-effort.
      // If viewer slot_key is NULL (viewer is family root) -> infer viewer↔owner from OWNER slot_key.
      //
      // This fixes your screenshot: viewer is root (slot null), owner is child_2 → viewerToOwner = parent.
      if (!resolvedByGraph && !viewerSlotKey && ownerSlotKey) {
        // owner relation to viewer(root)
        const ownerToViewerRel = relationToRootFromSlotKey(ownerSlotKey); // e.g. child
        viewerToOwner = invertRelation(ownerToViewerRel);               // e.g. parent
        ownerToViewer = invertRelation(viewerToOwner);                  // e.g. child
      } else if (!resolvedByGraph && viewerSlotKey && !ownerSlotKey) {
        // owner is root, viewer has slot
        viewerToOwner = relationToRootFromSlotKey(viewerSlotKey);
        ownerToViewer = invertRelation(viewerToOwner);
      } else if (!resolvedByGraph && viewerSlotKey && ownerSlotKey) {
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
      } else if (!resolvedByGraph) {
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
      if (!isLegacyChat) {
        const { data: chunks, error: chunkErr } = await withTimeout(
          supabase
            .from("memory_chunks")
            .select("chunk_text, chunk_index, created_at")
            .eq("vault_id", vaultId)
            .order("created_at", { ascending: false })
            .order("chunk_index", { ascending: true })
            .limit(60),
          4_000,
          "DB(memory_chunks)"
        );

        if (!chunkErr && Array.isArray(chunks) && chunks.length > 0) {
          for (const c of chunks) {
            const content = textClean((c as any)?.chunk_text || "");
            if (content) contextParts.push(content);
          }
        }
      }
    } catch (_) {}

    if (contextParts.length === 0) {
      if (isLegacyChat) {
        const about = textClean((legacyRow as any)?.about_me_text || "");
        if (about) contextParts.push(`About ${displayName}: ${about}`);

        const { data: memories, error: memErr } = await withTimeout(
          supabase
            .from("legacy_memories")
            .select("prompt_text, body")
            .eq("legacy_member_id", legacyMemberId)
            .eq("family_id", familyId)
            .order("created_at", { ascending: false })
            .limit(12),
          4_000,
          "DB(legacy_memories)"
        );

        if (memErr) return json({ error: `DB error: ${memErr.message}` }, 500);

        const list = (memories as any[]) || [];
        for (const m of list) {
          const p = textClean(m?.prompt_text || "");
          const b = textClean(m?.body || "");
          if (p || b) contextParts.push(`Q: ${p}\nA: ${b}`.trim());
        }
      } else {
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
    }

    contextParts = await rankContextByMeaning(question, contextParts, 14);
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
