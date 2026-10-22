# Family sponsorship - 28 September 2026

## Scope and evidence

Updated after deployment and phone installation on 28 September 2026. The reviewed
billing backend and matching iPhone build are now deployed for sandbox testing.
No real Apple purchase was performed by the agent and no account was deleted.
Existing working-tree changes were preserved. This note supersedes the earlier
billing implementation status, not the deletion release gates, in
launch-engineering-2026-09-28.md.

Private-vault permissions, shared legacy editing, relationship creation, ordinary
Leave family behavior and monthly plan allowances were not redesigned. The leave
confirmation now also warns that Apple billing does not stop when leaving.

## Implemented and deployed

- Any current family member may reserve checkout and sponsor the family. The
  previous owner-only billing restriction is removed from the validation handler.
- Fifteen-minute server reservation before Apple checkout; family-locked atomic
  entitlement application prevents two active sponsors being assigned together.
- Original Apple subscription permanently bound to purchaser UUID and family;
  a new binding requires the verified appAccountToken and a matching reservation.
  Tokenless historical purchases require their existing recorded binding.
- Replacement after expiry retires the previous subscription chain. Its later
  renewals cannot overwrite the replacement. Replayed/older transactions do not
  overwrite newer entitlements. Cancellation intent alone does not end paid access.
- Purchase validation and notifications use Apple signature verification and the
  same service-only SQL application function. Raw Apple audit records are no
  longer client-readable; members receive a limited sponsorship summary instead.
- App Store localized product prices remain authoritative. A sponsor label,
  disabled competing checkout, bounded connection waits, and friendly errors are
  added. No hardcoded currency conversion was introduced.
- Existing deletion warning retained; Leave family now has the same Apple
  cancellation warning and management link with a manual-settings fallback.
- Per-member bursts limited to six AI units and three transcription starts per
  minute. Monthly quotas unchanged. Cooldown is not presented as an upgrade need.
- A service-only, deduplicated conflict ledger records unmatched, late and retired
  subscription events without names, emails or raw signed payloads. Unmatched
  first notifications return HTTP 503 so Apple can retry after app-side binding.
  These records still require a support/reconciliation procedure.

## Current deployment and device evidence

- Project: `vbzyvaylfdhwowdbodmk`.
- `validate_apple_subscription`: version 8, ACTIVE, gateway JWT verification on.
- `apple_subscription_notifications`: version 7, ACTIVE, gateway JWT verification
  off intentionally; the handler verifies Apple's signed notification.
- Applied migrations:
  - `20260928212919_family_owner_successor.sql`
  - `20260928212929_expired_family_read_only.sql`
  - `20260928212954_family_sponsorship.sql`
  - `20260927230146_usage_burst_protection.sql`
- The first three local filenames were aligned to versions assigned by the live
  migration tool. Their test references were updated too.
- Signed release-mode development build `1.0.0 (2026092801)` was installed and
  launched on the connected iPhone. Bundle ID: `com.everroots.app`; display name:
  Ever Roots. This was not a TestFlight upload or public release.
- Build enables Apple purchases, subscription group `22339684`, and the four
  existing `everroots.family.*` / `everroots.legacy.*` monthly/annual products.
- Live Apple verification is configured for SANDBOX. Required signing secrets
  exist; `APPLE_APP_ID` was not listed. Production verification and sandbox review
  support must be finished before public release. No secret values were exposed.
- Live rolled-back SQL preflight passed: ordinary-member checkout, competing
  reservation rejection, purchaser binding, unchanged tree role, and burst guard.
  Temporary reservation, entitlement, ledger and usage writes were rolled back.
  This is not an actual StoreKit purchase or a multi-session concurrency test.
- New private billing tables have RLS; raw Apple event records are not readable by
  authenticated clients. Sensitive apply/conflict/handoff functions are service
  only; member-facing checkout/status RPCs retain explicit membership checks.
- Real HTTP negative checks passed: anonymous validation returned 401 and a forged
  Apple notification returned 400. Neither created a purchase or entitlement.

Deployment tooling initially returned internal errors; final retries succeeded.
Standard CLI dry-run also identified seven historical remote versions absent from
the checkout. No remote history was repaired or reverted. A one-off isolated
deployment directory used metadata-only placeholders for already-applied versions
and the real burst migration; its dry-run selected only that pending migration.
That directory is NOT a schema source for recreating a database. Reconcile the
historical migration drift before relying on normal automated deployments.

## Local verification

- Default Flutter suite: 99 passed, 14 purchase-config-dependent tests skipped.
- Purchase-enabled focused service/warning/quota run: 26 passed before the extra
  cooldown-copy test; that additional quota test is covered by the default suite.
- Whole Flutter suite with purchase flags: 112 passed, one expected configuration
  mismatch in the test asserting default purchases-disabled behavior. Use separate
  default-suite and purchase-enabled service runs rather than ignoring that test.
- PGlite: 16 tests passed across sponsorship, burst protection, expired read-only
  access and the existing successor helper. These fixtures do not prove live RLS,
  full-schema compatibility, Storage behavior or simultaneous database sessions.
- Deno: 17 Apple signature/product tests passed; both changed handlers type-check.
- Focused service analysis was clean. Analysis including the existing large tree
  and vault screens reports 45 warning/info findings, including the unused former
  grandchild helper, deprecated colors and an async-context warning; not zero-lint.
- git diff --check passed.

## Phone test order

1. Open Ever Roots, build `2026092801`, and sign into Linebreakers. The old
   `com.example.immortalink` installation, if visible, is not this test build.
2. Use a fresh/separate Apple Sandbox tester for Linebreakers' new purchase, with
   South Africa as its storefront. App login and Apple Sandbox login are separate.
   The previously recorded Ross purchase remains bound to Ross; rejection when
   Linebreakers tries to restore that purchase is correct, not a reason to rebind it.
3. Check the plan screen loads localized App Store prices. Make just one purchase
   after confirming Apple's sheet is a sandbox test. Report the result so the live
   purchaser/family/entitlement can be checked before continuing.
4. Sign into Ross in the same family. Confirm family benefits without another
   purchase and without changing who sponsors. Then test rightful-account restore
   and wrong-account rejection separately, checking the backend after each case.
5. Continue with join-after-purchase, expiry/replacement, delayed approval,
   renewal/refund, offline and account-switching cases. These are still unverified
   on the physical device.

Do not delete either test account or run last-member cleanup tests yet. The SQL
preflight file deliberately requires the initial free-family state; do not rerun
it after a genuine sandbox purchase.

Apple's sandbox setup guide:
https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/

## Must finish before paid launch

1. Finish shared-media-safe account deletion before destructive tests. Existing
   `delete_account` still removes uploader-prefix shared legacy media. The deployed
   successor helper is not yet wired into safe, retryable deletion. Preserve shared
   rows/bytes/read access for remaining members, delete personal data, and prove
   last-real-member cleanup. This is the next engineering priority.
2. Exercise genuinely concurrent purchases in PostgreSQL and real Apple pending,
   cancellation, delayed approval, restore and refund flows. A checkout reservation
   protects entitlement assignment, not a guarantee against every Apple charge.
   Durable conflict recording is deployed, but recovery and a support/refund route
   still need operational proof. Retired renewals are recorded, not silently lost.
3. Confirm production versus sandbox configuration and Apple grace-period handling.
   Current transaction-based expiry does not implement signed renewal grace data.
   Test renewal/expiry/refund ordering with Apple's actual signed payloads.
4. Test Linebreakers and Ross separately: member purchase, other-account restore
   rejection, existing join-after-purchase, replacement, currency/storefront and
   leave warnings. Do not infer these from mocks or a successful upload.
5. Coordinate the matching mobile/backend rollout. Older apps without reservations
   cannot safely claim new purchases under this model. Reconcile the seven missing
   historical local migration versions before repeatable CI deployment.
6. Define minimal transaction-binding retention and support reconciliation after
   account deletion. The ledger stores UUIDs/transaction IDs, not names/emails;
   these remain identifiers and require an explicit privacy/retention policy.
7. Complete the Heiro name/domain decision and clearance, migrate sender/domain
   verification and auth/invite/support links while preserving old-link continuity,
   and update privacy, terms, deletion, cancellation and retention disclosures.
8. Verify Apple paid agreements, banking/tax, production products/notifications,
   privacy labels, review credentials, screenshots and support links. TestFlight
   success alone does not establish readiness to accept public payments.
9. Review provider capacity, spend controls/alerts, backups and restore, monitoring,
   abuse/report handling and incident/support procedures. Burst guards do not cap
   every possible infrastructure cost. Fresh security advisors still flag leaked
   password protection disabled, authenticated SECURITY DEFINER RPCs for review,
   and `vector` in `public`. Private service-only tables intentionally have no
   client RLS policies; do not open them merely to remove advisor information items.

Public paid release remains NO-GO until these gates have evidence. No automated
test suite can establish that an app is unhackable or remove legal liability.
