# Apple notification verification

The public Apple callback verifies JWS signatures using Apple's verifier source
with a documented Deno compatibility adapter before accessing Supabase. See
`../_shared/apple_vendor/README.md` for the pinned upstream version and changes.
Its pinned Apple
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
APPLE_LIVE_OCSP_TEST=1 npx -y deno@2.1.4 test --allow-env --allow-read --allow-net --no-check --no-lock supabase/functions/apple_subscription_notifications/notification_verifier_test.ts supabase/functions/apple_subscription_notifications/certificate_compat_test.ts supabase/functions/validate_apple_subscription/product_validation.test.ts
npx -y deno@2.9.0 check supabase/functions/apple_subscription_notifications/index.ts supabase/functions/validate_apple_subscription/index.ts
```

Fixtures under `test_fixtures` are Apple's public synthetic test data from
https://github.com/apple/app-store-server-library-node/tree/main/tests/resources
and carry Apple's MIT license (included there). Fixture verifiers disable OCSP
because their synthetic certificates have no responder. The production factory
always enables online checks and rejects the fixture trust anchor.
`apple-certificates.json` contains Apple's v3.1.0 public certificate fixtures from
`tests/unit-tests/jws_verification.test.ts`; the optional live OCSP test checks
both real Apple responders without making a purchase. Test the deployed Deno
version as well as a current compiler: newer Node compatibility hid a live failure.

Before launch, confirm a genuine Apple sandbox notification is delivered and
processed, and verify production app ID/environment configuration separately.
Local synthetic signature tests do not prove live Apple delivery. Ordering and
replay protection are handled by `apply_verified_family_subscription` in SQL.
