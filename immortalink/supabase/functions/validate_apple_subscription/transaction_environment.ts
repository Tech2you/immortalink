import type { AppleEnvironment } from "../_shared/apple_environment.ts";

type VerifiedTransaction = { transactionId?: string; environment?: string };

export async function transactionEnvironment(options: {
  transactionId: string;
  signedTransaction: unknown;
  verify: (signed: string, environment: AppleEnvironment) => Promise<VerifiedTransaction>;
  previousEnvironments: () => Promise<string[]>;
}): Promise<AppleEnvironment | undefined> {
  const signed = options.signedTransaction;
  if (signed !== undefined && signed !== null && signed !== "") {
    if (typeof signed !== "string" || signed.length > 128_000) {
      throw new Error("Invalid signed Apple transaction");
    }
    const parts = signed.split(".");
    if (parts.length !== 3) throw new Error("Invalid signed Apple transaction");
    const encoded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const hint = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "="))).environment;
    if (hint !== "Sandbox" && hint !== "Production") {
      throw new Error("Invalid Apple transaction environment");
    }
    // The decoded claim selects a verifier only. Trust it only after the Apple
    // signature, bundle and environment checks have all succeeded.
    const environment = hint === "Sandbox" ? "sandbox" : "production";
    const verified = await options.verify(signed, environment);
    if (verified.transactionId !== options.transactionId || verified.environment !== hint) {
      throw new Error("Apple transaction identity mismatch");
    }
    return environment;
  }

  // Older recovery clients omitted their JWS. A previously verified event for
  // this exact transaction can select the endpoint, never grant an entitlement.
  const environments = [...new Set(await options.previousEnvironments())];
  if (environments.length === 1 &&
      (environments[0] === "sandbox" || environments[0] === "production")) {
    return environments[0];
  }
  return undefined;
}
