import { strict as assert } from "node:assert";
import { ownershipDiagnostic } from "./ownership_diagnostic.ts";

const transaction = {
  transactionId: "private-transaction-id",
  originalTransactionId: "private-original-id",
  appAccountToken: "PURCHASER-UUID",
  environment: "Sandbox",
  expiresDate: 10,
};
const binding = {
  purchaser_id: "purchaser-uuid", family_id: "family-uuid",
  environment: "sandbox", retired: true,
};

Deno.test("ownership diagnostics distinguish bound history without exposing identities", async () => {
  const result = await ownershipDiagnostic({ transaction, userId: "other-user-uuid",
    familyId: "family-uuid", now: 20, lookupBinding: async (original) => {
      assert.equal(original, transaction.originalTransactionId);
      return binding;
    },
  });
  assert.equal(result.expired, true);
  assert.equal(result.binding_found, true);
  assert.equal(result.binding_retired, true);
  assert.equal(result.binding_matches_caller, false);
  assert.equal(result.binding_matches_family, true);
  assert.equal(result.binding_matches_environment, true);
  assert.equal(result.token_matches_caller, false);
  assert.equal(result.token_matches_binding, true);
  assert.match(result.transaction_fingerprint!, /^[a-f0-9]{16}$/);
  const serialized = JSON.stringify(result);
  for (const secret of [...Object.values(transaction).filter((v) => typeof v === "string"),
    binding.purchaser_id, binding.family_id, "other-user-uuid"]) {
    assert.equal(serialized.includes(secret), false);
  }
});

Deno.test("unbound and tokenless transactions are distinct from purchaser mismatches", async () => {
  const unbound = await ownershipDiagnostic({ transaction, userId: "purchaser-uuid",
    familyId: "family-uuid", now: 1, lookupBinding: async () => null,
  });
  assert.equal(unbound.expired, false);
  assert.equal(unbound.binding_found, false);
  assert.equal(unbound.binding_matches_caller, null);
  assert.equal(unbound.token_matches_binding, null);
  assert.equal(unbound.token_matches_caller, true);
  const tokenless = await ownershipDiagnostic({
    transaction: { ...transaction, appAccountToken: undefined, revocationDate: 5 },
    userId: binding.purchaser_id, familyId: "family-uuid", lookupBinding: async () => binding,
  });
  assert.equal(tokenless.token_matches_caller, null);
  assert.equal(tokenless.token_matches_binding, null);
  assert.equal(tokenless.revoked, true);
  assert.equal(tokenless.transaction_fingerprint, unbound.transaction_fingerprint);
});

Deno.test("diagnostic lookup failure cannot leak or replace the billing error", async () => {
  const result = await ownershipDiagnostic({ transaction, userId: "private-user",
    familyId: "private-family", lookupBinding: async () => { throw new Error("private DB detail"); },
  });
  assert.deepEqual(result, { ownership_diagnostic_unavailable: true });
});
