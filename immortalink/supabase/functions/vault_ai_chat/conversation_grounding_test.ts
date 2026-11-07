import {
  emptyVaultAnswer,
  familyContext,
  isRelationshipQuestion as direct,
  recordedRelatives,
} from "./conversation_grounding.ts";
import type { RelationshipRow } from "./relationship_graph.ts";
function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}
const edge = (
  a: string,
  b: string,
  relationship_kind = "parent_child",
): RelationshipRow => ({
  parent_type: "legacy",
  parent_id: a,
  child_type: "legacy",
  child_id: b,
  relationship_kind,
});
for (
  const q of [
    "How are we related?",
    "Who am I to you?",
    "Who are you to me?",
    "Are you my great-grandparent?",
    "Am I your grandson?",
    "What is our relationship?",
    "Can you tell me how are we related?",
  ]
) {
  Deno.test(`direct relationship: ${q}`, () => equal(direct(q), true));
}
for (
  const q of [
    "Can you share a favorite memory you have of your grandparents?",
    "Tell me about your mother",
    "What was your relationship with your brother like?",
    "Who are your grandparents?",
    "How are my grandparents related?",
    "Did you enjoy playing the grand piano?",
    "Are you my grandfather, and what did your grandmother teach you?",
    "Who is John related to?",
    "What are your favourite childhood memories?",
  ]
) {
  Deno.test(`preserve the actual question: ${q}`, () =>
    equal(direct(q), false));
}
Deno.test("grandparents belong to the profile, not its great-grandchild viewer", () => {
  const rows = [
    edge("Bremner", "Jenna"),
    edge("Jenna", "Ross"),
    edge("Ross", "Viewer"),
  ];
  equal(recordedRelatives("legacy:Bremner", rows).grandparents, 0);
  equal(recordedRelatives("legacy:Viewer", rows).grandparents, 1);
  equal(
    emptyVaultAnswer(
      "Tell me about your grandparents",
      "legacy:Bremner",
      "legacy:Viewer",
      rows,
    ),
    "I don't have a saved memory about my grandparents here yet. No grandparents are linked to my profile in this family tree yet.",
  );
  equal(
    emptyVaultAnswer(
      "Tell me about my grandparents",
      "legacy:Bremner",
      "legacy:Viewer",
      rows,
    ),
    "I don't have a saved memory about your grandparents here yet.",
  );
});
Deno.test("half siblings do not create unnamed parents or grandparents", () => {
  const rows = [edge("A", "B", "sibling"), edge("P", "A"), edge("GP", "P")];
  equal(recordedRelatives("legacy:B", rows), {
    parents: 0,
    grandparents: 0,
    children: 0,
    siblings: 1,
    spouses: 0,
  });
});
Deno.test("multiple paths deduplicate a relative and distinguish legacy and live IDs", () => {
  const rows = [
    edge("GP", "P"),
    edge("GP", "Q"),
    edge("P", "A"),
    edge("Q", "A"),
    edge("P", "A"),
  ];
  equal(recordedRelatives("legacy:A", rows).grandparents, 1);
  equal(recordedRelatives("vault:A", rows).parents, 0);
});
Deno.test("failed graph lookup never claims grandparents are missing", () => {
  equal(
    emptyVaultAnswer("Tell me about your grandparents", "legacy:A", null, null),
    "I don't have a saved memory about my grandparents here yet.",
  );
  equal(
    familyContext("legacy:A", null, null).includes("could not be confirmed"),
    true,
  );
});
