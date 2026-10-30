import type { AppleEnvironment } from "../_shared/apple_environment.ts";

type Transaction = {
  bundleId?: string; environment?: string; productId?: string;
  originalTransactionId?: string; transactionId?: string;
  purchaseDate?: number; expiresDate?: number; signedDate?: number;
  revocationDate?: number; subscriptionGroupIdentifier?: string;
};
type Renewal = {
  environment?: string; originalTransactionId?: string; productId?: string;
  autoRenewStatus?: number; isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number; signedDate?: number;
};

// StoreKit can replay expired receipts as purchased/unfinished, not just restored.
// Classification must use Apple's verified dates and current status, not that label.
export async function recoverExpiredForeignPurchase(options: {
  transaction: Transaction; userId: string; familyId: string; now?: number;
  findBinding: (originalId: string) => Promise<{ purchaser_id: string; family_id: string } | null>;
  verifyCurrent: () => Promise<Transaction>;
  prepare: (latest: Transaction) => Promise<Record<string, unknown>>;
}): Promise<Record<string, unknown> | null> {
  const { transaction: tx, userId, familyId } = options;
  if (!tx.originalTransactionId || !Number.isFinite(tx.expiresDate) ||
      tx.expiresDate! > (options.now ?? Date.now()) || tx.revocationDate != null) return null;
  const binding = await options.findBinding(tx.originalTransactionId);
  if (!binding || (binding.purchaser_id === userId && binding.family_id === familyId)) return null;
  const latest = await options.verifyCurrent();
  const prepared = await options.prepare(latest);
  return { ...prepared, product_id: tx.productId };
}

// A historical receipt alone cannot prove that its subscription is still expired.
// Ask Apple for the entire group's current status and verify both signed payloads.
export async function verifiedExpiredHistory(options: {
  originalId: string; environment: AppleEnvironment; token: string;
  bundleId: string; products: Map<string, string>;
  verifyTransaction: (signed: string) => Promise<Transaction>;
  verifyRenewal: (signed: string) => Promise<Renewal>;
  fetcher?: typeof fetch; now?: number;
}): Promise<Transaction> {
  const { originalId, environment, token, bundleId, products } = options;
  const now = options.now ?? Date.now();
  const host = environment === "production" ? "api.storekit.apple.com" : "api.storekit-sandbox.apple.com";
  const response = await (options.fetcher ?? fetch)(
    `https://${host}/inApps/v1/subscriptions/${encodeURIComponent(originalId)}`,
    { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) },
  );
  if (!response.ok) throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
  const payload = await response.json();
  if (payload.bundleId !== bundleId || String(payload.environment).toLowerCase() !== environment ||
      !Array.isArray(payload.data) || !payload.data.length) {
    throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
  }
  let latest: Transaction | undefined;
  for (const group of payload.data) {
    if (!Array.isArray(group.lastTransactions) || !group.lastTransactions.length) {
      throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
    }
    for (const item of group.lastTransactions) {
      if (typeof item.signedTransactionInfo !== "string" || typeof item.signedRenewalInfo !== "string") {
        throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
      }
      const tx = await options.verifyTransaction(item.signedTransactionInfo);
      const renewal = await options.verifyRenewal(item.signedRenewalInfo);
      if (tx.bundleId !== bundleId || tx.environment?.toLowerCase() !== environment ||
          renewal.environment?.toLowerCase() !== environment || !tx.originalTransactionId ||
          tx.originalTransactionId !== item.originalTransactionId ||
          tx.originalTransactionId !== renewal.originalTransactionId ||
          tx.productId !== renewal.productId || !products.has(tx.productId ?? "") ||
          tx.subscriptionGroupIdentifier !== group.subscriptionGroupIdentifier ||
          !tx.transactionId || !Number.isFinite(tx.purchaseDate) || !Number.isFinite(tx.expiresDate) ||
          !Number.isFinite(tx.signedDate) || !Number.isFinite(renewal.signedDate) ||
          tx.signedDate! > now + 60000 || renewal.signedDate! > now + 60000) {
        throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
      }
      if (item.status !== 2 || tx.expiresDate! > now || tx.revocationDate != null ||
          renewal.autoRenewStatus !== 0 || renewal.isInBillingRetryPeriod === true ||
          (renewal.gracePeriodExpiresDate ?? 0) > now) {
        throw new Error("APPLE_PREVIOUS_PLAN_NOT_ENDED");
      }
      if (tx.originalTransactionId === originalId &&
          (!latest || tx.purchaseDate! > latest.purchaseDate!)) latest = tx;
    }
  }
  if (!latest) throw new Error("APPLE_HISTORY_CHECK_UNAVAILABLE");
  return latest;
}
