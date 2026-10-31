import { strict as assert } from "node:assert";
import {
  AppleStatusCheckError,
  fetchSubscriptionStatus,
} from "./subscription_status.ts";
const options = {
  originalId: "test-chain",
  environment: "sandbox" as const,
  token: "test-only",
};
Deno.test("temporary status API failure retries once, with the same deadline and no write", async () => {
  let calls = 0;
  let first: AbortSignal | null | undefined;
  const result = await fetchSubscriptionStatus({
    ...options,
    fetcher: async (input, init) => {
      assert.ok(String(input).endsWith("/subscriptions/test-chain"));
      assert.equal(init?.method, undefined);
      if (calls++ === 0) {
        first = init?.signal;
        return new Response("", { status: 503 });
      }
      assert.equal(init?.signal, first);
      return Response.json({ data: [] });
    },
  });
  assert.equal(calls, 2);
  assert.deepEqual(result, { data: [] });
});
Deno.test("persistent outage is bounded and nonretryable statuses fail immediately", async () => {
  for (const status of [401, 404, 429, 503]) {
    let calls = 0;
    await assert.rejects(
      () =>
        fetchSubscriptionStatus({
          ...options,
          fetcher: async () => {
            calls++;
            return new Response("", { status });
          },
        }),
      (e) =>
        e instanceof AppleStatusCheckError && e.stage === "http" &&
        e.httpStatus === status,
    );
    assert.equal(calls, status >= 500 || status === 429 ? 2 : 1);
  }
});
Deno.test("network interruptions retry once; malformed response is never accepted", async () => {
  let calls = 0;
  assert.deepEqual(
    await fetchSubscriptionStatus({
      ...options,
      fetcher: async () => {
        if (calls++ === 0) throw new TypeError("network");
        return Response.json({ data: [] });
      },
    }),
    { data: [] },
  );
  assert.equal(calls, 2);
  await assert.rejects(
    () =>
      fetchSubscriptionStatus({
        ...options,
        fetcher: async () => new Response("invalid"),
      }),
    (e) => e instanceof AppleStatusCheckError && e.stage === "json",
  );
});
