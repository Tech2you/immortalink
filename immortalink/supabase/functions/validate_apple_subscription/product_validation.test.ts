import { strict as assert } from "node:assert";
import { test } from "node:test";
import { productValidationError } from "./product_validation.ts";
import { productMap } from "../_shared/apple_subscription_products.ts";

const input = {
  bundleId: "com.everroots.app", transactionId: "123",
  requestedProductId: "everroots.legacy.monthly",
  supportedProducts: new Map([["everroots.legacy.monthly", "everroot_legacy"]]),
  transaction: { bundleId: "com.everroots.app", transactionId: "123", productId: "everroots.legacy.monthly" },
};
test("accepts a matching supported Apple transaction", () => {
  assert.equal(productValidationError(input), null);
});
test("reports unsupported product metadata without granting entitlement", () => {
  const result = productValidationError({ ...input, transaction: { ...input.transaction, productId: "old.product" } });
  assert.equal(result?.code, "APPLE_PRODUCT_UNSUPPORTED");
  assert.equal(result?.apple_product_id, "old.product");
  assert.equal(result?.requested_product_id, input.requestedProductId);
});
test("rejects mismatched transaction, product and bundle", () => {
  assert.equal(productValidationError({ ...input, transactionId: "456" })?.code, "APPLE_TRANSACTION_MISMATCH");
  assert.equal(productValidationError({ ...input, requestedProductId: "another.product" })?.code, "APPLE_PRODUCT_MISMATCH");
  assert.equal(productValidationError({ ...input, bundleId: "another.app" })?.code, "APPLE_BUNDLE_MISMATCH");
});

test("all four App Store products validate and map to the correct plan", () => {
  const products = productMap();
  assert.equal(products.size, 4);
  for (const [product, plan] of products) {
    assert.equal(plan, product.includes(".family.") ? "everroot_family" : "everroot_legacy");
    assert.equal(productValidationError({
      ...input,
      supportedProducts: products,
      requestedProductId: product,
      transaction: { ...input.transaction, productId: product },
    }), null);
  }
  assert.equal(products.has("unknown.product"), false);
});

test("stale product environment overrides cannot remove Family monthly", () => {
  const key = "APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID";
  const original = process.env[key];
  try {
    process.env[key] = "everroots.legacy.monthly ";
    assert.equal(productMap().get("everroots.family.monthly"), "everroot_family");
    assert.equal(productMap().get("everroots.legacy.monthly"), "everroot_legacy");
  } finally {
    if (original === undefined) delete process.env[key];
    else process.env[key] = original;
  }
});
