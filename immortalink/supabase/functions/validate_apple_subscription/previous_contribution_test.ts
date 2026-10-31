import { recoverOwnedPreviousContribution as recover } from "./previous_contribution.ts";
import {
  deepStrictEqual as assertEquals,
  rejects as assertRejects,
} from "node:assert/strict";
const tx = {
  revocationDate: undefined as number | undefined,
  originalTransactionId: "chain",
  productId: "family",
  appAccountToken: "payer",
  environment: "Sandbox",
};
const binding = {
  purchaser_id: "payer",
  family_id: "old",
  environment: "sandbox",
  retired: false,
};
function setup() {
  const calls: string[] = [];
  return {
    calls,
    options: {
      transaction: tx,
      userId: "payer",
      familyId: "new",
      findBinding: async () => binding,
      verifyCurrent: async () => {
        calls.push("Apple");
        return tx;
      },
      synchronize: async () => {
        calls.push("sync");
      },
      acknowledge: async () => {
        calls.push("ack");
        return { code: "APPLE_OWNED_PREVIOUS_CONTRIBUTION", status: "active" };
      },
    },
  };
}
Deno.test("owned previous purchase requires fresh Apple proof then persisted acknowledgement", async () => {
  const { calls, options } = setup();
  assertEquals((await recover(options))?.product_id, "family");
  assertEquals(calls, ["Apple", "sync", "ack"]);
});
Deno.test("foreign payer, wrong environment, retired and current-family bindings are never acknowledged", async () => {
  for (
    const b of [
      { ...binding, purchaser_id: "other" },
      { ...binding, retired: true },
      { ...binding, environment: "production" },
      { ...binding, family_id: "new" },
    ]
  ) {
    const { calls, options } = setup();
    assertEquals(
      await recover({ ...options, findBinding: async () => b }),
      null,
    );
    assertEquals(calls, []);
  }
  const { options } = setup();
  assertEquals(
    await recover({
      ...options,
      transaction: { ...tx, appAccountToken: "other" },
    }),
    null,
  );
  assertEquals(
    await recover({ ...options, transaction: { ...tx, revocationDate: 1 } }),
    null,
  );
});
Deno.test("Apple failure never acknowledges or releases a pending checkout", async () => {
  const { calls, options } = setup();
  await assertRejects(() =>
    recover({
      ...options,
      verifyCurrent: () => Promise.reject(Error("Apple unavailable")),
    })
  );
  assertEquals(calls, []);
});
