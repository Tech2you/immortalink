import type { AppleEnvironment } from "../_shared/apple_environment.ts";

// Only read-only Apple status requests are retried. Invalid signatures or
// inconsistent identities are never retried or accepted as valid proof.
export class AppleStatusCheckError extends Error {
  constructor(
    readonly stage:
      | "network"
      | "http"
      | "json"
      | "payload"
      | "transaction_fields",
    readonly httpStatus?: number,
  ) {
    super("APPLE_HISTORY_CHECK_UNAVAILABLE");
  }
}
export async function fetchSubscriptionStatus(o: {
  originalId: string;
  environment: AppleEnvironment;
  token: string;
  fetcher?: typeof fetch;
}): Promise<unknown> {
  const host = o.environment === "production"
    ? "api.storekit.apple.com"
    : "api.storekit-sandbox.apple.com";
  const signal = AbortSignal.timeout(15000);
  for (let attempt = 0; attempt < 2; attempt++) {
    let response: Response;
    try {
      response = await (o.fetcher ?? fetch)(
        `https://${host}/inApps/v1/subscriptions/${
          encodeURIComponent(o.originalId)
        }`,
        {
          headers: { Authorization: `Bearer ${o.token}` },
          signal,
        },
      );
    } catch {
      if (attempt === 0 && !signal.aborted) continue;
      throw new AppleStatusCheckError("network");
    }
    if (!response.ok) {
      const retryable = response.status === 429 || response.status >= 500;
      await response.body?.cancel();
      if (attempt === 0 && retryable && !signal.aborted) continue;
      throw new AppleStatusCheckError("http", response.status);
    }
    try {
      return await response.json();
    } catch {
      throw new AppleStatusCheckError("json");
    }
  }
  throw new AppleStatusCheckError("network");
}
