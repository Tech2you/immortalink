import assert from "node:assert/strict";
import test from "node:test";
import { handleRetiredVaultBundle } from "./handler.ts";

test("old media endpoint never reads a request body or returns media for any caller", async () => {
  for (const method of ["GET", "POST", "PUT", "DELETE"]) {
    for (const authorization of ["", "Bearer synthetic-user", "Bearer synthetic-admin"]) {
      const request = new Request("https://test.invalid", { method, headers: { authorization } });
      Object.defineProperty(request, "json", { value: () => { throw new Error("Must not inspect private requests"); } });
      const response = handleRetiredVaultBundle(request);
      assert.equal(response.status, 410);
      assert.equal(response.headers.get("Cache-Control"), "no-store");
      assert.deepEqual(await response.json(), {
        error: "ENDPOINT_RETIRED",
        message: "This older media endpoint is no longer available. Please update Heiro.",
      });
    }
  }
});

test("preflight exposes no media and does not cache responses", () => {
  const response = handleRetiredVaultBundle(new Request("https://test.invalid", { method: "OPTIONS" }));
  assert.equal(response.status, 204);
  assert.equal(response.body, null);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
