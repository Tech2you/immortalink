# Confirmed contribution move / build 41

Requested behavior: after the original payer leaves a family and joins or creates another, offer **Move my contribution** in Family storage. Moving requires a current Apple-signed active transaction and renewal response, plus an explicit confirmation. It changes the family receiving the existing benefit, without checkout or product/price/renewal changes.

## Safeguards

- Authenticated original payer and current target-family membership; payer must have left the source family.
- Service-only move RPC and private quotes/audit/billing records; 20 Apple move checks per payer per minute.
- Quote expires after ten minutes and becomes stale when source usage or billing changes. Repeated confirmations are idempotent.
- Used pooled AI/transcription allowance follows proportionally. Old-family usage is credited only up to lost capacity, protecting the free/beta allowance floor from reset exploits.
- A private billing record preserves an active contribution and consumed allowance if the old tree is deleted. Later verified renewals/refunds update that record.
- Normal renewal/refund processing follows the new binding. Membership, vaults, content, ownership, Apple products and prices are unaffected by the move itself.
- Existing purchases, expired-history recovery, free/beta access and grandfathered storage retain their existing guards.

## Local proof

- Billing/UI regression: 94 passed (including five move interaction/layout tests).
- Full default Flutter suite: 289 passed, 71 feature-gated skips; billing-enabled tests run separately above.
- Database pool/move regression: 34 passed; existing sponsorship regression: 27 passed.
- Real PostgreSQL concurrency: move/usage/duplicate/refund test passed; existing simultaneous payments/refunds test passed.
- Apple helper tests: 26 passed. Deno type check passed. New Dart files analyze without findings.

## Delivery state

- Production migration **deployed**, after explicit user approval: `20261030192334_confirmed_family_contribution_moves.sql`. Local filename aligned with verified live migration history. Permission changes are limited to named move helpers; no schema-wide revocation remains.
- iPhone release build 41 compiled and passed code-signature verification. Installed in place on ROSS's iPhone (3); device inventory independently confirms Heiro `com.everroots.app`, version 1.0.0, bundle version 41. Launch succeeded. The first installation connection reset; a read-only connection check recovered the connection and the next attempt succeeded. No uninstall, TestFlight upload or App Store draft changes.
- User subsequently explicitly approved the live billing update. `validate_apple_subscription` version **21** is ACTIVE with JWT verification enabled. All eleven deployed source files independently read back identical to the prepared sources. An unauthenticated preview request returned HTTP 401.
- Device proof: `/private/tmp/heiro-build41-install.json`, `/private/tmp/heiro-build41-installed-app.json`, `/private/tmp/heiro-build41-launch.json`.
- Build 40 backup: `/private/tmp/heiro-build40-before-move.app`.
- Previous deployed validator source: `/private/tmp/heiro-move-edge-before.json` (version 20).
- Live disposable-data check **passed**: `supabase/tests/contribution_move_live_canary.sql`. Supabase's confirmation expired twice; user then confirmed readiness and approved the reopened prompt. Whole transaction rolled back; final query found zero test bindings. Verified preview does not move benefits, wrong-payer rejection, a confirmed move, duplicate confirmation without double usage, preserved vaults/membership, ordinary quota consumption, and preservation/moving of a contribution after deleting its old family. This validates database behavior, not a real Apple move.
- Live access readback: all four new private tables have RLS and no authenticated-client table access; both move RPCs are callable by service_role only, not anon/authenticated. Advisor warning counts unchanged; the existing authenticated sponsorship endpoint now has a SQL wrapper rather than PL/pgSQL. Its private implementation and candidate lookup both enforce membership. Expected informational notices cover four deliberately inaccessible RLS tables and their new unused indexes. Relevant advisor explanation: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- Real Apple move verification and user acceptance of the feature are still pending; installation, launch, deployed source/access checks, and the live rolled-back database test are confirmed. No real contribution was moved, and no TestFlight upload or App Store draft change occurred.

## Phone follow-up: missing button, 30 October at 23:23 SAST

- Reviewed the supplied ten-second screen recording. It shows the new family's free 500 MB bucket, no contributors, and purchase verification in progress with temporarily disabled checkout buttons. No move card is shown.
- Read-only billing inspection shows Ross in My Family, with his own contribution to Ross Family already expired at 20:19:07 UTC (22:19:07 SAST), before the recording. The separate Linebreakers contribution is active but remains attached to its current family. Neither account currently satisfies the move rule (original payer, active contribution, left the source family, joined a different family).
- Validator logs identify Ross as the caller and repeatedly return successful APPLE_EXPIRED_HISTORY acknowledgements around the recording, including at 21:23:22 UTC. One earlier history check failed transiently at 21:22:48 UTC, followed by successful checks. Logs do not contain transaction IDs, so they do not establish whether these are duplicate receipts or distinct old queued receipts; do not describe this as a proven infinite loop.
- The absent move button is expected for the observed account state. No billing entitlement or code was changed during this diagnosis. A genuine active Apple contribution move remains untested on the phone.
