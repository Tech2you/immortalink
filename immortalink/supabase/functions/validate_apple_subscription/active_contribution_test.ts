import { strict as assert } from "node:assert";
import { verifiedActiveContribution } from "./active_contribution.ts";
const now = Date.now();
const tx = {
  bundleId: "com.everroots.app",
  environment: "Sandbox",
  productId: "everroots.family.monthly",
  originalTransactionId: "original",
  transactionId: "latest",
  appAccountToken: "payer",
  expiresDate: now + 86400000,
  purchaseDate: now - 1000,
  signedDate: now,
  subscriptionGroupIdentifier: "group",
};
const renewal = {
  environment: "Sandbox",
  originalTransactionId: "original",
  productId: tx.productId,
  signedDate: now,
  autoRenewStatus: 0,
  isInBillingRetryPeriod: false,
};
function fixture() {
  const item = {
    originalTransactionId: "original",
    status: 1,
    signedTransactionInfo: "tx",
    signedRenewalInfo: "renewal",
  };
  const payload = {
    bundleId: tx.bundleId,
    environment: "Sandbox",
    data: [{ subscriptionGroupIdentifier: "group", lastTransactions: [item] }],
  };
  const options: Parameters<typeof verifiedActiveContribution>[0] = {
    originalId: "original",
    environment: "sandbox",
    token: "test",
    bundleId: tx.bundleId,
    userId: "payer",
    products: new Map([[tx.productId, "family"]]),
    now,
    fetcher: async (input, init) => {
      assert.equal(
        String(input),
        "https://api.storekit-sandbox.apple.com/inApps/v1/subscriptions/original",
      );
      assert.equal(
        (init!.headers as Record<string, string>).Authorization,
        "Bearer test",
      );
      return new Response(JSON.stringify(payload));
    },
    verifyTransaction: async () => ({ ...tx }),
    verifyRenewal: async () => ({ ...renewal }),
  };
  return { item, payload, options };
}
Deno.test("active plan with cancelled renewal can move without a new purchase", async () => {
  const { options } = fixture();
  assert.deepEqual(await verifiedActiveContribution(options), tx);
});
Deno.test("expiry, refund, grace, retry and missing chain fail closed", async () => {
  for (const status of [2, 3, 4, 5]) {
    const { options, item } = fixture();
    item.status = status;
    await assert.rejects(verifiedActiveContribution(options), /INACTIVE/);
  }
  for (
    const changes of [{ expiresDate: now - 1 }, { revocationDate: now }, {
      purchaseDate: tx.expiresDate + 1,
    }]
  ) {
    const { options } = fixture();
    options.verifyTransaction = async () => ({ ...tx, ...changes });
    await assert.rejects(verifiedActiveContribution(options), /INACTIVE/);
  }
  const { options, payload } = fixture();
  payload.data[0].lastTransactions = [];
  await assert.rejects(verifiedActiveContribution(options), /MOVE_UNAVAILABLE/);
});
Deno.test("wrong payer, environment, chain, group, product, bundle or signatures cannot authorise a move", async () => {
  for (
    const changes of [
      { appAccountToken: "other" },
      { environment: "Production" },
      { originalTransactionId: "other" },
      { subscriptionGroupIdentifier: "other" },
      { productId: "other" },
      { bundleId: "other" },
      { signedDate: now + 90000 },
    ]
  ) {
    const { options } = fixture();
    options.verifyTransaction = async () => ({ ...tx, ...changes });
    await assert.rejects(
      verifiedActiveContribution(options),
      /UNAVAILABLE|MISMATCH/,
    );
  }
  for (const field of ["verifyTransaction", "verifyRenewal"] as const) {
    const { options } = fixture();
    options[field] = async () => {
      throw Error("invalid signature");
    };
    await assert.rejects(verifiedActiveContribution(options), /signature/);
  }
  const { options } = fixture();
  options.verifyRenewal = async () => ({
    ...renewal,
    originalTransactionId: "other",
  });
  await assert.rejects(verifiedActiveContribution(options), /UNAVAILABLE/);
});
Deno.test("Apple outage or duplicate current chain cannot authorise a move", async () => {
  const { options, payload, item } = fixture();
  options.fetcher = async () => new Response("", { status: 503 });
  await assert.rejects(verifiedActiveContribution(options), /UNAVAILABLE/);
  const duplicate = fixture();
  duplicate.payload.data[0].lastTransactions.push({ ...duplicate.item });
  await assert.rejects(
    verifiedActiveContribution(duplicate.options),
    /UNAVAILABLE/,
  );
});
