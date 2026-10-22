// Certificate fixtures from Apple's MIT-licensed v3.1.0 jws_verification.test.ts.
import { strict as assert } from "node:assert";
import { Buffer } from "node:buffer";
import { Environment } from "npm:@apple/app-store-server-library@3.1.0";
import { SignedDataVerifier, VerificationException } from "../_shared/apple_vendor/jws_verification.ts";
import { X509Certificate } from "../_shared/apple_vendor/x509_compat.ts";
import certificates from "./test_fixtures/apple-certificates.json" with { type: "json" };

class ChainVerifier extends SignedDataVerifier {
  check(leaf: string, intermediate: string, date = new Date()) {
    return this.verifyCertificateChain(this.rootCertificates,
      new X509Certificate(Buffer.from(leaf, "base64")),
      new X509Certificate(Buffer.from(intermediate, "base64")), date);
  }
}
const c = certificates;
const synthetic = () => new ChainVerifier(
  [Buffer.from(c.ROOT_CA_BASE64_ENCODED, "base64")], false, Environment.SANDBOX, "com.example",
);

Deno.test("certificate adapter preserves purpose and expiry rejection", async () => {
  await synthetic().check(c.LEAF_CERT_BASE64_ENCODED, c.INTERMEDIATE_CA_BASE64_ENCODED);
  await assert.rejects(() => synthetic().check(c.LEAF_CERT_INVALID_OID_BASE64_ENCODED,
    c.INTERMEDIATE_CA_BASE64_ENCODED), VerificationException);
  await assert.rejects(() => synthetic().check(c.LEAF_CERT_FOR_INTERMEDIATE_CA_INVALID_OID_BASE64_ENCODED,
    c.INTERMEDIATE_CA_INVALID_OID_BASE64_ENCODED), VerificationException);
  await assert.rejects(() => synthetic().check(c.LEAF_CERT_BASE64_ENCODED,
    c.INTERMEDIATE_CA_BASE64_ENCODED, new Date("2040-01-01")), VerificationException);
});

Deno.test({
  name: "live Apple certificate chain and both OCSP responders verify",
  ignore: Deno.env.get("APPLE_LIVE_OCSP_TEST") !== "1",
  fn: async () => {
    const verifier = new ChainVerifier([Buffer.from(c.REAL_APPLE_ROOT_BASE64_ENCODED, "base64")],
      true, Environment.SANDBOX, "com.example");
    await verifier.check(c.REAL_APPLE_SIGNING_CERTIFICATE_BASE64_ENCODED,
      c.REAL_APPLE_INTERMEDIATE_BASE64_ENCODED);
  },
});
