export type AppleEnvironment = "production" | "sandbox";

export class AppleTransactionLookupError extends Error {
  constructor(readonly status: number, readonly environment: AppleEnvironment) {
    super(`Apple transaction lookup failed ${status}`);
    this.name = "AppleTransactionLookupError";
  }
}

export function notificationEnvironment(signedPayload: unknown): AppleEnvironment {
  // This is only a verifier-selection hint. No claim is trusted until the
  // selected verifier has checked Apple's signature, app and environment.
  if (typeof signedPayload !== "string" || signedPayload.length > 128_000) {
    throw new Error("Invalid notification envelope");
  }
  const parts = signedPayload.split(".");
  if (parts.length !== 3) throw new Error("Invalid notification envelope");
  const encoded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const payload = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
  const environment = payload.data?.environment ?? payload.summary?.environment ?? payload.externalPurchaseToken?.environment;
  if (environment === "Production") return "production";
  if (environment === "Sandbox") return "sandbox";
  throw new Error("Invalid notification environment");
}

export async function lookupAppleTransaction<T>(options: {
  transactionId: string;
  token: string;
  verify: (signed: string, environment: AppleEnvironment) => Promise<T>;
  environment?: AppleEnvironment;
  fetcher?: typeof fetch;
}): Promise<T> {
  const fetcher = options.fetcher ?? fetch;
  const request = (environment: AppleEnvironment) => fetcher(
    `https://api.storekit${environment === "sandbox" ? "-sandbox" : ""}.itunes.apple.com/inApps/v1/transactions/${encodeURIComponent(options.transactionId)}`,
    { headers: { Authorization: `Bearer ${options.token}` }, signal: AbortSignal.timeout(15000) },
  );
  let environment = options.environment ?? "production";
  let response = await request(environment);
  if (!options.environment && response.status === 404) {
    const error = await response.clone().json().catch(() => ({}));
    // Apple's documented transaction-not-found response is the only fallback.
    if (error.errorCode === 4040010) {
      environment = "sandbox";
      response = await request(environment);
    }
  }
  if (!response.ok) throw new AppleTransactionLookupError(response.status, environment);
  const payload = await response.json();
  if (typeof payload.signedTransactionInfo !== "string" || !payload.signedTransactionInfo) {
    throw new Error("Apple transaction response missing signed data");
  }
  return options.verify(payload.signedTransactionInfo, environment);
}
