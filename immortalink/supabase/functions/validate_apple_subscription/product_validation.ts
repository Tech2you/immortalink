// Only call with a transaction fetched directly from Apple's authenticated API.
export function productValidationError({ transaction, bundleId, transactionId,
  requestedProductId, supportedProducts }: {
  transaction: { bundleId?: string; transactionId?: string; productId?: string };
  bundleId: string;
  transactionId: string;
  requestedProductId: string;
  supportedProducts: Map<string, string>;
}) {
  if (transaction.bundleId !== bundleId) {
    return { code: "APPLE_BUNDLE_MISMATCH", error: "Apple transaction bundle id does not match this app" };
  }
  if (String(transaction.transactionId || "") !== transactionId) {
    return { code: "APPLE_TRANSACTION_MISMATCH", error: "Apple transaction id does not match the requested transaction" };
  }
  const productId = String(transaction.productId || "").trim();
  if (!supportedProducts.has(productId)) {
    return {
      code: "APPLE_PRODUCT_UNSUPPORTED",
      error: "Unsupported Apple subscription product",
      requested_product_id: requestedProductId,
      apple_product_id: productId,
    };
  }
  if (requestedProductId && requestedProductId !== productId) {
    return { code: "APPLE_PRODUCT_MISMATCH", error: "Apple transaction product does not match the requested product" };
  }
  return null;
}
