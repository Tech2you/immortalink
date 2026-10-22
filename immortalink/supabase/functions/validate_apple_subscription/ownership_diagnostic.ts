type Binding = {
  purchaser_id: string;
  family_id: string | null;
  environment: string;
  retired: boolean;
};

type VerifiedTransaction = {
  transactionId?: string;
  originalTransactionId?: string;
  appAccountToken?: string;
  environment?: string;
  expiresDate?: number;
  revocationDate?: number;
};

async function fingerprint(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0"))
    .join("").slice(0, 16);
}

// Call only after Apple signature, bundle, product and transaction checks pass.
// Log relationships, never raw receipts, account IDs or appAccountTokens.
export async function ownershipDiagnostic(options: {
  transaction: VerifiedTransaction;
  userId: string;
  familyId: string;
  lookupBinding: (originalId: string) => Promise<Binding | null>;
  now?: number;
}) {
  const { transaction, userId, familyId, lookupBinding } = options;
  try {
    const binding = await lookupBinding(transaction.originalTransactionId!);
    const token = transaction.appAccountToken?.toLowerCase();
    return {
      transaction_fingerprint: await fingerprint(transaction.transactionId!),
      original_fingerprint: await fingerprint(transaction.originalTransactionId!),
      environment: transaction.environment?.toLowerCase(),
      expired: typeof transaction.expiresDate === "number"
        ? transaction.expiresDate <= (options.now ?? Date.now()) : null,
      revoked: transaction.revocationDate != null,
      token_matches_caller: token ? token === userId.toLowerCase() : null,
      binding_found: binding !== null,
      binding_matches_caller: binding ? binding.purchaser_id === userId : null,
      binding_matches_family: binding ? binding.family_id === familyId : null,
      binding_matches_environment: binding
        ? binding.environment === transaction.environment?.toLowerCase() : null,
      binding_retired: binding?.retired ?? null,
      token_matches_binding: binding && token
        ? token === binding.purchaser_id.toLowerCase() : null,
    };
  } catch (_) {
    // Diagnostics must not replace the original billing failure or leak DB errors.
    return { ownership_diagnostic_unavailable: true };
  }
}
