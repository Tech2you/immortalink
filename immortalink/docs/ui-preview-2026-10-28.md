# Local UI preview - 28 October 2026

## Rollback checkpoint

- Clean source baseline: `51e9488` (`main`, before UI edits).
- Work branch: `codex/heiro-ui-preview-2026-10-28`.
- Prior signed phone app copied intact to
  `build/ios/pre-ui-2026-10-28/Runner.app` before building.
- Existing App Store/TestFlight archives remain untouched.

Scope: story-first family feed, dedicated settings page, scoped blue-white
styling, existing vault-based composer with named recordings, and tree-artwork
loading indicators. No production deployment, account mutations, store update,
submission or release. The family-tree graph, relationship logic, permissions,
storage policies and purchase configuration must remain unchanged.

To roll back after owner approval, restore only this preview's source changes
against the baseline, preserving any later unrelated work. Reinstall the prior
signed app in place when its development signature is still valid, or rebuild
the baseline with the same configuration. Never uninstall or reset account data.

## Implemented

- Story-first family feed with full-width photo carousel, inline See more,
  compact named recording rows and expandable additional recordings.
- Dedicated Settings page, preserving existing account, family, privacy,
  subscription, support and sign-out actions and confirmations.
- Compact vault header and creation controls. The plus button opens the
  existing vault-based memory composer, not a new posting/data model.
- Local recording review with pause/resume, playback and editable names.
  Multiple recordings remain local until Preserve memory. The existing voice
  title column is used; no schema change is required.
- Existing tree artwork as a gentle loading indicator, with reduced-motion
  support and no visible wordmark. The family tree itself is unchanged.

## Verification

- Local, development-signed iPhone build: Heiro 1.0.0 (33).
- Full default suite: 260 passed, 50 configuration-dependent skips.
- Billing-configured subscription suite: 49 passed, using mocks only.
- Phone, tablet, large-text, recording, settings and loading visual suite:
  15 passed. Rendered images are in `build/ui-preview-33-qa/`.
- Static analysis completed without errors. Existing repository warnings and
  infos remain, plus a test-only transitive audio-platform import lint.
- `git diff --check` passed.
- Bundle signature, identifier, associated domains, all six Apple billing
  defines, bundled artwork and compiled app icon verified. Source timestamps
  were checked against the built bundle.
- Protected source paths are unchanged against `51e9488`: `supabase/`,
  `lib/services/`, `lib/main.dart`, `ios/`, `assets/`, pubspec and lockfile.
- The existing App Store archive is build 32, dated 26 October; untouched.

Evidence: `build/ios/local-33-evidence/`. Tests used mocked services and did not
change real family content, accounts, purchases or backend configuration.

## Device Delivery

The first pre-install check failed with a CoreDevice connection-reset error.
After the owner reconnected and replied "ready", the pre-install check confirmed
build 32. Build 33 was installed in place, its installed version was independently
read back, and the app launched successfully on the connected iPhone.

Evidence files: `before-install.json`, `install.json`, `installed-apps.json` and
`launch.json` in the evidence directory. No uninstall or data reset occurred.
Real-device interaction feedback from the owner is still pending; successful
installation and launch do not by themselves prove every production workflow.

## Follow-up UI: Build 34

The owner requested the approved UI first, on the cable-connected phone, then
the payment fix. Build 34 was installed over 33, independently read back and
launched before billing source or deployed billing behavior was changed.

- Header uses the existing tree artwork; the family selector uses its actual
  family photo with a tree fallback, not a lock avatar.
- Empty family feed offers Invite family and Add a memory. The populated feed
  does not keep the onboarding invitation. Settings retains an invite action.
- Invite entry opens the existing relationship/invitation flow. The tree graph,
  membership permissions, storage rules and rate limits were not redesigned.
- About is read-first, with a separate biography editor, a compact photo strip
  and a named voice introduction. Existing import/record/replace actions remain.
- About saving now preserves existing row metadata and sharing, uses a stable
  ID for retry-safe first saves, and defaults new biographies to not being feed
  posts. Failed saves retain the draft and offer inline retry. Indexing remains
  best effort after a successful save. No RLS or media schema changes were made.
- Full default suite: 267 passed, 50 configuration-dependent skips. Static
  analysis had no errors; existing warnings and infos remain.
- Evidence: `build/ios/local-34-evidence/`; visuals in `build/ui-preview-34-qa/`
  and `build/loading-ux-qa/ui34-empty-feed.png`.
- Preserved signed builds: `build/ios/pre-34-ui/Runner.app` (33) and
  `build/ios/ui-34-before-payment/Runner.app` (34).

## Approved Payment Follow-up: Build 35

Owner decision: a fully expired subscription may be followed by a new,
Apple-confirmed purchase for the current Heiro account/family. This does not
authorize transferring active coverage or granting access from an old receipt.

- The client distinguishes checking history from confirming a purchase.
  Expired-history acknowledgement grants nothing and is not cached as a
  completed purchase. Both finished-history lookup and restored callbacks use
  this path. An unresolved unfinished charge still blocks another checkout.
- The server fetches Apple's current subscription-group status and verifies
  signed transaction and renewal payloads. Active, grace, retry, revoked,
  renewing, inconsistent and unavailable states fail closed.
- A private, 15-minute eligibility check records the previous binding and
  verified expiry. Rebinding requires a different, new signed PURCHASE with
  the current user's appAccountToken, after expiry and the check, within an
  authorized checkout window. A client cannot create these records directly.
- Rebinding is atomic with entitlement validation and retains an audit of the
  prior binding. Old transactions/notifications cannot take the plan back.
  Active coverage, one-sponsor checks, environment isolation and checkout caps
  remain enforced. No real purchase or existing ownership was changed during
  deployment; both new tables had zero rows at verification.

Deployment on 28 October 2026:
- Local migration: `20261028120027_verified_apple_repurchase_after_expiry.sql`.
- Deployed migration version: `20261028123012`, same descriptive name.
- `validate_apple_subscription`: version 19, ACTIVE, JWT verification retained.
  All ten deployed files matched the prepared payload. Other Edge Functions
  and the existing internal entitlement function were not redeployed/changed.
- Verified SQL source hashes: prepare `6ef592d2c14cd6c699bd9aa809b734f7`,
  wrapper `b81526cf67d91d29ef32efc266604df9`; internal unchanged
  `79f9fec9c51827f05b0b0436d71ed240`.
- Live RLS and grants confirmed neither anon nor authenticated can read/write
  the new billing tables or call the privileged verification functions.
- Live invalid-input/membership rejection checks passed without data writes;
  unauthenticated HTTP request returned 401.
- Security advisors: no additional WARN findings. Two additional no-policy
  INFO notices are intentional deny-by-default, service-only billing tables.
  Existing public-vector, authenticated-definer and leaked-password warnings
  remain; this is not a claim that all app security concerns are resolved.

Verification: 27 isolated database tests; 36 Apple verification tests including
live certificate/OCSP checks; 53 billing-configured Flutter tests; full default
suite 267 passed with 54 configuration-dependent skips. One exploratory full
suite run with billing flags failed only the test that asserts inert defaults;
the intended default suite and separate configured billing suite both passed.
Evidence: `build/ios/local-35-evidence/` (includes the previous Edge payload).
Build 35 is development-signed and its compiled icon catalog matches build 34.
It was installed in place over build 34 and independently read back as 1.0.0
(35). The launch request was denied because the iPhone had locked, not because
of an app crash. The owner was asked to unlock/open Heiro and check Restore
purchases before making any new purchase. Static analysis has no errors and
207 existing warning/info findings. No uninstall or account reset occurred.

Do not blindly roll back the payment database after new purchases have used
the reassignment path. Preserve its audit and reconcile any new bindings first.
App Store/TestFlight archives and the submission draft remain unchanged.
Real-device purchase validation is still required; automated tests do not
prove a new Apple sandbox checkout has completed on the owner's phone.

## Expired Unfinished Replay Follow-up: Build 36

The owner's build-35 Restore test still showed the original ownership warning.
Live logs at 12:46 UTC on 28 October confirmed two expired, non-revoked sandbox
transactions from the same retired chain, bound to another user/family. No
repurchase checks or reassignment records had been created. The purchased/
unfinished path bypassed the history-only condition and failed before the new
eligibility check could run.

- Server recovery now classifies expired foreign receipts from Apple's verified
  data regardless of StoreKit's purchased/restored label. It still requires
  Apple's current group-wide expiry check and the existing database guards.
  Active, revoked, renewing, grace, retry and unverified states cannot qualify.
- The client distinguishes an applied entitlement from expired history and a
  failure. Fully checked expired unfinished replays no longer stop the restore
  flow or a later new checkout. They are not finished, granted, or cached as
  completed purchases; each explicit check is revalidated.
- An old replay cannot release a checkout reservation or clear an in-flight/
  uncertain new-charge state. A different unresolved transaction still blocks
  another checkout. New purchases retain the build-35 ownership and token checks.
- Only the validation Edge Function changed: version 20, ACTIVE, JWT checking
  retained, all ten deployed files exactly matched the payload. No database
  migration, real ownership transfer, account change or purchase was performed.
  Unauthenticated live endpoint check returned 401.

Verification: 59 billing-configured Flutter tests, 41 Apple-verification tests
including live OCSP, 27 isolated database tests, and the full default suite
(267 passed, 60 configuration-dependent skips). Static analysis has no errors
and the same 207 existing warnings/infos. `git diff --check` passed.

Build 36 was development-signed, signature-verified, installed over build 35,
and independently read back from the phone as 1.0.0 (36). The compiled icon
catalog is identical to build 35. Opening was denied only because the iPhone
was locked. The owner must unlock/open Heiro and check Settings > Subscription
> Restore purchases, without purchasing yet. Device restore/new-purchase success
is not yet proven. No TestFlight upload or App Store draft/submission change.

Evidence: `build/ios/local-36-evidence/`, including the prior Edge version 19
payload. Previous signed app preserved in `build/ios/pre-36-payment/Runner.app`.

### Device Restore Confirmed

On 28 October the owner confirmed build 36 Restore displays "The previous
Apple plan has ended." Read-only live verification found two successful
`APPLE_EXPIRED_HISTORY` checks at 13:15:49 and 13:15:51 UTC, both in sandbox
through the purchased/unfinished replay path. The eligibility row records an
expired plan; the retired binding's purchaser and family remain unchanged,
and `apple_sponsor_reassignments` still contains zero rows. This confirms the
restore blocker is resolved without transferring old coverage. A new verified
sandbox purchase remains the next device test; it has not yet been reported
or proven. No purchase, account change, upload or submission was made here.

## Family Relationship Fixes: Build 37

The owner approved the reviewed relationship fixes, followed by deployment and
a cable build. Installation is deferred until the owner explicitly confirms
the iPhone is connected and unlocked. Do not retry installation in the meantime.

- Sibling-only creation saves a sibling edge directly, without the old child
  insert followed by an RLS-denied update. Selected shared parents remain explicit.
- Person, placeholders, relationship links and invitation are saved atomically.
  An opaque client retry ID and private server receipt prevent duplicate retries.
- New relationship writes validate same-family endpoints and reject ancestry
  cycles, including invite acceptance and concurrent writes. No existing graph
  rows were automatically repaired or reinterpreted.
- Invited-child other-parent placeholders now work. The parent-choice dialog
  scrolls on narrow phones instead of overflowing its controls.
- Older branch entry routes open the current relationship tree with the intended
  person focused. Tree appearance is retained; sibling-side canvas bounds are fixed.
- AI relationship inference no longer treats chains of half-siblings as one
  sibling group. Direct sibling, ancestry, aunt/uncle and cousin cases are tested.

Verification before deployment: 273 default Flutter tests passed (60
configuration-dependent skips), 78 separately configured billing tests passed,
68 database checks passed, five AI relationship tests passed, and three native
PostgreSQL concurrency scenarios passed (four tests including their parent).
The final focused Flutter rerun passed nine tests. Deno type checking and
`git diff --check` passed. Static analysis has no errors and the same 207 existing
warning/info findings. These checks are not a substitute for phone verification.

Deployment on 28 October 2026:
- Local migration `20261028140702_atomic_family_relationships.sql` deployed as
  version `20261028150055`, named `atomic_family_relationships`.
- All four deployed SQL function bodies exactly match local source hashes.
  Both relationship triggers are enabled. The retry table has RLS, no client
  access, and zero rows. Private helpers are not callable by clients; only the
  membership-checking public creation RPC is executable by authenticated users.
- Live no-user membership rejection passed without writes. Existing relationship
  count remained 24. No production test relatives or AI requests were created.
- Only `vault_ai_chat` was redeployed: version 88, ACTIVE, JWT verification true.
  All four deployed files exactly match the prepared payload; the three prior
  files matched the pre-change baseline before deployment. Anonymous HTTP check
  returned 401. Billing functions were not redeployed.
- Advisors added the expected private-table no-policy INFO and explicit
  authenticated SECURITY DEFINER RPC WARN. The latter is intentional for the
  atomic operation, with membership, endpoint, quota and parameter checks tested.
  See [function privilege advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  Existing public-vector and disabled leaked-password warnings remain unchanged;
  [password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Heiro 1.0.0 (37) is built at `build/ios/iphoneos/Runner.app`. Development signature,
bundle identifier, associated domains, push entitlement and all six Apple billing
defines are verified. The compiled icon catalog is identical to build 36. No
source or asset file is newer than the built application. Sandbox-only signature
inspection could not read the trust chain; normal macOS trust verification passed.

Evidence is in `build/ios/local-37-evidence/`, including the prior Edge payload.
The previous signed build 36 is preserved at
`build/ios/pre-37-relationships/Runner.app`. At this checkpoint build 37 was not
installed or uploaded; see the subsequent device installation below.
No App Store draft, TestFlight group, account, billing sponsorship, family media
or real family relationship was changed. Previously misclassified relatives need
owner identification and a separate targeted correction; do not guess.

### Build 37 Device Installation

On 28 October the owner replied "ready" to resume the deferred cable installation.
The connected iPhone independently reported build 36 before installation. The
prepared build 37 passed strict signature verification, was installed in place
without uninstalling Heiro, and was independently read back as 1.0.0 (37).
Opening Heiro succeeded on a bounded retry after a transient device connection
drop. The earlier pre-install connection drop also recovered on one bounded
retry. Neither failure required a reset, reinstall, or account change.

Evidence: `build/ios/local-37-evidence/before-install-retry.json`, `install.json`,
`installed-apps.json`, and `launch-retry.json`. The owner still needs to verify
that a newly added sibling with no selected shared parent appears alongside the
focused person rather than under Children. Automated relationship and regression
test results above remain the evidence for correctness until that phone test.
Existing incorrectly stored relationships remain untouched. No backend redeploy,
TestFlight upload, App Store draft change, submission, or release was performed
during installation.
