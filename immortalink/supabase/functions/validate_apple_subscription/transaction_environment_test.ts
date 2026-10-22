import { strict as assert } from "node:assert";
import { transactionEnvironment } from "./transaction_environment.ts";
import { AppleTransactionLookupError, lookupAppleTransaction } from "../_shared/apple_environment.ts";

const envelope = (environment: string) => `e30.${btoa(JSON.stringify({ environment }))}.signature`;
const noHistory = async () => [];

for (const environment of ["Sandbox", "Production"]) {
  Deno.test(`verified ${environment} receipt selects its own endpoint directly`, async () => {
    const selected = await transactionEnvironment({ transactionId: "123",
      signedTransaction: envelope(environment), previousEnvironments: noHistory,
      verify: async (_signed, hint) => {
        assert.equal(hint, environment.toLowerCase());
        return { transactionId: "123", environment };
      },
    });
    let calls = 0;
    const result = await lookupAppleTransaction({ transactionId: "123", token: "test", environment: selected,
      fetcher: (url) => {
        calls++;
        assert.equal(new URL(String(url)).host, environment === "Sandbox"
          ? "api.storekit-sandbox.itunes.apple.com" : "api.storekit.itunes.apple.com");
        return Promise.resolve(new Response(JSON.stringify({ signedTransactionInfo: "fresh-response" })));
      },
      verify: async (signed, actual) => {
        assert.equal(signed, "fresh-response");
        assert.equal(actual, selected);
        return "freshly-verified";
      },
    });
    assert.equal(result, "freshly-verified");
    assert.equal(calls, 1);
  });
}

Deno.test("forged, malformed, wrong-app and mismatched receipts cannot select a trusted environment", async () => {
  for (const signed of ["bad", envelope("Xcode"), 12, "x".repeat(128001)]) {
    await assert.rejects(() => transactionEnvironment({ transactionId: "123", signedTransaction: signed,
      previousEnvironments: noHistory, verify: async () => { throw new Error("must not verify"); },
    }));
  }
  for (const verify of [
    async () => { throw new Error("invalid signature or bundle"); },
    async () => ({ transactionId: "other", environment: "Sandbox" }),
    async () => ({ transactionId: "123", environment: "Production" }),
  ]) {
    let history = false;
    await assert.rejects(() => transactionEnvironment({ transactionId: "123", signedTransaction: envelope("Sandbox"),
      previousEnvironments: async () => { history = true; return ["sandbox"]; }, verify,
    }));
    assert.equal(history, false, "bad JWS must not fall back to history");
  }
});

Deno.test("older clients use only unambiguous previously verified transaction environments", async () => {
  for (const [history, expected] of [
    [["sandbox", "sandbox"], "sandbox"], [["production"], "production"],
    [[], undefined], [["sandbox", "production"], undefined], [["Xcode"], undefined],
  ] as const) {
    const actual = await transactionEnvironment({ transactionId: "123", signedTransaction: "",
      previousEnvironments: async () => [...history], verify: async () => { throw new Error("no receipt"); },
    });
    assert.equal(actual, expected);
  }
});

Deno.test("endpoint selection never turns an Apple authentication error into entitlement or fallback", async () => {
  let calls = 0;
  await assert.rejects(() => lookupAppleTransaction({ transactionId: "123", token: "test", environment: "sandbox",
    fetcher: () => { calls++; return Promise.resolve(new Response(null, { status: 401 })); },
    verify: async () => { throw new Error("must not verify"); },
  }), (error) => error instanceof AppleTransactionLookupError && error.status === 401 && error.environment === "sandbox");
  assert.equal(calls, 1);
});
