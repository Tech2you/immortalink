import { strict as assert } from "node:assert";
import { lookupAppleTransaction, notificationEnvironment } from "./apple_environment.ts";

function fixture(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), { status });
}

Deno.test("production lookup succeeds without sandbox and verifies signed response", async () => {
  let calls = 0;
  const result = await lookupAppleTransaction({ transactionId: "12/34", token: "test",
    fetcher: (input) => {
      calls++;
      assert.equal(String(input), "https://api.storekit.itunes.apple.com/inApps/v1/transactions/12%2F34");
      return Promise.resolve(fixture(200, { signedTransactionInfo: "signed" }));
    },
    verify: (signed, environment) => {
      assert.equal(signed, "signed");
      assert.equal(environment, "production");
      return Promise.resolve("verified");
    },
  });
  assert.equal(result, "verified");
  assert.equal(calls, 1);
});

Deno.test("only 4040010 permits sandbox retry with sandbox verifier", async () => {
  const hosts: string[] = [];
  await lookupAppleTransaction({ transactionId: "123", token: "test",
    fetcher: (input) => {
      hosts.push(new URL(String(input)).host);
      return Promise.resolve(hosts.length === 1
        ? fixture(404, { errorCode: 4040010 })
        : fixture(200, { signedTransactionInfo: "sandbox-signed" }));
    },
    verify: (signed, environment) => {
      assert.equal(environment, "sandbox");
      assert.equal(signed, "sandbox-signed");
      return Promise.resolve(true);
    },
  });
  assert.deepEqual(hosts, ["api.storekit.itunes.apple.com", "api.storekit-sandbox.itunes.apple.com"]);
});

Deno.test("auth, network, other not-found and signature failures never downgrade to sandbox", async () => {
  for (const response of [fixture(401, {}), fixture(500, {}), fixture(404, { errorCode: 4040002 }), fixture(200, { signedTransactionInfo: "forged" })]) {
    let calls = 0;
    await assert.rejects(() => lookupAppleTransaction({ transactionId: "123", token: "test",
      fetcher: () => { calls++; return Promise.resolve(response); },
      verify: () => { throw new Error("bad signature"); },
    }));
    assert.equal(calls, 1);
  }
  let calls = 0;
  await assert.rejects(() => lookupAppleTransaction({ transactionId: "123", token: "test",
    fetcher: () => { calls++; throw new Error("offline"); }, verify: async () => true,
  }));
  assert.equal(calls, 1);
});

Deno.test("verified notification lookup stays in its signed environment", async () => {
  let calls = 0;
  await assert.rejects(() => lookupAppleTransaction({ transactionId: "123", token: "test", environment: "production",
    fetcher: () => { calls++; return Promise.resolve(fixture(404, { errorCode: 4040010 })); },
    verify: async () => true,
  }));
  assert.equal(calls, 1);
});

Deno.test("untrusted notification hint only selects production or sandbox, never local testing", () => {
  const envelope = (environment: string) => `e30.${btoa(JSON.stringify({ data: { environment } }))}.unsigned`;
  assert.equal(notificationEnvironment(envelope("Production")), "production");
  assert.equal(notificationEnvironment(envelope("Sandbox")), "sandbox");
  for (const input of [envelope("LocalTesting"), "a.b.c", undefined, "x".repeat(128001)]) {
    assert.throws(() => notificationEnvironment(input));
  }
});
