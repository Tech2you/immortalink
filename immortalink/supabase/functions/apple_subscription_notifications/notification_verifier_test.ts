import { strict as assert } from "node:assert";
import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";
import {
  createNotificationVerifier,
  notificationErrorStatus,
  verifyNotification,
} from "./notification_verifier.ts";
import { handleNotification } from "./index.ts";

const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(`./test_fixtures/${name}`, import.meta.url))
    .trim();
const notification = fixture("testNotification");
const transaction = fixture("transactionInfo");
// Apple's public synthetic fixtures use a TEST root, never accepted by the live factory.
// They have no OCSP responder; only these isolated fixture verifiers disable online checks.
const testVerifier = (
  environment = Environment.SANDBOX,
  bundle = "com.example",
) =>
  new SignedDataVerifier(
    [Buffer.from(fixture("testCA.base64"), "base64")],
    false,
    environment,
    bundle,
    1234,
  );

Deno.test("valid signed Apple fixture notification passes cryptographic verification", async () => {
  const result = await verifyNotification(notification, testVerifier());
  assert.equal(result.notification.notificationType, "TEST");
  assert.equal(result.transaction, null);
});

Deno.test("valid signed transaction fixture passes cryptographic verification", async () => {
  const result = await testVerifier().verifyAndDecodeTransaction(transaction);
  assert.equal(result.bundleId, "com.example");
  assert.equal(result.environment, "Sandbox");
});

Deno.test("changing the notification type invalidates its signature", async () => {
  const parts = notification.split(".");
  const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  payload.notificationType = "REFUND";
  parts[1] = Buffer.from(JSON.stringify(payload)).toString("base64url");
  await assert.rejects(
    () => verifyNotification(parts.join("."), testVerifier()),
    VerificationException,
  );
});

Deno.test("changing a transaction product invalidates its signature", async () => {
  const parts = transaction.split(".");
  const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  payload.productId = "everroots.legacy.annual";
  parts[1] = Buffer.from(JSON.stringify(payload)).toString("base64url");
  await assert.rejects(
    () => testVerifier().verifyAndDecodeTransaction(parts.join(".")),
    VerificationException,
  );
});

Deno.test("wrong app and environment are rejected even with a valid signature", async () => {
  await assert.rejects(
    () =>
      verifyNotification(
        notification,
        testVerifier(Environment.SANDBOX, "com.other"),
      ),
    (e: unknown) =>
      e instanceof VerificationException &&
      e.status === VerificationStatus.INVALID_APP_IDENTIFIER,
  );
  await assert.rejects(
    () =>
      verifyNotification(notification, testVerifier(Environment.PRODUCTION)),
    (e: unknown) =>
      e instanceof VerificationException &&
      e.status === VerificationStatus.INVALID_ENVIRONMENT,
  );
});

Deno.test("live Apple trust anchor rejects the fixture's untrusted certificate chain", async () => {
  await assert.rejects(
    () =>
      verifyNotification(
        notification,
        createNotificationVerifier("sandbox", "com.example"),
      ),
    VerificationException,
  );
});

Deno.test("factory cannot select Apple's unsigned local-testing mode", () => {
  for (const environment of ["LocalTesting", "Xcode", "invalid", ""]) {
    assert.throws(() =>
      createNotificationVerifier(environment, "com.everroots.app")
    );
  }
  for (const id of [undefined, "NaN", "0", "-1", "1.5"]) {
    assert.throws(() =>
      createNotificationVerifier("production", "com.everroots.app", id)
    );
  }
  assert.ok(
    createNotificationVerifier("production", "com.everroots.app", "1234"),
  );
});

Deno.test("nested transaction is verified before a notification is returned", async () => {
  let checked = false;
  await assert.rejects(() =>
    verifyNotification("outer", {
      verifyAndDecodeNotification: async () => ({
        data: { signedTransactionInfo: "forged" },
      }),
      verifyAndDecodeTransaction: async (value) => {
        checked = true;
        assert.equal(value, "forged");
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
        );
      },
    }), VerificationException);
  assert.equal(checked, true);
});

Deno.test("invalid outer signature never reaches nested verification", async () => {
  await assert.rejects(() =>
    verifyNotification("forged", {
      verifyAndDecodeNotification: async () => {
        throw new VerificationException(VerificationStatus.FAILURE);
      },
      verifyAndDecodeTransaction: async () => {
        assert.fail("must not be called");
      },
    }), VerificationException);
});

Deno.test("invalid signed input is rejected without Apple API or database access", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = () => {
    calls++;
    throw new Error("unexpected network access");
  };
  try {
    for (
      const signedPayload of [
        undefined,
        null,
        12,
        "",
        "a.b.c",
        "x".repeat(128_001),
        notification,
      ]
    ) {
      const response = await handleNotification(
        new Request("https://example.test", {
          method: "POST",
          body: JSON.stringify({ signedPayload }),
        }),
      );
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), {
        error: "Invalid Apple signed notification",
      });
    }
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("temporary verification and processing failures ask Apple to retry", () => {
  assert.equal(
    notificationErrorStatus(
      new VerificationException(
        VerificationStatus.RETRYABLE_VERIFICATION_FAILURE,
      ),
    ),
    503,
  );
  assert.equal(
    notificationErrorStatus(
      new VerificationException(VerificationStatus.INVALID_CERTIFICATE),
    ),
    400,
  );
  assert.equal(notificationErrorStatus(new Error("database unavailable")), 503);
});

Deno.test("GET cannot mutate subscription state", async () => {
  assert.equal(
    (await handleNotification(new Request("https://example.test"))).status,
    405,
  );
});
