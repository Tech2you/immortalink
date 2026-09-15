# Apple notification verification

The public Apple callback verifies JWS signatures using Apple's official server
library before reading transaction data or accessing Supabase. Its pinned Apple
Root CA G3 comes from Apple's public PKI page. Certificate revocation checks are
enabled; configuration, network and database failures return a retryable 503.

Keep `verify_jwt = false`: Apple does not send Supabase user JWTs. Authentication
is the Apple certificate chain, JWS signatures, bundle ID and environment checks.
Never enable Xcode/LocalTesting verification modes or add test roots to live code.

Configuration:
- `APPLE_BUNDLE_ID`: defaults to `com.everroots.app`.
- `APPLE_IAP_ENVIRONMENT`: `sandbox` (default) or `production` only.
- `APPLE_APP_ID`: numeric App Store Connect app ID, required for production.
- Existing Apple Server API and Supabase service credentials remain required.

Run from the repository root:

```sh
npx deno test --allow-env --allow-read --config=supabase/functions/apple_subscription_notifications/deno.json supabase/functions/apple_subscription_notifications/notification_verifier_test.ts
```

Fixtures under `test_fixtures` are Apple's public synthetic test data from
https://github.com/apple/app-store-server-library-node/tree/main/tests/resources
and carry Apple's MIT license (included there). Fixture verifiers disable OCSP
because their synthetic certificates have no responder. The production factory
always enables online checks and rejects the fixture trust anchor.

Before launch, confirm a genuine Apple sandbox notification is delivered and
processed, and verify production app ID/environment configuration separately.
Local synthetic signature tests do not prove live Apple delivery. This change
does not implement notification ordering or replay deduplication.
