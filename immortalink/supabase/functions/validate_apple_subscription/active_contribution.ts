import {
  AppleStatusCheckError,
  fetchSubscriptionStatus,
} from "./subscription_status.ts";
import type { AppleEnvironment } from "../_shared/apple_environment.ts";
type Transaction = {
  bundleId?: string;
  environment?: string;
  productId?: string;
  originalTransactionId?: string;
  transactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  purchaseDate?: number;
  signedDate?: number;
  revocationDate?: number;
  subscriptionGroupIdentifier?: string;
};
type Renewal = {
  environment?: string;
  originalTransactionId?: string;
  productId?: string;
  signedDate?: number;
  isInBillingRetryPeriod?: boolean;
};
// Moving is never authorised from a historical receipt or client cancellation.
// Fetch the current chain and verify Apple's transaction AND renewal signatures.
export async function verifiedActiveContribution(
  o: {
    originalId: string;
    environment: AppleEnvironment;
    token: string;
    bundleId: string;
    userId: string;
    products: Map<string, string>;
    verifyTransaction: (s: string) => Promise<Transaction>;
    verifyRenewal: (s: string) => Promise<Renewal>;
    fetcher?: typeof fetch;
    now?: number;
  },
): Promise<Transaction> {
  const now = o.now ?? Date.now();
  const data = await fetchSubscriptionStatus(o) as {
    bundleId?: string;
    environment?: string;
    data?: Array<
      {
        subscriptionGroupIdentifier?: string;
        lastTransactions?: Array<
          {
            originalTransactionId?: string;
            status?: number;
            signedTransactionInfo?: string;
            signedRenewalInfo?: string;
          }
        >;
      }
    >;
  };
  if (
    !data || data.bundleId !== o.bundleId ||
    String(data.environment).toLowerCase() !== o.environment ||
    !Array.isArray(data.data)
  ) throw new AppleStatusCheckError("payload");
  let found: Transaction | undefined;
  for (const group of data.data) {
    if (!Array.isArray(group.lastTransactions)) {
      throw new AppleStatusCheckError("payload");
    }
    for (const item of group.lastTransactions) {
      if (item.originalTransactionId !== o.originalId) continue;
      if (
        found || typeof item.signedTransactionInfo !== "string" ||
        typeof item.signedRenewalInfo !== "string"
      ) throw new AppleStatusCheckError("payload");
      const tx = await o.verifyTransaction(item.signedTransactionInfo),
        r = await o.verifyRenewal(item.signedRenewalInfo);
      if (
        tx.bundleId !== o.bundleId ||
        tx.environment?.toLowerCase() !== o.environment ||
        r.environment?.toLowerCase() !== o.environment ||
        tx.originalTransactionId !== o.originalId ||
        r.originalTransactionId !== o.originalId ||
        tx.productId !== r.productId || !o.products.has(tx.productId ?? "") ||
        !group.subscriptionGroupIdentifier ||
        tx.subscriptionGroupIdentifier !== group.subscriptionGroupIdentifier ||
        !tx.transactionId ||
        ![tx.expiresDate, tx.purchaseDate, tx.signedDate, r.signedDate].every(
          Number.isFinite,
        ) || tx.signedDate! > now + 60000 || r.signedDate! > now + 60000
      ) throw new AppleStatusCheckError("transaction_fields");
      if (tx.appAccountToken?.toLowerCase() !== o.userId.toLowerCase()) {
        throw Error("APPLE_PURCHASER_MISMATCH");
      }
      if (
        item.status !== 1 || tx.revocationDate != null ||
        tx.expiresDate! <= now || tx.purchaseDate! >= tx.expiresDate! ||
        r.isInBillingRetryPeriod === true
      ) throw Error("APPLE_SUBSCRIPTION_INACTIVE");
      found = tx;
    }
  }
  if (!found) throw Error("APPLE_MOVE_UNAVAILABLE");
  return found;
}
