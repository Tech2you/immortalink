# Single-family launch scope — 25 October 2026

The owner chose to defer multiple-family membership and multiple-family
sponsorship until customer feedback establishes demand.

## Launch behavior

- An account without a family may create a family or accept an invite.
- An account with a family cannot add another family, on any plan. This is
  separate from the number of relatives allowed within a family.
- The app removes additional-family creation/join actions and promotional copy.
  Invite links still open the join flow; the server permits same-family
  relationship updates and rejects attempts to join a different family with a
  clear message. A failed join does not consume the invite.
- Existing memberships are preserved, including accounts already belonging to
  multiple families. Their tree access and home-family switching remain usable.
- Leaving a family remains an explicit user action through the existing flow,
  with its existing data-retention and Apple-billing warnings. No account is
  automatically removed from a family or moved to another family.
- Storage, prices, per-family member caps, subscriptions and private-vault access
  are unchanged.

## Implementation and evidence

`20261025095147_single_family_launch_guard.sql` adds a trigger on membership
admission in a private `family_access` schema. It serializes admissions per
account and checks for an existing membership. Both invite RPCs and the create
RPC are covered, including callers using an older app. Existing row updates and
same-family upserts are retained. No existing rows are backfilled or deleted.
The concurrency check uses the Data API's READ COMMITTED transaction isolation.

The live create RPC and vault triggers were inspected read-only: vault creation
does not automatically create a family. A personal vault therefore does not
block a first invite. An explicitly created empty family remains a real
membership until the user leaves it.

Local database verification:

- PGlite: 8 new admission tests plus 3 existing membership-access tests passed.
- Embedded PostgreSQL: 8 simultaneous-admission scenarios passed (9 test results
  including the parent): direct inserts, creation and both invite paths, and
  release after transaction rollback.
- Independent review found no actionable issues in the scoped change.

Live backend deployment and read-only verification on 25 October 2026:

- Applied only `single_family_launch_guard` to project
  `vbzyvaylfdhwowdbodmk`; Supabase recorded version `20261025095147`.
  No unrelated pending migrations were pushed.
- The installed function body exactly matches the tested migration. The
  `family_members_single_family_launch_guard` trigger is enabled for INSERT and
  updates of `family_id` or `user_id`. The database default isolation remains
  READ COMMITTED.
- The helper is SECURITY DEFINER with an empty search path in the private
  `family_access` schema. `anon`, `authenticated` and `service_role` have no
  schema usage/create privilege or direct function execute privilege.
- Before/after privacy-safe fingerprints match for all membership rows, all
  family rows and vault-family links. Counts remained 7 memberships, 6 families
  and 6 vaults, including one existing multi-family account.
- The security advisor comparison found no new or resolved findings; existing
  notices remain unchanged. Verification did not create, join, leave or modify
  any production account or family.
- The local filename and test helper were aligned to the remote migration
  version. The 11 PGlite admission/access tests passed again afterwards.

Local Flutter verification:

- 2 new widget tests cover the first-family entry points, existing-family access,
  missing-vault invite onboarding and the deep-linked second-family rejection.
- 32 related onboarding, pending-invite, family-menu, plan-screen, public-error
  and quota tests passed. Six purchase-configured cases were skipped in that
  default run; all 19 plan-screen tests then passed with Apple purchase flags
  enabled, including those six cases.
- The full Flutter suite passed with 201 tests and 50 configured skips after a
  test-only `detectSessionInUri: false` fixture correction.
- Analysis of the home screen reported no errors or warnings; it retained 42
  existing informational diagnostics (deprecated opacity calls and an existing
  async-context check). This is not a zero-lint claim.
- `git diff --check` passed.

Reproduction commands (the optional module paths use the installed local test
runtime; normal package resolution also works):

```sh
PGLITE_MODULE=/private/tmp/heiro-retirement-tests/node_modules/@electric-sql/pglite/dist/index.js node --test supabase/tests/single_family_launch.test.mjs supabase/tests/family_membership_access.test.mjs
EMBEDDED_POSTGRES_MODULE=/private/tmp/heiro-retirement-tests/node_modules/embedded-postgres/dist/index.js node --test supabase/tests/single_family_launch_concurrency.test.mjs
```

## Release status

Subsequent icon-only delivery: build 1.0.0 (25) includes this same app code with
the new turquoise home-screen icon. It is processed/Validated, assigned to
Internal Beta, and selected/saved in the App Store version. The existing draft
has all six items, including 1.0.0 (25), and manual release remains selected.
No submission or release occurred. The owner confirmed build 25's correct
home-screen icon and unchanged in-app images on their phone. That visual pass
does not relabel the functional build-24 evidence below as build-25 evidence.
See `heiro-home-icon-2026-10-25.md`. The current archive/IPA paths now hold
build 25; build 24's archive is preserved under
`build/ios/release-24-evidence/Runner.xcarchive` and its IPA/evidence in that folder.

The backend membership restriction is deployed and its installed definition,
trigger, privileges and data preservation are verified. The owner authorized
TestFlight preparation/upload and explicitly excluded App Store review submission.

Build 1.0.0 (24) has been archived and exported using
`scripts/build_ios_testflight_purchases.sh`, with the existing six Apple billing
values, release mode and explicit build name/number. Verified IPA identity:
Heiro / `com.everroots.app` / 1.0.0 / 24. Its Apple Distribution signature passed
deep/strict verification for team `DNLP6MCWMN`; production push,
`beta-reports-active=true`, `get-task-allow=false` and both associated domains are
preserved. SHA-256:
`35a95cd0312349cb5ad1baac45ff2481e7e6eeb4fd54f29655e275af3bbc440a`
(33,445,968 bytes). All 120 source-manifest files match the pre-build snapshot.
The pending content-screening controls remain compile-time disabled.

Source HEAD is `008859b60aa395ff42314f3c74a6cbbbb5eef4d0` plus the existing working
tree. Build artifacts and evidence are under `build/ios/archive/Runner.xcarchive`,
`build/ios/ipa/Heiro.ipa` and `build/ios/release-24-evidence/` (source manifest,
patch, export settings, artifact verification and build/test logs). The previous
build 23 archive/IPA is preserved under `/private/tmp/heiro-build-23-checkpoint/`.
Flutter reported its existing default-launch-image warning; the archive and IPA
export succeeded. Native dependencies and crypto-relevant source are unchanged
from build 23; this is source continuity, not a new encryption declaration.

Xcode uploaded the same build 24 archive through App Store Connect using the
existing Apple account. `xcodebuild -exportArchive` returned exit 0 and
`EXPORT SUCCEEDED`; its upload log recorded “Upload succeeded” at 12:05:37 SAST
on 25 October 2026. Apple reported that the uploaded package was processing.
Transporter was closed after stalling at app lookup; no Deliver action was taken
there.

Subsequent read-only App Store Connect verification on 25 October confirms
1.0.0 (24) has finished processing: TestFlight lists Ready to Submit, Binary
State is Validated, and App Uses Non-Exempt Encryption is No. Internal Beta has
the build and one tester. No install/crash metrics were available at that check;
missing metrics are not a zero-crash result. The owner then answered "yes" to
installing 1.0.0 (24) through TestFlight and opening their family, tree and an
existing photo/voice memory. This is owner-confirmed bounded iPhone smoke
evidence, not independent installation inspection or complete acceptance.

At that earlier check the App Store version draft still selected build 23.
The subsequent build-25 delivery above supersedes that selection without
submitting the app for review.

Before release, complete owner/device verification of the selected candidate. Confirm first-family
creation, first invite, blocked second invite, and preserved access for an
existing member on the release candidate. The production verification above is
metadata and data-preservation evidence; it does not replace device or TestFlight
flow verification. Existing launch gates remain applicable.

To reintroduce multiple-family support later, remove this admission guard through
a reviewed migration and restore the app entry points. The existing family data
model is preserved. Multiple-family sponsorship would still require its separate
Apple/product and billing design.
