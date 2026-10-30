import {
  type RelationshipRow,
  resolveRelationshipFromGraph as resolve,
} from "./relationship_graph.ts";

const edge = (
  a: string,
  b: string,
  kind = "parent_child",
): RelationshipRow => ({
  parent_type: "vault",
  parent_id: a,
  child_type: "vault",
  child_id: b,
  relationship_kind: kind,
});
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const same = (kind: string) => ({ viewerToOwner: kind, ownerToViewer: kind });

Deno.test("direct unknown-parent siblings are symmetric without inventing their parents", () => {
  const rows = [edge("A", "B", "sibling"), edge("P", "A")];
  equal(resolve("A", "B", rows), same("sibling"));
  equal(resolve("B", "A", rows), same("sibling"));
  equal(resolve("P", "B", rows), null);
});
Deno.test("half-sibling chains do not imply sibling or cousin relationships", () => {
  const rows = [
    edge("A", "B", "sibling"),
    edge("B", "C", "sibling"),
    edge("A", "D"),
    edge("C", "E"),
  ];
  equal(resolve("A", "C", rows), null);
  equal(resolve("D", "E", rows), null);
});
Deno.test("explicit shared parents, partners and self remain correct", () => {
  const rows = [
    edge("P", "A"),
    edge("P", "B"),
    edge("Q", "B"),
    edge("Q", "C"),
    edge("A", "X", "spouse"),
  ];
  equal(resolve("A", "B", rows), same("sibling"));
  equal(resolve("B", "C", rows), same("sibling"));
  equal(resolve("A", "C", rows), null);
  equal(resolve("A", "X", rows), same("spouse"));
  equal(resolve("A", "A", rows), same("owner"));
});
Deno.test("one recorded sibling pair still supports aunts and first cousins", () => {
  const rows = [
    edge("A", "B", "sibling"),
    edge("B", "A", "sibling"),
    edge("A", "D"),
    edge("B", "E"),
  ];
  equal(resolve("A", "E", rows), {
    viewerToOwner: "parent's sibling",
    ownerToViewer: "sibling's child",
  });
  equal(resolve("D", "E", rows), same("first cousin"));
});
Deno.test("ordinary ancestry and legacy endpoints retain their direction", () => {
  const rows = [edge("A", "B"), edge("B", "C")];
  equal(resolve("A", "C", rows), {
    viewerToOwner: "grandparent",
    ownerToViewer: "grandchild",
  });
  equal(resolve("C", "A", rows), {
    viewerToOwner: "grandchild",
    ownerToViewer: "grandparent",
  });
  equal(
    resolve(
      "A",
      "L",
      [{ ...edge("A", "L", "sibling"), child_type: "legacy" }],
      "legacy",
    ),
    same("sibling"),
  );
});
