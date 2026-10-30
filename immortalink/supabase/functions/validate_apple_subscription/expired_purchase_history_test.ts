import { strict as assert } from "node:assert";
import { recoverExpiredForeignPurchase, verifiedExpiredHistory } from "./expired_purchase_history.ts";

const now = Date.now();
const tx = { bundleId: "com.everroots.app", environment: "Sandbox", productId: "everroots.family.monthly",
  originalTransactionId: "original", transactionId: "old", purchaseDate: now-10000,
  expiresDate: now-1000, signedDate: now-100000, subscriptionGroupIdentifier: "group" };
const renewal = { originalTransactionId: "original", environment: "Sandbox", productId: tx.productId,
  autoRenewStatus: 0, isInBillingRetryPeriod: false, signedDate: now-100000 };
function fixture() {
  const item = { originalTransactionId: "original", status: 2, signedTransactionInfo: "tx", signedRenewalInfo: "renewal" };
  const payload = { bundleId: tx.bundleId, environment: "Sandbox",
    data: [{ subscriptionGroupIdentifier: "group", lastTransactions: [item] }] };
  return { item, payload, options: { originalId: "original", environment: "sandbox" as const,
    token: "test", bundleId: tx.bundleId, products: new Map([[tx.productId,"family"]]), now,
    fetcher: async () => new Response(JSON.stringify(payload)),
    verifyTransaction: async () => ({...tx}), verifyRenewal: async () => ({...renewal}),
  } };
}

function recoveryFixture() {
  const calls: string[] = [];
  const options: Parameters<typeof recoverExpiredForeignPurchase>[0] = {
    transaction: { ...tx }, userId: "new-user", familyId: "new-family", now,
    findBinding: async (_: string): Promise<{ purchaser_id: string; family_id: string } | null> => {
      calls.push("binding"); return { purchaser_id: "old-user", family_id: "old-family" };
    },
    verifyCurrent: async () => { calls.push("apple"); return { ...tx, transactionId: "latest" }; },
    prepare: async (latest) => {
      calls.push("prepare"); assert.equal(latest.transactionId, "latest");
      return { code: "APPLE_EXPIRED_HISTORY", status: "expired" };
    },
  };
  return { options, calls };
}
Deno.test("expired foreign purchased/unfinished receipts do not need a client history flag", async () => {
  const {options, calls} = recoveryFixture();
  assert.deepEqual(await recoverExpiredForeignPurchase(options), {
    code: "APPLE_EXPIRED_HISTORY", status: "expired", product_id: tx.productId,
  });
  assert.deepEqual(calls, ["binding", "apple", "prepare"]);
});
Deno.test("active, revoked, missing and invalid expiry bypass history recovery", async () => {
  for (const patch of [{ expiresDate: now+1000 }, { revocationDate: now },
    { expiresDate: undefined }, { expiresDate: NaN }]) {
    const {options, calls} = recoveryFixture();
    assert.equal(await recoverExpiredForeignPurchase({ ...options, transaction: { ...tx, ...patch } }), null);
    assert.deepEqual(calls, []);
  }
});
Deno.test("unbound and same-owner/same-family receipts retain normal validation", async () => {
  for (const binding of [null, { purchaser_id: "new-user", family_id: "new-family" }]) {
    const {options, calls} = recoveryFixture();
    options.findBinding = async () => binding;
    assert.equal(await recoverExpiredForeignPurchase(options), null);
    assert.deepEqual(calls, []);
  }
});
Deno.test("history recovery does not prepare on Apple outage or non-ended current plan", async () => {
  for (const code of ["APPLE_HISTORY_CHECK_UNAVAILABLE", "APPLE_PREVIOUS_PLAN_NOT_ENDED"]) {
    const {options, calls} = recoveryFixture();
    options.verifyCurrent = async () => { throw new Error(code); };
    await assert.rejects(recoverExpiredForeignPurchase(options), new RegExp(code));
    assert.deepEqual(calls, ["binding"]);
  }
});
Deno.test("database rejection never returns a successful history acknowledgement", async () => {
  const {options} = recoveryFixture();
  options.prepare = async () => { throw new Error("FAMILY_ALREADY_SPONSORED"); };
  await assert.rejects(recoverExpiredForeignPurchase(options), /FAMILY_ALREADY_SPONSORED/);
});
Deno.test("only a live Apple status check with verified expired transaction and renewal permits preflight", async () => {
  const {options}=fixture();
  const fetcher=options.fetcher;
  options.fetcher=async (input?: unknown, init?: RequestInit) => {
    assert.equal(input,"https://api.storekit-sandbox.apple.com/inApps/v1/subscriptions/original");
    assert.equal((init?.headers as Record<string,string>).Authorization,"Bearer test");
    return fetcher();
  };
  assert.deepEqual(await verifiedExpiredHistory(options),tx);
});
Deno.test("active, grace, retry, revoked and unknown statuses never qualify", async () => {
  for(const status of [1,3,4,5,0]) {
    const {options,item}=fixture(); item.status=status;
    await assert.rejects(verifiedExpiredHistory(options),/APPLE_PREVIOUS_PLAN_NOT_ENDED/);
  }
  for(const patch of [{autoRenewStatus:1},{isInBillingRetryPeriod:true},{gracePeriodExpiresDate:now+1000}]) {
    const {options}=fixture(); options.verifyRenewal=async()=>({...renewal,...patch});
    await assert.rejects(verifiedExpiredHistory(options),/APPLE_PREVIOUS_PLAN_NOT_ENDED/);
  }
  for(const patch of [{expiresDate:now+1000},{revocationDate:now}]) {
    const {options}=fixture(); options.verifyTransaction=async()=>({...tx,...patch});
    await assert.rejects(verifiedExpiredHistory(options),/APPLE_PREVIOUS_PLAN_NOT_ENDED/);
  }
});
Deno.test("an older expired chain cannot hide another active subscription in the group",async()=>{
  const {options,payload,item}=fixture(); payload.data[0].lastTransactions.push({...item,status:1});
  await assert.rejects(verifiedExpiredHistory(options),/APPLE_PREVIOUS_PLAN_NOT_ENDED/);
});
Deno.test("missing data, wrong environment, inconsistent group/product/chain and failed signatures fail closed",async()=>{
  for(const patch of [{bundleId:"wrong"},{environment:"Production"},{originalTransactionId:"wrong"},
    {subscriptionGroupIdentifier:"other"},{productId:"other"},{signedDate:now+86400000}, {transactionId:""}]) {
    const {options}=fixture(); options.verifyTransaction=async()=>({...tx,...patch});
    await assert.rejects(verifiedExpiredHistory(options),/APPLE_HISTORY_CHECK_UNAVAILABLE/);
  }
  const {options,payload}=fixture(); payload.data=[];
  await assert.rejects(verifiedExpiredHistory(options),/APPLE_HISTORY_CHECK_UNAVAILABLE/);
  const signed=fixture().options; signed.verifyRenewal=async()=>{throw new Error("bad signature")};
  await assert.rejects(verifiedExpiredHistory(signed),/bad signature/);
  const offline=fixture().options; offline.fetcher=async()=>new Response("",{status:500});
  await assert.rejects(verifiedExpiredHistory(offline),/APPLE_HISTORY_CHECK_UNAVAILABLE/);
});
