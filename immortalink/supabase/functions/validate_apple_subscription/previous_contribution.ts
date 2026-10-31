type Transaction = {
  originalTransactionId?: string;
  productId?: string;
  appAccountToken?: string;
  environment?: string;
  revocationDate?: number;
};
// A restore of the same payer's delivered service is not a foreign-account
// claim. It still does NOT move service or grant access to the current family.
export async function recoverOwnedPreviousContribution<T extends Transaction>(
  o: {
    transaction: T;
    userId: string;
    familyId: string;
    findBinding: (
      id: string,
    ) => Promise<
      {
        purchaser_id: string;
        family_id: string | null;
        environment: string;
        retired: boolean;
      } | null
    >;
    verifyCurrent: () => Promise<T>;
    synchronize: (tx: T) => Promise<void>;
    acknowledge: (tx: T) => Promise<Record<string, unknown>>;
  },
): Promise<Record<string, unknown> | null> {
  const t = o.transaction;
  if (
    !t.originalTransactionId || t.revocationDate != null ||
    t.appAccountToken?.toLowerCase() !== o.userId.toLowerCase()
  ) return null;
  const b = await o.findBinding(t.originalTransactionId);
  if (
    !b || b.retired || b.purchaser_id !== o.userId ||
    b.family_id === o.familyId ||
    b.environment !== t.environment?.toLowerCase()
  ) return null;
  const current = await o.verifyCurrent();
  await o.synchronize(current);
  const result = await o.acknowledge(current);
  return { ...result, product_id: t.productId };
}
