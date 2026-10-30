function textClean(s: string) {
  return (s || "").replace(/\s+/g, " ").trim();
}

export type RelationshipRow = {
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
  const removedWord = removed === 1
    ? "once"
    : removed === 2
    ? "twice"
    : `${removed} times`;
  return `${degreeWord} cousin ${removedWord} removed`;
}

export function resolveRelationshipFromGraph(
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
    const first = `${textClean(row.parent_type || "")}:${
      textClean(row.parent_id || "")
    }`;
    const second = `${textClean(row.child_type || "")}:${
      textClean(row.child_id || "")
    }`;
    const kind = textClean(row.relationship_kind || "");
    if (first === ":" || second === ":") continue;

    const isDirectPair = (first === viewerKey && second === ownerKey) ||
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

  // A sibling link establishes only this pair, not every sibling of either person.
  // A separate synthetic parent per edge preserves aunt/cousin paths without
  // treating siblinghood as transitive across different half-sibling families.
  const seenPairs = new Set<string>();
  let siblingPairIndex = 0;
  for (const [first, siblings] of siblingLinks) {
    for (const second of siblings) {
      const pair = JSON.stringify([first, second].sort());
      if (seenPairs.has(pair)) continue;
      seenPairs.add(pair);
      const syntheticParent = `sibling-pair:${siblingPairIndex++}`;
      for (const sibling of [first, second]) {
        const parents = parentsByChild.get(sibling) ?? [];
        parents.push(syntheticParent);
        parentsByChild.set(sibling, parents);
      }
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
