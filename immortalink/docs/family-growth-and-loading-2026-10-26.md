# Family growth and loading - 26 October 2026

Status: backend deployed with owner approval; build 27 uploaded successfully
at 10:38 SAST, processed and assigned to Internal Beta (one tester).
Hosted rollback verification passed. Build 27 is now the saved and staged
App Store draft candidate, independently verified after reload.
No submission or release is authorized.

## Owner decisions

The owner approved these limits and identified opening the app and loading
photos as the slow areas:

| Rule | Free | Family | Legacy |
| --- | ---: | ---: | ---: |
| Total real family members | No headcount cap | No headcount cap | No headcount cap |
| Legacy profiles, including retained replacements | 8 | 100 | 250 |
| Invites per sender, rolling hour | 20 | 20 | 20 |
| Invites per family, rolling hour | 50 | 50 | 50 |
| Pending invites | 10 | 25 | 50 |
| Sender/family cooldown | 10 seconds | 10 seconds | 10 seconds |
| Storage | 500 MB | 10 GB | 50 GB |

Monthly invitation totals no longer gate growth. Hourly sender usage is shared
across any grandfathered families. Full storage blocks new invites, accepting
old invites and adding legacy profiles. Incoming members' existing personal
media must fit the remaining allowance. Existing members are not removed;
same-family membership updates, ordinary profile edits and existing access
remain available. Existing expired-plan read-only rules otherwise remain.
One family per account remains the launch rule; it is not a family-size cap.

## Implementation

- `20261026080435_family_growth_admission_guards.sql` and
  `20261026080449_family_growth_invitation_limits.sql` change only
  growth gates and invitation accounting. A private ledger survives consumed
  or deleted invites. Client timestamps are ignored, and old invite identities
  cannot be recycled to bypass rates. Existing media lifecycle locking is
  acquired at join RPC entry before row locks, protecting concurrent uploads
  and admissions without changing the Storage quota function.
- No real family names, membership records, stored media, subscription prices,
  product IDs, ownership, sponsorship or AI/media allowances are rewritten.
- Fresh batch-signed media links replace per-image requests in tree, feed,
  personal-vault and legacy-vault loading. Requests contain at most 100 paths;
  link lifetime stays one hour and no persistent signed-link cache is added.
  Missing/denied images remain absent. Originals and image quality are unchanged.
- Home family navigation no longer waits for the optional own-avatar request.
  Independent legacy sections and memory photo/audio loading overlap; memory
  text can appear before all media links finish loading.
- Member and tree relationship queries paginate; vault-owner filters use
  batches of 50. This avoids the old silent database row-limit truncation and
  excessively long URLs. Feed queries still display the newest 12 memories.
- Invite-rate errors explain waiting rather than suggesting a paid upgrade.

## Evidence

Read-only live inspection found the old real-member caps 8/20/30, monthly invite
caps 25/50/100, pending limits and cooldown. No rolling hourly cap was found.
The existing legacy limits were 8/100/250. After explicit owner approval, the
two growth migrations above replaced the old member/monthly-invite gates.
A scoped CLI dry run and push applied only those two files, not the unrelated
screening migrations. Hosted disposable checks passed and rolled back.
Existing data/policy hashes match; only expected function definitions changed.
See `security-check-2026-10-26.md` for the separately approved security fixes.

The previous 24-hour aggregate edge logs contained no 5xx for data or Storage:
3,244 data requests (origin_time p50 196, p95 330.85) and 418 Storage requests
(p50 272.5, p95 753.6). These server log values are not end-to-end phone timings.
Database advisory findings were inspected, not blanket-fixed or suppressed.

- Full default Flutter suite: 208 passed, 50 existing purchase-configured skips.
- Configured purchase, family-plan and deletion-notice suite: 79 passed.
  An initial all-tests configured run hit only the test deliberately requiring
  empty/default billing IDs; it was rerun in the appropriate default suite.
- Database regression suite: 44 passed across growth, renaming, one-family
  admission and media retirement. Growth tests use the actual quota error helper.
- Real local PostgreSQL concurrency suite: 8 passed (seven scenarios plus parent).
  Covers hourly/pending/legacy caps, upload versus join in both orders and rollback.
- A widget test holds an avatar request pending while proving home family
  navigation is available. A directory test loads 1,001 members without truncation.
  A signing test proves 50 images use one signing call, instead of 50, per bucket.
- New helpers, quota utility and tests: analyzer clean. Existing large screens
  still have pre-existing warnings/deprecation/info findings; no compile errors.
- `git diff --check` and Dart formatting checks pass.

## Build Delivery

Build 1.0.0 (27) passed Apple Distribution signature/entitlement verification,
122-file source-manifest verification, unchanged billing defines, disabled
screening checks, and byte-for-byte comparison of bundled in-app images and
compiled home icons against build 25. Only seven app-source files changed from
build 26. IPA SHA-256:
`5a9079a5b2d7af12c8d837a7dd43f2169bc283cb664b3d8d23ef262de4fa9f7e`.
The existing Flutter launch-image placeholder warning remains; launch assets
were not changed. Build/signing success is not Apple processing or phone proof.

Apple subsequently confirmed Binary State Validated, Bundle Version 27,
Non-Exempt Encryption No, and Internal Beta with one tester. The existing
group assigned the build automatically after compliance; no external group
was added. Apple build ID: `27645087-7e84-47e0-9308-5ac80bcaa00a`.

At 10:53 SAST the version draft was verified with build 27 and manual release
selected after a fresh reload. Only the app was temporarily unstaged; the four
subscriptions and group remained. Add for Review restored that app to the
existing draft: six items, iOS App 1.0 / 1.0.0 (27), Subscriptions (4), Heiro
Plans. The app is Ready for Review, not submitted. The panel was closed without
clicking Submit for Review. Private reviewer credentials were not output.

## Remaining Checks

1. The owner confirmed build 27 opens, loads photos, plays voice and opens the
   tree, but rejected the jittery loading presentation. This is functional phone
   proof, not acceptance of the loading experience or measured speed. The local
   follow-up below is now delivered as build 28; device acceptance remains pending.
2. Owner store-copy/screenshot approval and remaining launch gates are separate.
   Do NOT submit for review or release without a separate request.

## Loading presentation follow-up

The owner requested an existing-logo launch, no transient empty-account screen,
quiet media placeholders and automatic saved offline memories for already
signed-in users when connectivity fails. Genuinely signed-out users retain the
sign-in screen. The owner subsequently approved build 28 and updating the
existing draft, but not public submission or release.

- The existing Heiro sign-in logo renders during initialization and for at least
  350 ms at the session gate. The same screen stays until the first vault and
  family-membership load resolves. A cached partial home no longer briefly
  replaces the startup gate before current membership is known.
- The initial reachability probe is bounded to four seconds. On a connection
  failure, signed-in users enter the read-only offline directory automatically.
  Reconnection does not interrupt that view; its Wi-Fi button retries online.
  Normal later API timeouts remain unchanged. Offline copies still expire after
  six hours and only previously viewed photos/loaded snapshots are available.
- Photos retain their allotted dimensions with neutral placeholders, including
  image decoding. The visible home feed, highlights and vault loading surfaces
  use placeholders rather than multiple independent spinners. An existing feed
  stays visible during refresh, but access denial clears it; stale overlapping
  responses cannot replace a newer feed. Active upload/purchase progress remains.
- HTTP 401/403 and database permission denials clear home cache instead of
  allowing offline fallback. A retryable token-refresh transport failure is
  treated as unavailable connectivity, not as a revoked login. Offline cache
  isolation, expiry and denied-photo protections are preserved.
- On narrow screens or large accessibility text, personal-vault Rename/Delete
  move into the action menu so they do not squeeze the name into single letters.

Verification: 211 default Flutter tests pass (50 existing configured skips),
plus all 79 configured fake-StoreKit billing tests. Phone/tablet loading renders
and a 320-point, 2x-text home were inspected. The edited app files have no analyzer
errors; existing unused/deprecated screen diagnostics remain. Evidence and logs:
`build/loading-ux-qa/`. SHA-256 comparisons confirm all 49 baseline image/iOS/
billing/lockfile entries checked against build 27 are unchanged.

## Build 28 delivery

At 12:14 SAST on 26 October, Xcode confirmed upload success for signed Heiro
1.0.0 (28), bundle `com.everroots.app`. Build 27's archive was preserved. No live
backend, real family data, prices, membership policy, icon or in-app image files
changed in this step. Package verification passed the distribution signature,
production push entitlement, disabled debugger entitlement, associated domains,
all six Apple purchase defines, and 124 source-file hashes. The three bundled
in-app images and compiled iPhone/iPad icons match their existing baselines.
Only ten app-source files changed from 27. The existing native launch-image
placeholder warning remains; the Flutter startup screen uses the existing logo.

IPA SHA-256: `d6c20e29ed8e69065436cc7d4715e1610e0a82b350878b08c1d3b136ba01a82e`.
Evidence: `build/ios/release-28-evidence/`.

Apple subsequently confirmed build 28 Validated, Non-Exempt Encryption No and
Internal Beta with one tester. The existing group assigned it automatically;
no external group or tester was added. Apple build ID:
`a5f16ee0-bdef-4233-b53d-8b2e00cddb6b`. Apple's metadata displays upload time
12:26 PM, separate from Xcode's 12:14 upload-success time.

At 12:37 SAST, the saved app version was verified after reload with build 28
and manual release selected. The app was added back to the same existing draft:
six items, iOS App 1.0 / 1.0.0 (28), Subscriptions (4), Heiro Plans. The panel
was closed without clicking Submit for Review. Status is Ready for Review,
not submitted or released. No reviewer credentials were output or changed.

The owner confirmed the requested build-28 phone checks: "Yes, it's all good."
This accepts the logo-to-account transition, stable photo placeholders and
automatic saved offline memories by user report, not by an agent device test.
They then requested a branding-only change installed directly on the phone,
explicitly without TestFlight upload. That local build 29 is documented in
`docs/heiro-branding-preview-2026-10-26.md`; Apple's draft remains build 28.
