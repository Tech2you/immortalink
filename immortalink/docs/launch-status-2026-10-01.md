# Launch recovery status - 1 October 2026

Public paid launch: **NO-GO until the gates below are verified**.
This is the current work ledger; earlier recovery notes are historical evidence.

## Latest checkpoint - 26 October 2026

- Build 32 was distribution-signed and uploaded successfully at 20:10 SAST.
  Its 126 source hashes match the locally installed build 32, including the
  branding, sign-out navigation, refresh stability and 20-photo batch changes.
  The compiled turquoise app icon, bundled artwork, production entitlements
  and six Apple purchase defines passed verification. Fresh checks: 248 tests
  passed / 50 configured skips; 68 purchase-enabled lifecycle/plan tests passed;
  static analysis of the four upload/startup components found no issues. One
  initial billing invocation incorrectly included a defaults-only test with
  purchase defines; that test passed in the default suite, and the correctly
  configured lifecycle suite passed separately. No app-source changes were
  needed. Apple now reports the binary Validated and non-exempt encryption No.
  Internal Beta is assigned with one tester. At 20:21 SAST, build 32 replaced
  build 28 in iOS version 1.0, with a reload confirming the saved selection and
  manual release. Only the app version was temporarily removed from the draft;
  the same six-item draft now contains 1.0.0 (32), four subscriptions and Heiro
  Plans. Status: Ready for Review, not submitted or released. Draft panel closed.
  The previous archive is preserved under `build/ios/release-28-evidence/`;
  new build/upload/signature/test evidence is in `build/ios/release-32-evidence/`.
  Existing launch gates, including device acceptance of batch uploads and the
  policy's responsible-party identity/address issue, remain open.
- Local build 32 adds native iPhone photo multi-selection capped at 20 per batch
  for new/existing personal and legacy memories. The remaining selection count,
  previews/removal, sequential progress and same-screen retry are implemented.
  Retries skip saved items and reconcile lost responses using stable random
  paths; they do not overwrite existing media. Videos remain single-selection.
  Existing 12 MB/photo, 100 MB pending-batch and server family quotas remain.
  No backend or billing-rule change. Tests: 248 passed / 50 configured skips;
  configured billing: 79 passed. New picker/queue/widget/test analysis is clean;
  integrated screens retain 70 pre-existing warnings/information messages and
  zero errors. Phone/tablet/large-text preview renders were inspected. Build 32
  signature, 126 source hashes, artwork and billing flags passed verification.
  In-place installation and remote launch succeeded. An independent device
  query confirms Heiro 1.0.0 (32); native gallery/upload device acceptance
  remains pending. No uninstall, account change or real media upload was done.
  TestFlight/App Store were not accessed; the last
  verified Apple candidate remains 28, not submitted. Retry state is local to
  the open upload screen, not a background or durable queue. Evidence:
  `build/ios/local-32-evidence/` and `build/photo-32-qa/`.
- Local build 31 addresses the owner's reload flicker recording: cached/live
  vaults now share one layout, refresh retains existing cards/media and scroll
  position, and renewed photo links no longer blank the same visible image.
  Account/cache clearing and denied access still remove stale content. Tests:
  225 passed / 50 configured skips; configured billing: 79 passed; phone/tablet/
  large-text refresh and render checks passed. Signature/source/artwork/billing
  verification passed. In-place iPhone installation succeeded and an independent
  query confirms 1.0.0 (31). Owner confirmed that it feels smooth; no
  measured device frame-rate claim. No backend or Apple change; last verified
  Apple candidate remains 28. See `docs/loading-stability-2026-10-26.md`.
- A reported leave-family then sign-out bug is fixed locally: tree navigation
  removed AuthGate, leaving an empty vault after sign-out. The affected routes
  now preserve or restore the auth-aware root. Local build 30 compiled and
  passed signature/source/artwork/billing verification. Full suite: 219 passed
  / 50 existing configured skips; configured billing: 79 passed. After the owner
  reconnected the phone, in-place installation succeeded and an independent
  device query confirmed 1.0.0 (30). Remote launch failed after another transport
  disconnect; the owner was asked to open Heiro manually and check sign-out/sign-in.
  Device acceptance is pending. No real account/family data, backend or Apple
  draft was changed. The last verified Apple candidate remains 28. See
  `docs/sign-out-navigation-fix-2026-10-26.md`.
- The owner accepted build 28's startup, photo placeholders and automatic offline
  behavior. At their request, a branding-only local build 29 was then installed
  in place on the connected iPhone and launched; an independent device query
  confirms 1.0.0 (29), builtByDeveloper=true. Startup now uses the unchanged
  in-app background tree. Sign-in/create-account use an app-icon-derived tree
  with HEIRO across its roots. Launcher icons and other images are unchanged.
  Tests: 219 pass / 50 existing configured skips; focused analyzer clean.
  No TestFlight upload, backend deployment, submission or release occurred.
  Apple's draft was not changed and remains at the last verified build 28;
  local branding is NOT in that draft. See
  `docs/heiro-branding-preview-2026-10-26.md`.
- Build 27 phone functionality was confirmed (opening, photos, voice, tree),
  but its jittery loading presentation was not accepted. A local follow-up now
  keeps the existing logo visible through initial account/family loading,
  automatically opens saved offline copies after a failed connection attempt
  for signed-in users, and uses quiet, stable photo/feed placeholders. It also
  preserves feed contents during refresh and distinguishes access denial from
  connectivity failure. Tests: 211 pass / 50 existing configured skips, plus
  79 configured billing checks; phone/tablet/large-text render checks pass.
  After owner approval, build 28 uploaded successfully at 12:14 SAST. Apple
  confirmed Validated, Non-Exempt Encryption No and Internal Beta (one tester).
  At 12:37 SAST, build 28 was saved and verified after reload with manual release
  selected, then restored to the existing six-item draft with the four
  subscriptions and Heiro Plans. Ready for Review, not submitted or released.
  Signature, purchase configuration, source hashes, existing turquoise icons
  and all three in-app images were verified. No backend change was made.
  Build 28 phone acceptance subsequently passed by owner report. Evidence:
  `build/ios/release-28-evidence/`; follow-up:
  `docs/family-growth-and-loading-2026-10-26.md`.
- Family growth backend is deployed after explicit owner approval. Uncapped total
  real members; 8/100/250 legacy profiles; rolling 20 invites per sender and 50
  per family per hour; existing cooldown/pending safeguards; full storage blocks
  new invites/joins/legacy profiles without removing existing access. Monthly
  invite caps are removed. One-family-per-account and billing remain
  unchanged. Batched image signing, overlapping independent loads and paginated
  directories address startup/photo delays and larger families. Full Flutter
  suite: 208 passed plus 50 configured skips; configured billing suite: 79 passed;
  DB regression: 44 passed; real PostgreSQL growth races: 8 passed. Hosted
  disposable verification passed with full rollback; existing data and policies
  are unchanged. Build 27 is uploaded, Validated, Non-Exempt Encryption No and
  assigned to Internal Beta (one tester). It replaced 26 in the saved version,
  verified after reload with manual release selected. At 10:53 SAST Apple
  confirmed the existing six-item draft includes app 1.0 / 1.0.0 (27), all four
  subscriptions and Heiro Plans. Ready for Review, not submitted or released;
  the draft panel was closed. Functional phone checks subsequently passed;
  loading presentation needs the local follow-up and a new phone check above.
  See `docs/family-growth-and-loading-2026-10-26.md`.
- Scoped security audit found and fixed client-writable AI indexes and replayable
  notifications, separately approved by the owner. Index writes are service-only;
  push claims are deduplicated and capped 20/sender and 50/family/hour. Edge v9
  is deployed. No real push, AI call or paid service was used. This is not a full
  penetration test or an unhackable guarantee. Residual warnings and exact checks
  are recorded in `docs/security-check-2026-10-26.md`. Screening stays disabled.

## Previous checkpoint - 25 October 2026

- Family-name editing: the owner explicitly approved allowing all current
  family members to rename. The app now exposes the action from the vault
  family-details sheet and tree menu, while successor controls remain
  owner-only. Migration `20261025183407_allow_family_members_to_rename`
  changes only the authorization check inside `rename_family`; membership,
  ownership, billing, Storage and the launch admission guard are unchanged.
  Full Flutter suite: 201 passed, 50 existing configured skips. Database
  regression suite: 14 passed (rename, membership access and successor).
  Focused analyzer: no errors; 45 existing warnings/info in the screen files.
  `git diff --check` passed. The owner then approved deployment, rollback-only
  verification, build 26 and replacing build 25 in the existing draft, without
  submission or release. The exact migration is now deployed; authenticated
  owner/member rename, invalid-name, outsider, cross-family, missing-identity
  and former-member checks passed in a rolled-back transaction. Existing family
  and membership counts/fingerprints, policies, other functions and security
  advisor counts are unchanged. Build 26 is uploaded, Validated, Non-Exempt
  Encryption No, and assigned to Internal Beta with one tester. The owner
  confirmed "Renaming works" on the requested build-26 iPhone check. Build 25
  does NOT contain this fix. No real family was renamed or promoted by the
  agent; the owner performed the phone rename check. Icons and in-app images
  match build 25. Build 26 is saved on app version 1.0 and verified after
  reload, with manual release selected. The app was temporarily unstaged to
  replace its build. After a temporary Safari lock interruption, the app was
  restored to that same draft. At 21:24 SAST Apple confirmed six items: app
  1.0/build 26, all four subscriptions and Heiro Plans. The app is Ready for
  Review, not submitted or released. The draft panel was closed without
  clicking Submit for Review. Store-copy/screenshot approval and other launch
  gates remain separate. See `docs/family-name-edit-2026-10-25.md`.
- Build 1.0.0 (25) delivers the owner's middle turquoise home-screen icon.
  All 15 iOS icon PNGs pass size/opacity/catalog checks; bundled in-app and
  launch-screen images are unchanged. Compared with build 24's source manifest,
  only those 15 icon files changed. Signing/configuration checks and 21 focused
  tests passed. Apple confirms processing complete, Validated, Non-Exempt
  Encryption No, and assignment to Internal Beta (one tester).
  Build 25 replaced build 23 in the saved App Store version; fresh page readback
  confirms the selection and manual release, and Apple displays the new icon.
  At that earlier checkpoint the draft contained six items: app 1.0 / 1.0.0 (25), four
  subscriptions and Heiro Plans. Ready for Review is not submission or approval.
  No Submit for Review or release action was taken. The owner confirmed build
  25's correct home-screen icon and unchanged in-app images on their phone.
  This is visual acceptance, not a new full functional or iPad test. See
  `docs/heiro-home-icon-2026-10-25.md`.
- The owner authorized deployment of the single-family launch guard and a new
  TestFlight build, with no App Store review submission. Migration
  `20261025095147_single_family_launch_guard` is deployed and verified on the
  linked backend. Existing membership/family/vault counts and fingerprints are
  unchanged; security-advisor findings are unchanged. The app removes additional
  create/join actions while retaining first-family setup and existing access.
  Full Flutter suite: 201 passed, 50 configured skips. Build 1.0.0 (24) passed
  artifact/signature/configuration checks and was uploaded successfully at
  12:05 SAST. A subsequent read-only Apple check confirms processing complete,
  Binary State Validated, Non-Exempt Encryption No, and assignment to Internal
  Beta with one tester. The owner answered "yes" to the build-24 iPhone check
  covering opening their family, tree and an existing photo/voice memory. This
  is a bounded owner-confirmed smoke pass, not full acceptance or an iPad test.
  At that earlier checkpoint the review draft still used build 23; the later
  icon/build-25 checkpoint above supersedes that selection. See
  `docs/single-family-launch-2026-10-25.md` for scope and evidence.
- Submission forms resumed. Fresh Apple inspection confirmed saved build 23,
  reviewer details, manual release and one draft submission. The privacy-policy
  URL is saved and the 14-category App Privacy label was completed and published
  with the owner's specific approval. Apple displayed its publication confirmation.
  Age rating is saved and verified: generally 13+, Australia 16+ (other regional
  and older-OS variants documented in the package). Owner rights attestation is
  received; Content Rights is saved and verified after reload. All four missing
  declarations from the 24 October validation are now completed. Private review
  notes explain the test tone and persisted after reload (2,393 characters left).
  In the next authorized continuation, selected build 23's Apple metadata
  showed Validated / App Uses Non-Exempt Encryption No. All four saved price
  schedules were checked for the five launch countries, without edits. The app
  passed Add for Review into the existing draft; Apple now shows six items
  ready to submit and app status Ready for Review. Manual release remains set.
  Submit for Review was not clicked. This clears form validation, not app review
  or the remaining owner/device checks. The owner subsequently confirmed the
  demo-password reset, saving its replacement directly in Apple, and a fresh
  phone sign-in showing Morgan Family. No credential was collected or read.
  The installed build was not reconfirmed for that login; it does not establish
  acceptance of the separately uploaded build 24.
  The owner also approved replacing only the isolated demo's macOS synthetic
  speech with an original eight-second test tone. One attachment row/new object
  is verified; the old object is removed. No real family content, code, policies,
  schema, authentication or billing changed. The app is not submitted or released.
  Exact inventory and evidence are in
  `docs/heiro-submission-package-2026-10-24.md`. The earlier demo credential
  replacement was owner-confirmed. During the later build/store read-only
  check, an automated accessibility response unexpectedly included the private
  reviewer-password field. The owner was informed; no value is reproduced in
  these files. Replace that demo password once more after metadata work and
  update Apple's field before actual submission. Later page output is filtered
  to exclude credential fields. Other final owner/device checks remain pending.
- Store review on 25 October: saved description and promotional text match this
  package; both public screenshot slots still contain the legacy and personal
  photo/voice captures. Proposed, not applied: a more direct description opening
  and photo/voice first, legacy second. The tree capture remains held for framing.
  Owner copy/image approval and comparison with build 24 remain pending; the
  basic phone smoke reply does not approve the listing. No Apple metadata,
  screenshot order, build selection or submission state changed in this review.
- Current live family allowances and localized price snapshots are recorded in
  the submission package. Free / Family / Legacy storage is 500 MB / 10 GB /
  50 GB, AI replies 20 / 500 / 1,500 per month, and transcription 10 / 120 / 400
  minutes per month. These are pooled family allowances. The live definition,
  not the older three-tier migration's transcription values, is authoritative
  for this reminder. No billing/backend/code changes were made in this check.

## Previous checkpoint - 24 October 2026

### Submission package preparation; not submitted

- Resume checkpoint at 23:07 SAST, based on owner-provided Safari evidence:
  all four subscriptions plus Heiro Plans are staged in one iOS draft (five
  items, Ready for Review). Build 23 / 1.0.0 is attached and saved to app
  version 1.0. Adding the app is blocked by Content Rights, age-rating answers,
  Privacy Policy URL and App Privacy data-practices answers. The app remains
  Prepare for Submission; nothing has been submitted or released. Owner wants
  the remaining forms filled and is considering a pause to conserve usage.
  Saved drafts persist; no automatic resume is scheduled. See the submission
  package's resume checkpoint for the exact next steps and evidence limits.
  The reviewer password field appeared in a user-shared screenshot: do not
  retain/repeat it; replacement and Apple-field update are pending before
  actual submission. No Apple forms or backend settings changed in this
  checkpoint-only turn. This supersedes unstaged-build statements below.
- Private subscription review images: the owner's two clearest genuine phone
  screenshots are uploaded to all four products (Family image for both Family
  durations, Legacy image for both Legacy durations). Verified persistence after
  reload and all four rendered thumbnails; evidence is saved as
  `docs/submission-evidence-2026-10-24/*-review-image.jpg`. Originals are unchanged
  1170 x 2532 PNGs with matching SHA-256 hashes in the asset manifest. They were
  not used as public marketing artwork. The owner reports TestFlight build 23
  and USD diagnostics, then confirmed Storefront USA. USD is expected for that
  storefront despite physical presence in South Africa; no payment-logic fix is
  indicated. This is not a new ZAF/ZAR test. Product count/Result were not supplied,
  and no failure was reported. The bounded dollar-price concern is explained.
  No prices, payments, product IDs, backend code or submission state changed.
- Review/release checkpoint: the owner asked whether Apple would explain a
  rejection and whether Supabase could be upgraded after launch. Verified
  Apple's feedback/resubmission and manual-release guidance. No authority to
  submit, release or buy hosting was inferred. Live Supabase is ACTIVE_HEALTHY
  on Free; Storage metadata totals 19 objects / 13,548,282 bytes. Free's 1 GB
  storage is not per family. Recommend deciding on Pro (currently from USD
  25/month) before public paid release, with database AND media recovery checked;
  this is operational judgment, not a required Apple vendor tier. Do not add
  larger compute speculatively or treat Apple approval as comprehensive QA.
  See the submission package for sources and the exact evidence limits.
- Uploaded the two non-tree screenshot drafts per device into Apple: iPhone
  Dynamic Island large display and iPad 13-inch. The iPhone pair persisted after
  reload and supplies the medium-display fallback. The iPad pair also persisted
  after full reload, showing 2 of 10. Screenshot evidence is saved in
  `docs/submission-evidence-2026-10-24/iphone-images-uploaded.jpg` and
  `docs/submission-evidence-2026-10-24/ipad-images-uploaded.jpg`.
  Tree images remain held locally. The requested TestFlight paywall screenshots
  have now filled all four private review slots, as recorded above.
  Store copy, image selection, declarations and final acceptance remain pending.
- Reviewer-access checkpoint: the owner approved the unused
  `linebreakers+apple-review@outlook.com` address. Created that separate ordinary
  account and only its fictional Morgan Family/sample media. The existing bare
  Linebreakers account was not changed. Login works through the API and both
  iPhone/iPad simulator UIs. Member-token checks confirm only its own vault and
  family; photo and WAV downloads match local sample bytes. No schema, policy,
  billing or paid-entitlement changes. The unique password and concise notes
  are saved in Apple's private reviewer fields and verified after reload;
  no password is in repository documents. A later user screenshot exposed the
  field; see the replacement task above. Draft/manual-release remain.
- Six genuine screenshot candidates were captured from a clean export of
  TestFlight 23 source `d66dcf4`, built for iOS 26.5 simulators, not from the dirty
  screening worktree. iPhone JPEGs are 1320 x 2868; iPad JPEGs 2064 x 2752; all
  have no alpha. The four non-tree JPEGs are now uploaded as drafts, as above.
  The tree selector overlaps
  part of its top row at initial framing: hold those captures for review. Other
  candidates need owner selection and final-build confirmation. See
  [asset provenance and remaining checks](app-store-assets-2026-10-24/README.md).
  This does not establish audible playback, multi-member/invitation/blocking,
  purchases or deletion for this new fixture, or final TestFlight acceptance.
- Owner authorized the Apple draft rename to **Heiro**, non-EU launch and manual
  release, with store-copy review and final checks before any submission.
- Name, draft subtitle and Lifestyle category saved in Apple. Manual release
  saved. Owner then approved a free download, iPhone/iPad only and exactly South
  Africa, United Kingdom, United States, Canada and Australia. Those territories
  are saved as Available on App Release; future automatic territories, Mac and
  Vision Pro are disabled. Optional subscription prices/logic are unchanged.
- Current package and owner-review copy:
  [Heiro submission package](heiro-submission-package-2026-10-24.md).
  Description, promotion, keywords, support/marketing URLs and copyright are
  saved and verified after reload. Private reviewer name/email and the
  owner-supplied phone are also saved and verified; the phone is intentionally
  excluded from repository documents and public copy.
  Version 1.0 remains Prepare for Submission. Build 23 was subsequently selected
  by the owner, as recorded above. No submission, release, deployment or legal
  acceptance occurred in this preparation pass.
- Subscription group reference/localized name **Heiro Plans**, all four Heiro
  product reference/display names, localized purchase descriptions and reviewer
  notes are saved and read back. Ireland alone was removed from each product;
  all four show exactly the five approved launch countries, with future
  automatic territories off. Product IDs, durations, price fields and backend
  billing logic were not changed. Annual products remain 1 Year Upfront; Apple
  Family Sharing was left off. A full price-schedule audit is still pending.
- The approved service-level correction is **saved and verified after reload**.
  The owner grouped the pairs; editor readback confirmed both Legacy products
  at level 1 and both Family products at level 2 before Save. A full reload then
  confirmed the persisted 1/1/2/2 grouping. Evidence is
  `docs/submission-evidence-2026-10-24/subscription-levels-saved.jpg`; earlier
  pending-editor screenshots are historical. No prices, IDs, durations or
  backend payment logic changed. This proves configuration, not StoreKit
  switching behavior on the final candidate. All four subscription review
  screenshot fields are now filled and verified. The owner subsequently staged
  the four products and group using Add for Review, as recorded above.
- Re-centering: the large local screening backlog below is historical engineering
  work, not proof of live filtering and not automatically the minimum launch
  scope. Blanket manual review of every upload is not an explicit Apple mandate.
  The remaining filtering approach is an unresolved review risk to decide and
  verify, separately from completing store metadata. Keep all staged switches off.
- The 24 October live read-only audit found agreements/banking/tax Active; the
  older updated-agreement blocker below is superseded. App privacy/declarations,
  final copy/image approval, reviewer-device rehearsal, price-schedule checks
  and final candidate acceptance remain incomplete. Do not reopen passed payment/storage
  behavior or mark every historical checkbox as a current defect.

### Automatic-review alerts and post-approval notifications connected locally; not deployed

- Continued after the owner's "proceed". Added staged migration
  `20261024170015_screening_delivery_outboxes.sql` and a default-off
  `send_screening_delivery` worker. A newly held current generation queues one
  generic operator email; first approval/automatic clearance of a new enrolled
  personal or legacy memory queues generic family pushes for eligible registered
  devices. Existing user-report alerts, sign-up email settings and family-joined
  notification handling are unchanged. No content, names or attachments enter
  these new email/push payloads.
- Dispatch uses a short-lived one-use token and service-only claim/authorization/
  completion RPCs. Immediately before sending it rechecks the generation, sharing
  intent, family, membership, deletion, restrictions, blocks, hidden-feed choice
  and device-token ownership. The old memory notification handler now routes
  enrolled sources to this outbox, preventing an old client from sending again
  after approval. Its new routing RPC must be deployed before that handler.
- Email retries keep a stable per-case idempotency key and stop before 23 hours.
  Push timeouts, malformed successes and crashed in-flight sends become uncertain,
  not blindly resent. Known failures have bounded backoff. Limits are three send
  attempts, eight leases, 1,000 active deliveries and 100 devices per initial
  notice. Provisional new global caps are 20 email attempts and 200 push attempts
  per UTC day, separate from existing user-report/sign-up limits. Omissions and
  failed/stalled/uncertain deliveries are visible in the private console.
- Scope is first-publication notification, not repeated edit/Restore announcements.
  A source edited before its initial notice is sent makes that notice stale; this
  candidate skips it rather than silently retargeting it or producing edit spam.
  New devices/family members are not backfilled. Offline pushes expire immediately.
  Provider acceptance is not proof of mailbox/device delivery. A change after the
  final database check cannot be atomically coupled to an external provider; the
  generic payload and normal app read permissions remain important safeguards.
- **Verification:** combined local database/image/worker suite **508 passed**,
  zero failures/skips; reviewer/server/browser suite **30 passed**, zero failures/
  skips. Eight new real-PostgreSQL delivery races cover issue, claim, authorization,
  completion, edit/Hide, shared daily-budget contention and invalid-token rejection
  without taking the shared media lock. An actual staged-SQL
  harness follows flag -> local pg_net stand-in -> fake email -> exact-version
  approval -> fake push. Tests also cover Restore/media retirement, duplicate
  prevention, revocation during OAuth preparation, privacy, bounded transport,
  actual local RSA signing, and unchanged existing functions/ACLs/RLS policies.
  Desktop/mobile delivery-health screenshots were inspected without overflow.
  Node syntax checks passed for both Edge entry points. Deno runtime/typechecking
  and hosted provider/gateway/scheduler verification are still outstanding.
- **Unchanged live:** no migrations/functions/secrets/schedules deployed, no real
  AI/email/push calls, no family data accessed, no payment or phone build changes.
  Every app, processing, publication and delivery switch remains off. The normal
  Finder launcher is unchanged. Flutter was not rerun because no app source was
  changed in this checkpoint. No phone action is needed yet.
- **Next:** finish pending collaborative edits, archive edits and the declined-
  permission/voice/video alternatives; operational pagination, retention, recovery
  and activation/capacity checks. Then obtain approval for a controlled hosted
  end-to-end deployment/canary, verify real alerts and pushes using disposable
  fixtures, and complete the new TestFlight and Apple submission checks. This
  checkpoint is not evidence of fully hosted screening or launch readiness.

### Automatic held-item review connected locally; not deployed

- Continued after the owner's "okay proceed". Added staged migration
  `20261024162740_content_screening_human_review.sql` and an **Automatic checks**
  section in the existing private Mac review console. This is distinct from the
  already-tested user-report/email/Hide/Restore workflow, which is preserved.
- A current flagged result or exhausted retry creates one private case for that
  exact source generation. Refreshing or withdrawing/reaccepting provider consent
  cannot reroll that held generation. Human approval never grants AI permission.
  No existing archive is scanned, copied into an evidence archive or backfilled.
- Reviewers can mark under review, keep private, reopen by reference/filter, or
  approve the exact reviewed text/photo version. Text and every direct image must
  have a recent recorded preview by that reviewer. The server acknowledges an
  image only after successful bounded retrieval and a second source check; the
  browser additionally waits for image display before enabling approval. This
  records access, not proof that a human actually inspected the image carefully.
- Edits, replaced media, scope changes and deletion invalidate the old case.
  Account deletion in progress, lost membership, existing report restrictions
  and restricted sexual-content cases prevent approval. Human approval never
  removes a report restriction, moves/deletes media or changes subscriptions.
  Closing an unavailable case cannot publish it. Historical cases hold references
  and decision logs, not copies of memory text or image bytes.
- The console capability defaults off and requires an explicit operator flag;
  `Heiro Safety Review.command` is unchanged. The app/server screening and
  publication switches remain off. No deployment, AI call, live account/media
  access, Apple setting or phone build changed. No phone action is needed yet.
- **Verification:** final combined local database/image/worker suite passed
  **453 tests**, zero failures/skips, including six real-PostgreSQL approval races
  and unchanged existing policy/function/privilege checks. Reviewer/server/browser
  regression passed **29 tests**, zero failures/skips. The browser uses the real
  staged SQL against a disposable local database with mocked Storage bytes; hold,
  reopen, preview, approve, family readback and logout passed at 1280x900 and
  390x844. Screenshots were inspected with no overlap/overflow. The split-worker
  harness now connects a mocked classifier flag through the case and exact-version
  approval. No hosted classifier/Storage/notification or real phone proof is claimed.
  Flutter was not rerun in this checkpoint; app source was not changed this turn.
  `git diff --check` is clean.
- **Still missing:** automatic-case email alerts and durable post-clear family
  notification dispatch/deduplication; collaborative pending edits, archive-edit
  and declined-permission/voice/video alternatives; complete hosted split/Storage
  proof, retention/recovery/queue pagination and final device/Apple checks.
  The normal report-alert emails remain separate and already working. Do not
  describe this checkpoint as fully hosted screening or enable it for testers.

### Local app sharing status, consent and notification guard; not deployed

- Continued after the owner's "proceed". Added staged migration
  `20261024120503_content_screening_client_status.sql`: a caller/account-bound
  status RPC and a service-only notification audience RPC. Status reveals no
  content, paths, provider responses or other contributors' identities. Refresh
  cannot enqueue work, grant permission, reset a held result or publish content.
- The default-off app candidate now connects completed personal/legacy saves and
  edits to separate permission, sharing status and an explicit retry. It separates
  saved from shared, supports decline/close, account changes, timeout recovery,
  held/paused/unsupported states and retries the same target without re-uploading.
  Normal upload and payment behavior is unchanged with the switch off.
- The local notification handler now requires the server-checked owner, family,
  current publication generation and eligible recipients before token lookup or
  Firebase dispatch. Pending, hidden and restricted content cannot use the old
  owner-readable shortcut. The app suppresses immediate notifications when its
  screening switch is enabled. Durable post-approval dispatch/deduplication is
  still missing; this guard is not a completed notification delivery workflow.
- Verification: **413 local database/image/worker tests passed**, zero failures
  or skips; **198 default Flutter tests passed**, with 50 existing purchase-config
  skips; the separately configured fake-StoreKit billing suite passed **79**
  with no skips. Focused consent/sharing tests passed **59**. New/changed focused analyzer
  scope is clean; `vault_home_screen.dart` retains 69 existing warnings/info.
  Rendered and inspected 320x568, 390x844 and 1024x768 at 200% text size with real
  fonts/icons: no overflow or overlap. The first modal run exposed a background
  spinner; it was fixed rather than weakening the timeout assertions.
  These are local SQL, widget/service, source-wiring and mock-worker checks, not
  full composer/device or hosted Firebase notification proof. Edge handler syntax
  passed Node's check; a Deno runtime/typecheck is still needed before deployment.
- **Unchanged:** all screening switches remain off. No live migrations/functions,
  AI requests, family content, payments, Apple settings or phone build changed.
  No phone action is needed. This work does not authorize deployment/submission.
- **Next:** scoped held-item review and durable post-approval notifications;
  collaborative pending edits, archive edits and voice/video alternatives;
  approved hosted split/Storage integration and operational retention/recovery
  checks. Then final TestFlight acceptance and the Apple submission gates below.

### Local exact-generation publication ceiling; still disabled and not deployed

- Continued after the owner's "proceed". Added staged migration
  `20261024114120_content_screening_publication.sql`, with an independent
  default-false `enforce_publication` switch that requires capture configuration.
  It adds restrictive read ceilings for enrolled personal/legacy memories,
  their direct attachments/chunks, the existing shared-vault media reader and
  new Storage reads. Existing owner/family/block/hide rules remain in force.
  Identified authors retain pending-source access so INSERT RETURNING, editing
  and inspection work; this is not a new permission grant to relatives.
- A successful, currently authorized worker completion approves only the current
  source generation. Edits, media-reference/byte changes and parent scope changes
  rotate that generation. Editing and reverting cannot resurrect old approval.
  Provider errors, flags, unsupported voice, missing permission and exhausted
  budgets never release pending content. The worker pause switch does not release
  pending content or unpublish already-approved unchanged content.
- Publication is distinct from provider permission: later consent withdrawal
  stops new processing, not already-approved family access. Local tests preserve
  approved Grandma text and same-byte retained images through contributor-account
  deletion, and preserve approval through exact report Hide/retirement/Restore.
  The maintenance exception requires an existing server-only manifest; arbitrary
  service writes still invalidate. Legacy deletion with unverified/different
  object fingerprints fails closed and needs operator recovery, not lost bytes.
- Private address markers protect orphaned/new uploads from folder-read fallback.
  Clients cannot overwrite enrolled media or delete/recreate its old address
  when enforcement is on; the composer already uses unique names/upsert:false.
  This is local SQL/preflight evidence, not proof of hosted Storage byte ordering
  or CDN behaviour. Existing archive objects are not scanned or backfilled.
  New media attached to an excluded archive stays uploader-only; edited-archive
  publication/decline/retry behaviour must be completed before activation.
- Integrated the 14-scenario local split-worker harness with the publication
  gate, asserting relative-visible rows before and after the mocked classifier.
  Added 37 generation, RLS, retention, immutable-address and concurrency test
  entries, including five real PostgreSQL race scenarios. Full combined local
  database/image/worker regression: **388 passed, zero failures/skips**.
  `git diff --check` is clean. Flutter/device tests were not rerun: no app code
  or build changed in this checkpoint.
  Existing policy definitions, quota/deletion routines and object metadata were
  checked unchanged apart from the explicitly added restrictive policies and
  three replaced screening/visibility helpers. No new permissive policy.
- **Unchanged:** no live migration, function, account, file, payment, Apple
  setting or phone build was changed; no family data or AI endpoint was accessed.
  Screening, the Flutter disclosure switch and publication enforcement stay off.
- **Next:** app-side consent/sharing/status/retry integration, server notification
  release checks (an owner can still read their pending memory), scoped held-item
  review, collaborative legacy edits and edited-archive/unsupported-media paths.
  Then complete approved hosted split/Storage-flow verification and operational
  retention/cost/recovery checks before seeking deployment approval. Address
  tombstones retain metadata after byte deletion; bounded retention and cleanup
  remain launch gates. No phone action is needed for this local checkpoint.

### Trusted new-sharing requests implemented locally; no deployment

- Continued after the owner's "proceed". Added the staged migration
  `20261024111907_content_screening_share_requests.sql`. It records only actual
  new personal/legacy memory INSERTs after the server's capture cutoff, with
  private origins linked to the real source row and scope. There is no backfill.
  Editing an archive's client-writable date/feed flag cannot enroll it. Pausing
  processing after capture begins still records new inserts, so they cannot
  become exempt archives when processing resumes. Initial defaults stay off.
- Added caller-only `request_content_screening(text,uuid,uuid)`: authenticated
  identity and expected account must agree; the caller must be the current
  personal owner or a current legacy contributor/editor in the family, with no
  deletion underway. Unavailable/archived/foreign targets return one generic
  code. This request never grants consent, publishes content or returns media.
  Only a valid explicit request unlocks the existing queue eligibility check.
- Replaced the staged snapshot in place (same function identity), retaining all
  source, permission, attribution, restriction, file and budget checks. Source
  generation is part of the revision. Repeat requests cannot reset a review;
  deleting a target removes its origin, job and photo tickets, not other memories
  or files. Reusing its ID cannot accept an old result. Shared legacy text still
  survives author deletion, without granting new provider permission.
- Connected the 14-scenario local split-worker test to the authenticated sharing
  request, including four-image WASM preparation and one mock classifier call.
  Added 33 eligibility/concurrency tests, including seven real-PostgreSQL races.
  The initial restricted run aborted in Node while starting the loopback test;
  the permitted local rerun passed without weakening assertions. The access
  audit now expects three staged client RPCs (two permission, one request); those
  missing from live are expected until approved deployment, not reasons to grant
  access or claim deployed readiness.
- **Verification:** final combined local database/image/worker regression run
  passed **351 tests, zero failures/skips**, including the 33 new sharing cases
  and seven real-PostgreSQL races. `git diff --check` is clean.
- **Unchanged:** no live migration/function, policy, Storage file, account,
  payment, Apple setting or phone build was changed. No family content was read
  and no AI/provider call was made. Screening and its app switch remain disabled.
  No need for a phone test at this checkpoint.
- **Next:** integrate the new request with publication/read enforcement and
  held-item review, including old-client/edited-archive handling and a usable
  decline/unsupported-media path. Complete hosted split-flow verification using
  approved disposable fixtures before activation. Voice/video safeguards,
  operational limits/retention, privacy/security, final TestFlight and Apple
  submission gates remain. This is a tested local entry boundary, not a working
  end-to-end deployed filter or authorization to submit.

### Build tools installed; bundled decoder passes local and hosted diagnostics

- Owner approved local build tools. Installed Colima 0.10.3, Docker CLI 29.9.2
  and Lima 2.2.1 using Homebrew, without upgrading unrelated packages or enabling
  a login service. Dedicated `heiro-build` profile: 2 CPUs, 2 GiB RAM, 20 GiB
  data disk plus 20 GiB root disk (sparse, not fully allocated). Only the
  disposable build directory was mounted; no home/repository credentials were
  shared into the VM. Default Docker context stayed unchanged. VM is now stopped.
- Actual bundling exposed two local issues before any deployment: importing the
  whole npm package included unused binaries (47,760,710-byte bundle), and the
  runtime's static-file system does not support `Deno.stat` for that asset.
  Preparation now copies the locked module byte-for-byte, retains license and
  notices, includes one WASM asset, and uses supported `Deno.readFile` with exact
  byte-count/SHA-256 checks. No decoder download/fallback occurs at worker start.
- Local offline bundling produces a **16,086,872-byte** bundle (4,967,409 bytes
  using local Brotli quality 6, not a measured cloud bill). Generated 2048x1536,
  4032x3024 and 6000x4000 JPEGs pass in isolated 256 MiB / 2-second workers.
  The harness uses one-shot retirement: an earlier harness accumulated workers
  and lost its largest-fixture connection; its OOM state was not recorded, so
  the exact cause remains unproven. No resource cap was increased to get a pass.
- Repeated the previously approved generated-only hosted diagnostic from 10:51:23
  to 10:51:50 UTC. Bundled static assets load successfully; all three fixtures
  returned HTTP 200 with matching local/hosted output sizes. Processing wall
  times: **373 / 703 / 438 ms**. Final observed isolate: 1,383 ms lifecycle CPU,
  56,974,150 bytes at shutdown, reason `EarlyDrop`. Shutdown usage is not peak
  memory, and processing wall time is not CPU time or total upload latency.
- Anonymous/app-key probes returned 401; authorized wrong method/empty body
  returned 405/413. Temporary function removed; runner and independent readback
  both confirm all ten existing function fingerprints unchanged. No family data,
  Storage, database records or AI endpoint was accessed by the diagnostic.
  No app function, migration, payment, policy, phone build or screening activation
  changed. Sanitized evidence: `results-bundled-2026-10-24.json` beside the canary.
- **Verification:** complete local database/image/worker regression rerun passed
  **318 tests, zero failures/skips**. Local containers removed and VM stopped.
  Build tools/cache remain installed for reuse; no paid hosting was added.
- **Next:** verify the complete split flow with database tickets, current consent,
  child/parent checks and mock dispatch on the host using approved disposable
  fixtures; then trusted new-sharing eligibility, publication/read enforcement
  and held-item review. Voice/video safeguards, operational cost/cleanup limits,
  privacy/security checks, final TestFlight acceptance and Apple gates remain.
  This closes the generated-image packaging test, not screening or public launch.

### Bundled decoder candidate tested locally; build-tool approval pending

- Continued packaging preparation only. Added a fixed-local-asset loader and
  `--bundled-wasm` mode for the isolated generated-image diagnostic. The exact
  15,425,791-byte pinned decoder is included in `static_files`, checked by size
  and SHA-256 before initialization, and initialized once per isolate. A failed
  load stays failed; there is no network fallback or per-start CDN fetch in this
  candidate. Existing hosted results used the older CDN loader, not this mode.
- The runner verifies the local asset and a running Docker-compatible engine
  before obtaining project keys. Static-file mode uses local CLI bundling, not
  `--use-api`; missing packaging metadata, altered bytes or an absent engine
  stops it. Existing generated-fixture restrictions, gateway JWT checks,
  secret handling, cleanup and existing-function fingerprints are retained.
- **Verification:** complete local database, image, worker and mocked-provider
  suite passed **318 tests, zero failures/skips**, including real-PostgreSQL
  concurrency and working storage/deletion/reporting regressions. Six new
  loader/preparation tests include actual pinned-WASM processing without a
  network loader and exact static-asset copying. Twelve fake-runner scenarios
  include bundled success, altered assets, missing engine and missing packaging.
  These do not prove deployed filesystem access, final bundle size or cold CPU.
- **No live changes:** no deployment, migration, AI call, family-media access,
  account/payment change, phone build or Apple setting change occurred. Screening
  remains disabled. No new paid hosting or local runtime was installed.
- **Pending owner answer:** requested approval to install free Colima and Docker
  command-line build tools on this Mac, using local disk/RAM only. Do not install
  until approved. Then verify the bundled candidate with the isolated generated
  diagnostic, preserving its explicit approval and cleanup requirements. Bundling
  avoids a loader CDN fetch but does not make hosting/compute/transfer free.
- **Still required:** full hosted split-flow verification and scoped deployment
  approval; trusted new-sharing eligibility, publication/read enforcement and
  held-item review; voice/video safeguards, operations and final privacy/security
  checks; TestFlight acceptance and Apple submission gates. Temporary diagnostic
  approval is not permission to deploy or activate screening. No phone action
  is needed for this checkpoint. Public paid launch remains NO-GO.

### Single-photo preparation implemented and tested locally; no live changes

- Continued the next local implementation after the owner's "proceed". Added
  `20261024092200_content_screening_photo_tickets.sql`, a single-photo worker,
  internal HTTP transport factories and aggregate-worker integration. These are
  **not deployed**. No AI request, family-media read, phone build, Apple change,
  production migration or screening activation occurred in this step.
- Chose **no durable image staging**: each child request prepares exactly one
  current, checked private object and returns a bounded JPEG directly to the
  parent. The database stores only a single-use ticket, revision, source ID,
  expiry, size and SHA-256, at most four rows per parent job. Old-lease tickets
  are replaced; deleting the parent removes its tickets. No temporary bucket,
  duplicate stored photo, Storage policy or new image-cleanup process is added.
- Photo claims reserve the whole attempt before download and recheck current
  source, consent and deletion state again after decoding. Every ticket must
  finish before aggregate dispatch. The parent verifies each response against
  the ordered database manifest, then reserves **one** classifier request for
  all text/photos. Edits, withdrawal, deletion, stale leases, missing photos and
  changed proofs cannot produce a current clear result. Ambiguous child calls
  do not retry under the same ticket; a fresh bounded parent attempt pays again.
- HTTP factories remain default-off and undeployed. They use a fixed internal
  endpoint, a separate server-worker secret, bounded streamed bodies, deadlines,
  no redirects/retries and one decode at a time per handler isolate. Deployment
  must retain gateway authentication and server-only credentials. Actual gateway
  configuration, full hosted CPU/memory behaviour and cold WASM packaging are
  still unverified; local HTTP simulation is not hosted proof.
- Expanded the existing **undeployed** outgoing-budget reservation to include
  both the binary child response and classifier base64, without raising any cap.
  Owned buffers are cleared after use, not a guarantee that every runtime copy
  is erased. Cold binary transfer/compute and total cloud cost still require a
  production decision; no "free infrastructure" or profitability claim is made.
- **Verification:** complete local database, image, worker and mocked-provider
  suite passed **308 tests, zero failures/skips**. Includes 16 ticket/database
  tests, 13 photo/HTTP unit tests, 14 end-to-end scenarios and six additional
  real-PostgreSQL races. Four native/WASM photo requests converge into one mock
  classifier request; source/permission/deletion changes, altered manifests,
  failed children and exhausted budgets fail closed. Existing policies, triggers,
  media rows and unrelated function bodies remain unchanged in migration tests;
  existing upload/deletion/retirement regressions pass. No Flutter change here.
- **Next:** resolve production WASM packaging and verify the complete split flow
  on the existing host using approved disposable fixtures before deployment or
  activation. Then implement trusted new-sharing eligibility, publication/read
  enforcement and held-item review; settle voice/video safeguards and operational
  cleanup/health. Final privacy/security checks, TestFlight acceptance and Apple
  submission gates remain. No phone action is needed for this local checkpoint.

### Hosted image bottleneck identified; single-photo diagnostics pass; screening stays off

- Continued the explicitly approved temporary generated-image experiment only.
  No family media, Storage, database records or AI endpoint was accessed by the
  diagnostic. No payment, app function, policy, migration, phone build, Apple
  setting or screening-activation change was made.
- Fixed diagnostic observability and authentication: fixed stage labels exposed
  an unexpected service-key rejection before decoding. The temporary handler now
  pins a SHA-256 fingerprint of the exact operator key in a separate header,
  retaining gateway JWT verification. Anonymous/public-app keys are rejected;
  authorized GET/empty-body controls return 405/413. No shared credential was
  rotated, logged or written to disk; only its fingerprint is in the temporary
  deployment configuration. The precise cause of the earlier key comparison
  mismatch was not established; it was not an app-user permissions change.
- **Hosted failure confirmed:** four generated 2048x1536 JPEGs with 2048-edge
  screening copies reached serialization but were terminated with HTTP 546,
  `CPUTime`, 2,064 ms lifecycle CPU. This replaces the earlier unknown-timeout
  hypothesis with direct evidence for this run, not a claim about yesterday's
  exact timeout cause.
- Changed only the local WASM screening-copy candidate to a 1024-pixel edge.
  JPEG shrink hints round up to the decoder's eighth-scale steps to preserve
  target detail. Stored originals, uploaded quality and family storage allowances
  are unchanged. Image tests cover dimensions, metadata, orientation and original
  bytes. Moderation accuracy at this resolution is not yet tested.
- **Batch result:** four 2048x1536 images passed; four 4032x3024 images still
  failed with HTTP 546 / `CPUTime`, 2,113 ms CPU. Do not deploy the current
  four-photo-in-one-invocation worker, increase spend caps to hide the failure or
  treat desktop benchmarks as hosted proof.
- **Single-photo result:** generated 2048x1536, 4032x3024 and 6000x4000 JPEGs all
  passed with HTTP 200, one image per request. Measured processing wall times
  were 741 / 594 / 1,099 ms; the last isolate reported 1,188 ms lifecycle CPU.
  These are bounded fixture results, not adversarial worst-case or all-format
  guarantees. No content was sent to a classifier. Cold WASM packaging, staging
  and extra invocation/transfer costs still need a production design.
- **Cleanup verified after every attempt:** temporary function removed; all
  ten existing functions retain IDs, versions, statuses, JWT flags and bundle
  hashes. Sanitized evidence is in
  `supabase/verification/screening_runtime_canary/results-2026-10-24.json`.
  The checked diagnostic runner is operator-only with explicit opt-in, fail-stop
  probes and cleanup/readback; fake CLI tests exercise failures without deploying.
- **Regression verification:** the complete local database, screening worker,
  photo adapter and diagnostic suite passed **258 tests, zero failures/skips**,
  including both real-PostgreSQL concurrency suites. The first sandboxed run
  aborted inside Node when starting the localhost database tests; those passed
  separately, and the complete rerun passed with local database/socket access.
  No assertion was weakened. `git diff --check` is clean. This does not replace
  final-device or real-provider validation; no Flutter code/build changed here.
- **Follow-up:** the later local checkpoint above implements split single-photo
  work without persistent staging, with source/consent/deletion binding and one
  aggregate classifier request. Full hosted verification, production packaging
  and unsupported-format recovery remain open. No new hosting is authorized or
  provisioned.
- **Then:** trusted sharing eligibility, publication/read enforcement and
  held-item review; voice/video safeguards, final privacy/operations/security,
  TestFlight acceptance and Apple submission settings. No phone action is needed
  for this diagnostic step. Public paid launch remains NO-GO.

## Previous checkpoint - 23 October 2026

### Processing budgets tested; approved hosted diagnostic timed out and was removed

- Continued locally without changing working payments, uploads, Storage policies,
  family allowances, account deletion or the TestFlight build. Screening remains
  disabled. No provider call or real family image was used.
- Found and closed a local cost-control gap: previously request budget was only
  reserved after photos were fetched/decoded. New migration
  `20261023174955_content_screening_processing_budgets.sql` reserves downloads,
  conservative outgoing payload bytes, jobs and photo decodes before returning
  source data for processing. Global UTC-day/month limits and per-initiator UTC
  hourly limits share atomic durable counters. Retries/edits do not refund them;
  same-lease rechecks do not double charge. Missing/exhausted limits fail closed.
- Provisional defaults: global 256 MiB/day and 2 GiB/month for source bytes,
  separately the same limits for outgoing payload allowance; 1,000 jobs/day,
  10,000/month; 1,000 photos/day, 5,000/month. Per initiator: 48 MiB/hour in each
  byte category, 20 attempts and 40 photos. Outgoing reservation covers worst-case
  base64/JSON for bounded outputs. These are workload caps, not a total cloud bill
  or profitability guarantee. They do not lower existing storage allowances.
- Implemented a local `magick-wasm 0.0.45` candidate, with JPEG shrink-on-load,
  metadata stripping, orientation, bounded output, no disk spill, guarded pixel
  allocations and cooperative deadlines. Container checks reject animation and
  multi-picture JPEG rather than checking one frame. Unsupported/large raster
  failures remain pending/review, not clear; a usable recovery path remains needed.
  Both candidate and native reference pass the real-local-DB/mocked-provider flow,
  including edits, permission withdrawal and deletion races.
- Generated-noise benchmark in fresh Node child processes includes holding the
  whole batch and JSON/base64 serialization: four 2048x1536 JPEGs, 562 ms CPU /
  220 MiB peak process RSS; four 4032x3024 JPEGs, 725 ms / 212 MiB; one 6000x4000
  JPEG, 482 ms / 207 MiB. This supersedes the earlier unshrunk JPEG experiment,
  but is NOT hosted CPU/memory proof or a worst-case guarantee. Large PNG/WebP
  may fail closed under the cache limit. No new hosting was added.
- Pinned/locked both local image dependencies; npm advisory audit reports zero
  known vulnerabilities at this check. Worker now requires the server's explicit
  processing reservation before downloading, so an old backend cannot silently
  omit cost controls.
- **Local verification:** the combined database, worker, adapter and diagnostic
  suite passed **247 tests, zero failures and zero skips**, including both opt-in
  real-PostgreSQL concurrency suites. No Flutter build changed in this step.
- Prepared a temporary diagnostic outside the app function directory. It requires
  the service key, expires after 30 minutes, accepts only exact generated-fixture
  hashes and returns numeric metrics. No database, Storage or AI calls in its
  code. This Mac has no Docker; diagnostic API packaging uses a fixed public,
  hash-verified WASM binary download, not a selected production loader.
- **Owner approved the temporary generated-image test.** Between 18:19 and 18:26
  UTC, deployed only `screening_runtime_canary`, with gateway JWT verification
  retained and a second exact service-key check. The first attempt hit a client
  transport error during a rejected upload. Empty-body rejection probes then
  returned **401** for both no credential and the public app key. The authorized
  2,188,411-byte generated JPEG request timed out after 90 seconds with Node fetch
  and 75 seconds with curl. Neither produced decode metrics; the larger two
  fixtures were not run. This is **failed/incomplete hosted validation**, not a
  decoder-performance pass or proof that a particular CPU/memory limit was hit.
  Available scoped logs showed boots and lifecycle shutdowns, not a successful
  image result. The failing request/body/loader stage remains unidentified.
- **Cleanup verified after every attempt:** the temporary function is absent;
  all ten existing functions retain their IDs, versions, status, JWT settings
  and bundle hashes. No screening migration, Storage policy, app function,
  subscription, family data or AI call was involved. No secret was printed or
  written to the diagnostic results. No new hosting was provisioned.
- **Next:** isolate the hosted request/body/loader timeout before another batch
  benchmark or production runtime decision; resolve production binary packaging
  and hard runtime limits. Then server-owned new-sharing eligibility,
  publication/read enforcement and held-item review. Voice/video, operations,
  final device checks and Apple submission gates remain below. No phone test or
  submission yet; screening remains disabled.

### Queue-to-provider worker proven locally; runtime/publication gates still open

- Owner requested continuation. Implemented the next local processing stage in
  `scripts/content-screening/`: closed-RPC/fixed-project Storage transport, a
  single-lease worker and a bounded Node photo-normalization reference. No
  production migration, app hook, scheduler, hosting service or paid API was
  enabled. The worker defaults off and additionally requires an explicitly
  supplied decoder. It has no CLI or automatic credential discovery.
- Extended the existing moderation adapter to accept up to four photos plus
  text in **one** multimodal request and one aggregate result. It preserves the
  previous single-photo API, rejects partial/invalid batches, bounds combined
  image bytes at 10 MiB and serialized request bytes at 15 MiB, and never loops
  four provider requests against one queue reservation. This closes the earlier
  local queue/adapter batch mismatch, not publication enforcement.
- Downloads require the current lease's exact private bucket/path, recorded
  size/MIME and strong ETag. Conditional requests, actual-length/digest checks,
  closed URL construction, redirect rejection, stream limits and deadlines fail
  closed. ETag/MD5 is a Storage coherency check, not a signature; the queue's full
  source/consent hash is rechecked before dispatch and completion. Production
  Storage header compatibility still needs approved disposable-fixture proof.
- The Node reference decodes JPEG/PNG/WebP, applies orientation, strips embedded
  metadata, rejects animated/corrupt/unsupported images, and bounds dimensions
  and pixels. Four-photo inputs are processed sequentially, with a 24 MiB total
  source limit and 2 MiB per normalized JPEG. It does not change stored originals.
  Temporary owned buffers are cleared, but this is not a guarantee of erasing
  every runtime/OS copy. Sharp `0.35.5` is pinned/locked as a local dev dependency;
  its npm advisory audit returned zero known vulnerabilities at this check.
- **Runtime finding:** Supabase explicitly does not support native Sharp in
  hosted Edge Functions. Kept it as a local reference, not a proposed deployable
  function. An isolated `magick-wasm 0.0.45` experiment used generated images only:
  a solid 1600x1200 JPEG took about 81 ms CPU and 4032x3024 about 548 ms CPU;
  6000x4000 hit a configured 96 MiB pixel-cache limit with disk spill disabled.
  These are Mac Node measurements including a separate image-generation setup,
  NOT Supabase memory/CPU proof. The documented hosted limits are 256 MB and
  2 seconds CPU per request. Validate a bounded WASM path in the target runtime
  before selecting it; do not quietly add hosting or lower published allowances.
- **Verification:** 40 focused tests passed, including five real local-database
  scenarios from queue through checked bytes, normalization, mocked provider and
  queue completion. Edits, withdrawal before dispatch, withdrawal during the
  request and deletion reject stale results. The combined database/worker/mock
  suite passed **192 tests**, with the same two opt-in concurrency parents
  skipped; their earlier **11 passing** real-PostgreSQL results are unchanged.
  No Flutter/SQL behavior changed in this step. No actual provider request or
  real family image was used; classifier effectiveness is not proven by mocks.
- **Next:** resolve and test the existing-host decoder/runtime path and global
  media-transfer/compute budgets, then server-owned new-sharing eligibility,
  publication/read enforcement and held-item review. Voice/video, privacy and
  Apple gates remain below. Do not activate screening, ask for a phone screening
  test or submit to Apple on this local worker evidence alone.

### Bounded screening queue tested locally; not deployed or connected

- Owner said "proceed". Added CLI-generated migration
  `20261023164835_content_screening_queue.sql`, a private queue and service-only
  enqueue/claim/prepare/finish RPCs. Controls start disabled with no eligibility
  cutoff. No upload hook, scheduler, network request, read policy or publication
  grant was added. The existing permission migration is still local only.
- The queue binds the actual memory, scoped attachment metadata, family scope
  and every identified legacy contributor/editor's current permission revision.
  It rechecks these before dispatch authorization and completion. Changes,
  withdrawals, deletion jobs and existing restrictions invalidate approval.
  Duplicate work and obsolete leases cannot approve a new revision. A second
  contributor cannot reset a review decision or retry limit for the same source.
- Provisional processing ceilings: 1,000 pending/review jobs globally, 20 per
  initiating account; 1,000 request reservations per UTC day globally, 20 per
  initiating account per UTC hour. Each revision gets at most three processing
  attempts, a two-minute lease and bounded retry backoff. These are separate
  from the existing report-submission limit, not monetary or profit guarantees.
  Counters persist across worker restarts and failed requests consume capacity.
- No voice/video is sent by these RPCs. Unsupported or unattributed content,
  oversized inputs and targets with sexual-content reports fail eligibility.
  These return codes are NOT yet integrated with a held-item reviewer or a
  user-facing recovery path. Existing archives are not automatically queued.
- **Verification:** the full database plus mocked-adapter run passed **166
  tests**, with the two opt-in real-PostgreSQL parents skipped. Separately enabled
  both real-PostgreSQL concurrency suites: **11 passed, no skips**, including
  screening consent/source/budget races and the existing media-retirement versus
  deletion/restore races. The queue suite contributes **38 passing tests** to
  the default run. A definition/data comparison verifies the new migration does
  not replace existing functions, policies or triggers, or alter Storage rows.
  Tests use isolated fixtures, not live accounts or real family media. Flutter
  was unchanged in this step; its previous test results remain recorded below.
- **Still missing before activation:** authenticated sharing integration and
  server-owned eligibility events; exact-revision publication/read enforcement
  across metadata, media, feed and AI paths; safe byte retrieval/decoding and
  metadata stripping; a compatible bounded batch-provider contract; held-item
  review, retry and retention operations; old-client handling and a voice/video
  approach. The queue currently allows up to four photos while the disconnected
  adapter accepts one: do not loop provider calls against one reservation or
  claim multi-photo screening is implemented. Client-writable timestamps alone
  must not decide which historical content is eligible when integration lands.
- `clear` means a locally recorded assessment of one exact revision, not public
  access. The service-only predicate rechecks the source but is not wired into
  RLS. Do not deploy/enable this as a complete filter. No provider request, live
  deployment, Apple write, phone build or payment change occurred. Preserve the
  working TestFlight 23 and the passed billing/media checks. No phone screening
  test is useful until the complete path is implemented and approved to deploy.

### Apple account rechecked after owner sign-in (read-only)

- Owner replied "done" to the sign-in request. Inspected the actual distribution
  draft, App Information, App Privacy, subscription group, TestFlight and Business
  pages in Safari. No Apple field, release setting, agreement, product, account or
  submission was changed. The findings below replace the expired-session blocker
  and the corresponding historical 13 October account observations.
- **Distribution draft:** app is still named **Ever Roots**, iOS version `1.0`,
  **Prepare for Submission**. No build is selected. The displayed iPhone 6.5-inch
  set has **0 screenshots and 0 previews**; other device sets were not inspected.
  Description, keywords, support URL, marketing URL, copyright, reviewer sign-in,
  review contact and notes are empty. Automatic release is currently selected;
  switch to manual release with approval before submission. Previews, promotional
  text and marketing URL are optional, not independent launch blockers.
- **App Information:** name and subscription display names still need the Heiro
  rename, without changing bundle/product IDs. Category is blank, content rights
  are not set up and age ratings show **Set Up Age Ratings**. Both production and
  sandbox server-notification URLs still point to the existing Supabase Apple
  notification function. This readback confirms configuration, not delivery.
- **App Privacy:** no privacy policy URL is entered and the questionnaire still
  shows **Get Started**. Complete answers against the finished implementation,
  including any consented third-party screening, rather than declaring future
  behavior as deployed. No privacy answers were published.
- **Subscriptions:** group `22339684` and all four products are **Prepare for
  Submission**. Service levels remain Legacy annual 1, Legacy monthly 2, Family
  annual 3 and Family monthly 4. Correct the catalog to group equal service tiers
  (both Legacy durations at level 1; both Family durations at level 2), with
  approval and upgrade/downgrade regression checks. This is not permission to
  alter the working entitlement code. Billing grace period is not configured;
  streamlined purchasing is On and needs a supported-path decision. Individual
  product prices, territories and review attachments were not rechecked today.
- **TestFlight:** `1.0.0 (23)` is present, **Ready to Submit**, assigned to Internal
  Beta, with one install shown. This is not a selected App Store build or Apple
  approval. Build 13 remains Testing. Today's local screening work is not in 23.
- **Business:** Free Apps Agreement is Active. Paid Apps Agreement is
  **Active (New Agreement Available)**, and the app list warns that the Account
  Holder must review/accept the updated Paid Applications Schedule before new
  app submission. Owner must review the terms; no acceptance was attempted.
  Bank and both displayed tax forms are Active. EU trader-status compliance is
  still requested; resolve it if distributing in the EU. Do not invent a trader
  declaration or publish personal contact information without owner review.
- **Next:** keep building and locally testing the bounded, revision-bound
  screening/publication flow. The Apple audit does not authorize deployment or
  submission and does not close the voice/video, privacy, operations or final
  TestFlight acceptance gates below.

### Submission work resumed; separate permission controls tested locally

- Owner requested a remaining-launch checklist followed by implementation.
  Reconciled the current source/ledger with passed device results rather than
  restarting the resolved payment investigation. The current remaining gates are
  listed below; no public submission is authorized or performed.
- Added `lib/widgets/content_screening_permission.dart` and a separately named
  settings action. The release switch is deliberately **false**: no user sees a
  new prompt and no client calls the un-deployed RPCs yet. This is not an upload
  hook or permission to publish. No chat/transcription consent, payment logic,
  storage policy, public privacy page or existing archive changed.
- The local prompt identifies OpenAI, text/photos, family personal information,
  human review, excluded archives/private drafts and separate voice/video/chat
  permissions. It supports explicit decline, withdrawal, retry, policy changes,
  duplicate-call suppression and account changes. An unconfirmed withdrawal
  explicitly warns that checks may still be enabled; it never claims success.
- Strengthened the still-un-deployed permission migration's setter to
  `set_content_screening_permission(boolean,text,uuid)`: the expected account
  must equal `auth.uid()`. A request started before a session switch cannot grant
  or withdraw the new account's permission. This check is additional to, not a
  replacement for, authenticated caller identity. Old disclosure versions can
  still withdraw, but cannot grant processing.
- Extended the staged access-audit contract to exactly the two new RPCs. The
  worker helper remains service-only; unsafe old setter overloads and accidental
  helper grants are caught by a new negative test. The earlier live audit's zero
  findings used the earlier contract. Running this new candidate contract on
  live before deployment should show these two missing RPCs; do not call that
  deployed or grant them just to silence the audit.
- **Verification:** 29 new Flutter permission tests and nine permission SQL
  tests passed. Full default Flutter suite: **168 passed, 50 configuration skips**;
  separately enabled billing/plan/deletion suite: **79 passed, no skips**. Full
  SQL plus mocked screening adapter run: **128 passed, 1 skipped** (the opt-in
  real-PostgreSQL retirement concurrency test was not rerun). These fixture tests
  are not a claim that the full screening pipeline or live migrations were tested.
- Rendered and visually inspected 320x568 and 390x844 dialogs with 2x text;
  also rendered/tested 1024x768. Fixed small-phone overflow and used a compact
  heading with scrolling disclosure and accessible actions. Focused analysis is
  clean; the wider vault screen still has its 42 pre-existing informational lints.
  `git diff --check` passed. No real OpenAI request, paid inference, phone build,
  upload, live deployment, account mutation or media operation occurred.
- **Apple audit resumed:** the first attempt was blocked by an expired login.
  After the owner signed in, the read-only audit above completed. No settings
  were saved; use the fresh 23 October findings rather than the older snapshot.

### Current submission gates

| Gate | Current status | Required next evidence |
| --- | --- | --- |
| Family purchases, expiry/replacement sponsor; ordinary photo/voice; report/preview/hide/restore | Passed in recorded user/device and scoped backend checks | Preserve these results and smoke-test the final distribution candidate; do not reopen the resolved payer bug without a new failure. |
| New shared-content filtering | Local consent/status/retry, budgets, split worker, caller-bound requests, exact-generation read ceilings, pre-dispatch notification guard and exact-version human review tested; isolated hosted JPEG diagnostics pass; everything remains off | Automatic-case alerts, durable post-approval notifications, collaborative/old-client/archive-edit and declined-permission paths; full hosted split/Storage-flow verification; explicit voice/video safeguards without paid transcription. |
| Privacy and human operations | Partly implemented | Align the deployed disclosure and Apple answers with actual processing; finalize retention/appeals, urgent escalation and reviewer cover. Do not auto-purge retained family contributions. |
| Security, resilience and costs | Unverified remaining controls | Review privileged function authorization, password protection, database AND media recovery, monitoring, and hard global/provider budgets. Catalog audit alone is not clearance. |
| Final TestFlight acceptance | Incomplete | Fresh sign-up/invite/join, legacy contribution, consent decline/withdrawal, deletion/retention and offline recovery; remaining active restore/tier-change/refund/interruption billing cases on the final candidate. |
| Apple submission | Rechecked 23 October; draft incomplete and updated paid agreement requires owner review | Heiro name/URLs/screenshots/metadata, privacy/category/content rights/age rating, reviewer access, subscription service levels and product metadata, final-build export compliance, EU status if applicable, updated agreement and manual release. Bank/tax Active; build 23 in TestFlight but not selected. Then request submission approval. |

Next implementation step: add automatic-case alerts and durable post-approval
notification dispatch to the locally connected exact-version review, app
consent/status/retry and read gates. Complete collaborative edits, archive edits and unsupported-media paths,
preserving existing archives and usable decline/recovery behavior. The split-photo
candidate avoids durable image staging; its bundled decoder passes isolated hosted
tests, not the complete hosted parent/child/DB flow. Do not deploy the old batch
worker, turn the settings switch on, present foundations as "complete screening", or ask for another
phone screening test before that end-to-end path exists.

### Owner selected free text/photo moderation; permission foundation local only

- Newest direction: "if theres no ai cost we can do that". Clarified that the
  standalone OpenAI moderation endpoint has no classifier API fee, but hosting,
  transfer and human review remain costs. Proceed locally with that route; do
  not enable paid audio transcription or treat the earlier self-hosting proposal
  as selected. Privacy requirements and audio/video gaps remain.
- Added un-deployed migration `20261023110215_content_screening_permission.sql`:
  a private RLS-protected permission table, caller-scoped getter/setter and a
  service-only revision predicate. Permission starts off and is independent of
  AI-chat consent. Acceptance must match the current disclosure; withdrawal
  works with stale disclosure versions and advances the revision. Account deletion
  removes its permission. No triggers, uploads, billing or Storage changes.
- Eight new local tests pass; combined consent/adapter suite **23 passed**.
  Full default database suite **112 passed, 1 skipped** (the separate real-PG
  concurrency suite was not rerun). Mocked adapter tests made no provider request.
- This is only a permission foundation, NOT complete screening. Next: user
  disclosure/withdrawal UI, durable bounded claim/finish queue, exact-revision
  publication/read enforcement and scoped held-item review. Before deployment,
  extend the live access-audit contract for the two new authenticated RPCs and
  verify their grants; do not silently allow all new privileged functions.
- The worker must recheck permission before sending and before publication.
  Revocation cannot recall an already-dispatched request; the predicate is not
  atomic coordination with a provider and cannot replace the future claim/finish
  design. Old-client behavior, absent consent and audio/video need explicit paths.
- No live deployment, end-user prompt, phone build, archive scan or public
  disclosure change occurred. Screening stays off. No phone test is needed yet.

### Filtering privacy/cost comparison completed; screening still off

- The owner asked for the comparison, not activation. Recorded source inspection,
  current provider constraints and explicitly hypothetical cost calculations in
  `docs/filtering-privacy-cost-comparison-2026-10-23.md`. No family content or
  production settings were accessed, no model was installed and no inference ran.
- Apple Sensitive Content Analysis cannot supply server review flags: Apple says
  its detection results must stay on-device, and users can disable it. The app
  targets iOS 15 and has no integration. Treat it as optional viewer protection.
- Source also permits video. Neither the proposed text/photo adapter nor an
  image-only replacement settles voice/video safeguards. Feed visibility is not
  itself proof of owner-only access; define the sharing boundary from access rules.
- Recommendation at that point, superseded by the owner's later choice above:
  local-only, bounded self-managed filtering
  evaluation on synthetic/rights-cleared fixtures, then a production decision
  based on measured quality, languages, resource use and privacy review. This is
  a recommendation, not deployment permission or a claim of complete coverage.
  Self-managed inference may need a separate runtime; OpenAI moderation itself
  has no classifier API charge, so cost alone does not justify self-hosting.
- External screening remains disconnected. Existing optional AI, payments,
  storage, accounts and the passed phone media check are unchanged. No new phone
  test is needed for this documentation-only checkpoint. Launch remains NO-GO.

### Read-only access preflight and current work order

- Added `supabase/verification/launch_access_audit.sql`, a SELECT-only catalog
  check, and seven negative/positive regression tests. It records the expected
  36 app-facing privileged signatures and seven private RLS helpers, rejects
  unexpected overloads/grants, and checks anonymous access, schema creation,
  fixed function search paths, table RLS, view access, private review relations
  (including column grants) and public buckets. The signature inventory is an
  access contract, not approval of every function's authorization logic.
- Ran the exact final query against live Supabase inside `BEGIN READ ONLY` /
  `ROLLBACK`: all nine checks returned zero findings. No family content was
  inspected and no production configuration, function, policy, media, payment
  or account was changed. Default SQL suite: **104 passed, 1 skipped**. The
  skipped PostgreSQL concurrency suite was not rerun in this read-only checkpoint;
  its separate passing deployment evidence remains below. `git diff --check` passed.
- Current advisors still report 36 authenticated SECURITY DEFINER functions,
  `vector` in `public` and disabled leaked-password protection. Do not revoke
  app-required functions merely to clear a warning. Individual authorization
  review, backup/recovery and provider-cost controls are not closed by this audit.
- **Filtering preflight (before the later selection above).** Cloud screening remains disabled. The local
  adapter is not a publication gate. Apple's guideline 1.2 requires a filtering
  method as well as report/block/contact flows; it does not prescribe a paid AI
  vendor. Apple's device-sensitive-media framework can be disabled by policy
  and is not text/audio coverage; the app still supports iOS 15. A device-only
  check must not be represented as complete server enforcement.
- Rechecked official OpenAI documentation: standalone text/image moderation has
  no provider API fee, does not classify audio, and must not receive known or
  suspected CSAM. Infrastructure/review still cost money. Renewed owner direction
  is needed before integrating external processing of new shared text/photos;
  separate consent, publication checks, held-item review and audio safeguards
  would still be required. No private-draft or existing-archive scan, automatic
  paid voice transcription, new provider request or disclosure publication occurred.

Current work order, not the stale tasks in older dated checkpoints:

1. Implement/test the selected text/photo filtering at actual sharing boundaries,
   including the queue, revision-bound publication/read gate, held-item review
   and defined audio/video paths. Consent controls are now local and tested, not
   active. Keep reporting and blocking; no paid moderation transcription.
2. Finish the operational retention/appeal and urgent-escalation process. Hiding
   is not deletion; no automatic purge of family memories is approved. A documented
   retention decision is needed, not an arbitrary deletion timer.
3. Complete security/operations follow-through: authorization review, password
   protection, recovery of database AND media, monitoring and hard provider limits.
4. Verify the final distribution candidate's core flows and remaining billing
   cases, then refresh Apple metadata/privacy/age rating, review access, agreements
   and business settings before requesting submission. Preserve passed device evidence.

Already-downloaded copies cannot be recalled; this is a disclosed residual limit,
not a task that can be made to pass. CDN propagation and whole-archive takedown
need explicit operational handling. Public submission remains unapproved.
Sources checked: [Supabase advisors](https://supabase.com/docs/guides/observability/advisors),
[Apple 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content),
[Apple sensitive media](https://developer.apple.com/documentation/SensitiveContentAnalysis/detecting-nudity-in-media-and-providing-intervention-options),
[OpenAI moderation](https://developers.openai.com/api/docs/guides/moderation).

### Exact-memory old-link fix deployed and disposable canary passed

- After the explanation, the owner explicitly said to proceed and take extra
  care not to break other storage features. Applied only
  `20261023101256_memory_media_retirement.sql`; the local timestamp was aligned
  with Supabase's recorded migration version. No app build, payment change,
  screening activation or real-family media operation was performed.
- Preflight refreshed Supabase docs/advisors and live schema/function definitions.
  The original quota body was verified equivalent apart from the exact approved
  move exception. Deletion claim/finalization and original review function bodies
  were preserved byte-for-byte under the private schema, with direct service
  execution revoked. Readback matched all **20 new/replaced function bodies**,
  checked service-only RPC grants, private-table RLS/no direct grants and all
  **36 new triggers**. No production deletion job was active before deployment.
- Re-ran local checks before deployment: **97 SQL passes / 1 intentional skip**;
  the separate PostgreSQL 17 concurrency suite passed three scenarios (four Node
  entries); **29 worker/CLI/server/browser/QA-runner checks passed**. These cover
  ordinary saves, photo/voice paths, legacy retention, full/expired quotas,
  retry/permission-probe rollback and deletion race orderings. Local fixture
  coverage is not a claim that every flow was repeated on a physical phone.
- Integrated live canary run `06ac3d34-c362-4024-863e-a1456d765459`, exact synthetic
  report `0bac3eca-43dc-4a22-9edb-b88b843733c8`: two server-tagged temporary accounts,
  isolated family, two personal memories and generated PNGs. Ordinary authenticated
  memory save/upload and family read succeeded. Hide denied new signing; the
  Storage API move completed and atomically rewrote the direct attachment path.
  The original warmed link remained a 200/HIT initially, then became 400/BYPASS
  after **56.16 seconds** of measured polling. Restore returned identical bytes
  at the new address while the old link remained denied. The sibling photo
  stayed readable. This is one observed CDN location, not instant global removal.
- Both QA accounts were deleted through the existing account-deletion endpoint.
  Cleanup independently returned to **6 users, 5 families, 5 vaults, 7 personal
  memories, 7 legacy memories, 14 objects, zero restrictions/deletion jobs/pending
  retirements**. Hashes of existing Storage paths/owners/metadata, personal/legacy
  memory records and photo/voice references all matched baseline. Billing function
  hashes matched and event count stayed 70. Public/Storage policy hash stayed
  `a3922afaaadd5e3592092dbfccab38ed` using this turn's full-policy serialization.
  Synthetic non-content audit/tombstone records remain intentionally.
- No new security warning category appeared. Two new RLS-with-no-policy INFO
  notices are expected for deliberately private tables. Performance warning
  counts were unchanged; one new unused-index INFO concerns the intentional
  report foreign-key index. Existing vector-schema, authenticated RPC exposure
  and leaked-password-protection warnings remain for separate launch review;
  do not represent the advisor report as entirely clean.
- Restarted the private reviewer with `Heiro Safety Review.command`. Safari
  independently showed **Private review session ready**, **Alert health checked**,
  and **No open reports**. The DB also showed no waiting lifecycle lock and no
  active deletion. No private session URL or credentials are retained here.
- Post-deployment phone smoke check: the owner replied **"Photo and recording
  both work"** after being asked to save a disposable memory with a harmless
  photo and short voice note, then reopen it. This records owner-reported
  acceptance of ordinary photo display and voice playback after the server
  change, without an app update. It does not establish live legacy/audio
  old-link retirement or every account-deletion path. This acceptance update
  made no further backend changes.
- **Boundaries / next:** exact-personal-memory integrated old-link proof passed.
  Legacy/photo/audio and deletion interaction have local regression coverage,
  not fresh live end-to-end evidence for every media type. Production-scale lock
  latency is unverified. Whole-vault/member archive links, already-downloaded
  copies, adequate filtering, retention and final Apple submission checks remain
  separate gates. No further phone reinstall or repetition of the already-passing
  report test is required for this server change.

### Earlier local implementation checkpoint (superseded by deployment above)

- Implemented local migration `20261023091212_memory_media_retirement.sql` and
  bounded `scripts/retire_report_media.mjs` worker, integrated with the private
  reviewer console and operator CLI. Hide creates durable exact-memory jobs;
  Storage moves preserve bytes/ownership/folder/extension and atomically update
  attachment references. Restore never reuses the retired address. Pending or
  held jobs remain in the queue even if the report is resolved; operator Retry
  continues them. No automatic scheduler or whole-archive relocation is claimed.
- Narrow maintenance-only quota handling preserves full/expired-family behavior.
  Transaction locking coordinates moves with existing account deletion without
  making deletion wait on an operator or a network operation. Local tests cover
  retained legacy photo/audio, ordinary save-returning, path reuse, malformed or
  shared refs, stale previews, partial/retried moves and deletion orderings.
- Verification completed: full SQL suite **97 passed / 1 skipped**. The skipped
  real-PostgreSQL case ran separately against isolated PostgreSQL 17 and passed
  all **three concurrency scenarios** (four Node entries including its parent).
  Worker, operator CLI, server, desktop/mobile Playwright and live-runner guards:
  **29 passed**. Inspected synthetic desktop/mobile screenshots; no layout overflow
  or browser errors. `git diff --check` clean. No Flutter/device build changes.
- Production reads only: expected attachment/Storage column types, five private
  unversioned media buckets, aggregate metadata keys. No real family content was
  opened, no production migration applied and no real object moved in this turn.
  Upstream Storage move source informed permission-probe/HEAD tests but does not
  establish the integrated behavior of the deployed API. The global short
  metadata transaction lock also needs live latency/lock-wait observation.
- Prepared guarded `--run-integrated` disposable QA mode to test warmed old-link
  denial, hidden new-link denial, new-address restore, byte equality, sibling
  preservation and cleanup. It has NOT run live. Its cleanup deletes only tagged
  fixtures through the normal deletion flow before reconciling a pending hide.
- **Next:** request explicit production migration plus disposable canary approval,
  deploy/read back, restart the reviewer, run the isolated canary and verify
  cleanup. The modified local console requires new RPCs: do not restart it against
  the old backend before deployment. No need to repeat phone tests yet.
- **Launch gate remains open:** existing live Hide still has the old-link gap.
  The change does not retire whole-vault/member archives, remove downloaded
  copies, implement filtering or settle retention. Payments and AI screening
  remain untouched. See `docs/media-takedown-design.md` for rollout/recovery.

### Earlier media-link experiment completed; not integrated production proof

- The owner explicitly approved a disposable live media-access test. Added
  `supabase/verification/media_link_live_qa.mjs` and its opt-in, scope, redaction
  and cleanup tests. No existing family content was read or changed; no policy,
  migration, worker, payment or phone build was deployed.
- Run `0cdc7a5e-b9ab-4212-b2f6-67f2759ab98a` created two tagged QA accounts,
  one isolated family, two personal memories and copies of one generated pixel
  image. Exact test report: `f1d2eae0-6bb6-421d-bb05-8d8d70d5b73c`.
  A harmless QA alert/audit is expected; it is not a genuine abuse report.
- **Gap reproduced live:** a hidden memory and new signed-link requests were
  denied, but the original pre-warmed signed URL still returned the exact image
  with HTTP 200 / CDN HIT. Adding `cacheNonce` still returned HIT in this run;
  it did not establish an origin-only read. The sibling image stayed available,
  and restore returned access to the exact original bytes.
- **Storage mechanism verified, not a finished moderation fix:** after restoring
  the fixture, an owner-authorized Storage move to a new path and metadata-path
  update preserved family access and image bytes. The old warmed URL returned
  HTTP 400 / BYPASS after ten five-second polling waits (about 50 seconds), having
  remained readable before then. This is one observed CDN location/window, not
  an instantaneous or global revocation guarantee. A separate administrator move
  kept `media_object_matches_scope` true on this deployed Storage version;
  do not assume that behavior on other versions without checking it.
- **Cleanup independently verified:** all fixture accounts, family, vault,
  memories, files and deletion jobs are removed. Baseline/readback match: six
  Auth users, five families, five vaults, seven memories, fourteen Storage objects
  and zero moderation restrictions. Public/Storage policy fingerprint remained
  `95084a65e45d567ee0ecc72839278df7`. Non-content synthetic review audit remains.
  Initial cleanup hit a runner bug reading an empty successful RPC response;
  fixed it, added a regression test and completed cleanup through the existing
  account-deletion endpoint. This was not an app-deletion failure.
- Tests: 22 Node tests pass across the live-test guards, reviewer console and CLI.
  The console tests require loopback permission; the initial sandbox EPERM was
  rerun successfully with that permission. No full Flutter/SQL regression or new
  device acceptance is claimed. Final runner-only assertions additionally check
  the exact updated metadata row and record actual elapsed time; these later
  assertions were not rerun live after fixture cleanup.
- **Next implementation:** durable, exact-memory address retirement coordinated
  with the existing Hide action, atomic reference changes, narrow quota handling,
  account-deletion concurrency and retry recovery. Never reuse the retired path
  on Restore. Review the constraints in `docs/media-takedown-design.md` before
  editing storage/deletion code. Approval above covers only disposable testing,
  not deploying new production logic or moving real memories. Normal Hide still
  has the old-link gap; do not mark this launch gate passed or repeat the owner's
  already-passing phone workflow tests yet.

### Earlier owner-operated acceptance

- The owner confirmed reopening resolved report
  `4a08c3fa-94ea-410a-8002-4ae28c17b268` by reference after ending and restarting
  the private reviewer session. This is owner-reported acceptance, not a new
  independent UI/backend inspection. No new report or moderation action was needed.
- Photo-memory save, report/preview, hide, restore and cross-session case reopening
  are now owner-confirmed. The owner also answered "yes" to hearing the short
  harmless reported voice note after Open audio and Play in the reviewer console.
  This establishes owner-reported audio-preview acceptance, not independent
  device/provider proof; the audio report reference and dismissal were not supplied.
- The owner answered "yes working" to the paired phone check: Ross's shared
  memories disappear from Frank's view when blocked and return when unblocked
  through Settings > Safety and blocked members. Record this as owner-confirmed
  block/unblock acceptance, not independent backend/device inspection. It does
  not establish every legacy surface, already-open/offline view, or suspension.
  Dismissal of the harmless audio QA report remains unconfirmed.
- Next engineering check: cached-media takedown. Current source still generates
  one-hour signed links in personal/shared/legacy vault screens. RecentPhoto
  removes its cached entry on 401/403/404/410 and can use cached bytes on network
  failure; those controls do not establish revocation of an already-issued link.
  No new live cached-URL test was run during this acceptance update. Preserve the
  known takedown gap pending focused verification and a scoped correction.
- Reporting/photo/audio review, exact-memory hide/restore, resolved-case reopening
  and the requested member block/unblock path are owner-confirmed. Cached-media
  takedown, retention/filtering, final-candidate and Apple submission gates remain
  open. No further repetition of these passing phone checks is needed right now.
- Earlier acceptance update was documentation only. The later disposable live
  experiment above supersedes its statement that no cached-URL test was run.

## Previous checkpoint - 22 October 2026

### Memory creation permission regression fixed and deployed

- The owner hit "You do not have permission to complete this action" while
  preserving a new personal memory with a photo. Live Postgres logs identified
  three failed inserts at 21:24 UTC against `safety_memory_read` on `memories`.
  There were zero moderation restrictions, so this was not an account suspension
  or a report-limit failure. The insert failed before the app uploaded attachments.
- Root cause: the 21 October restrictive SELECT policy called the STABLE
  `memory_visible(id)` helper, which rereads `memories`. During the app's
  `insert(...).select('id').single()` request, that helper's statement snapshot
  cannot see the newly inserted row; the RETURNING check rejects the whole insert.
  The prior tests seeded existing rows and missed this creation path.
- Added the exact failing insert-returning regression first and observed the same
  policy/42501 error locally. Migration `20261022213230_memory_insert_returning_safety`
  now evaluates the candidate row's vault visibility and exact-memory restriction
  directly. It changes only this restrictive SELECT policy; ownership/write
  grants, attachment policies, helpers, payments and screening are unchanged.
  A new helper or a broad read/write grant was not introduced.
- The owner explicitly approved live deployment and disposable rollback-only
  verification. Applied the tested policy, read it back as RESTRICTIVE SELECT
  for `authenticated`, and aligned the local migration filename to the server's
  recorded version above. No phone rebuild or installation was needed.
- All 34 focused database tests pass (12 personal-memory, eight preview, seven
  foundation safety, seven alert cases). Coverage includes insert/update returning,
  photo/voice metadata, foreign/viewer/anonymous write denial, hidden memory/vault
  denial, suspension/reinstatement and exact hide/restore with sibling preservation.
- Live `supabase/verification/memory_insert_returning_rollback_qa.sql` passed owner
  insert/update, family read, foreign/viewer write denial, exact hide/restore,
  outsider read denial and suspension. All fixtures and restrictions rolled back.
  Before/after counts matched: six Auth users, five families, five vaults, four
  memories, ten Storage objects, zero restrictions. No real account or memory
  was changed. This SQL check does not claim real Storage upload/playback proof.
- Security-advisor baseline is unchanged: 18 deny-by-default-table INFO entries,
  36 callable-definer warnings, public `vector` and disabled leaked-password
  protection. Existing [RPC review](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
  [extension schema](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public)
  and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
  gates remain, not new findings from this fix.
- Phone acceptance: the owner replied "worked" to the same-draft Preserve check
  asking whether the memory saved and its photo appeared. This is owner-confirmed
  device acceptance, not an independent device inspection. No app update was needed.
- Hide acceptance: the owner confirmed hiding the disposable photo memory and
  then confirmed it was hidden in Heiro. The supplied Safari snapshot shows
  report `4a08c3fa-94ea-410a-8002-4ae28c17b268` resolved, no open reports, and
  the exact photo still available in the restricted reviewer preview. This is
  owner-reported phone acceptance plus supplied UI evidence, not a fresh backend
  audit or independent device inspection. Unrelated-memory visibility was not
  explicitly confirmed; cached-copy revocation was not tested by this result.
- Restore acceptance: the owner confirmed the memory returned with its photo.
  A subsequent read-only live audit for the exact report confirms `hide` at
  21:41:21 UTC, `restore` at 21:51:01 UTC, status `resolved` and no current
  exact-target restriction. This completes owner-operated hide/restore acceptance
  for this disposable memory; it does not prove cache revocation or all media types.
- Retention/readback: the live review function only adds/removes a restriction;
  it does not delete memory/media or expire the restriction. Live storage usage
  sums the stored media objects without excluding hidden content. The console
  lists only open/reviewing reports, but exact-reference lookup can reopen a
  resolved case. Closing the browser or dismissing a case does not lift a hide.
- Reopening was subsequently owner-confirmed on 23 October above. Cover audio/blocking and the
  known cached-media takedown gap. Define deliberate moderation retention/deletion
  and appeal handling instead of leaving hidden files unmanaged or silently
  auto-deleting family memories. Filtering and broader Apple gates remain open.

### Exact-memory report received; alert located in Outlook Junk

- The owner reported the updated app testable through TestFlight and submitted a
  memory report. Live read-only metadata confirms reference
  `b753bf90-5318-4668-ac81-51fe59dd608c`, kind `memory`, status `open`, received
  at 11:39:21 South African time. No report narrative or family media was read.
- The alert outbox records one attempt, provider acceptance at 11:40:01 and
  provider ID `01a162fb-571d-7a7b-a4f7-a1367d741e56`. Resend's original
  `rossstrauss1` workspace shows today's matching recipient/subject as Delivered.
  Outlook then independently shows the exact report reference in
  `linebreakers@outlook.com` > Junk Email at 11:40, with the revised Mac-launcher
  instructions. The older 18 October Inbox email was not today's alert.
  The agent did not resend, move mail, change spam rules or make a report decision.
- Live function and permission checks confirm authenticated, family-authorized
  reporting; a per-account transaction lock; duplicate open/reviewing target
  deduplication; and a rolling limit of 10 new reports per hour. Direct client
  table insertion and anonymous RPC execution are denied. The enabled queue
  trigger and scheduler are healthy, with zero pending/sending/failed alerts.
- The global email budget remains 40 attempts per UTC day, including retries.
  This caps alert costs, not report intake: saved reports can wait for an email
  budget reset. These controls are not comprehensive multi-account/DDoS defense;
  operators must also check the private queue rather than rely only on email.
- The owner subsequently confirmed that the correct test memory and photo opened
  in the private console and that the harmless QA report changed to Dismissed.
  Photo-preview and dismissal acceptance are owner-confirmed, not a fresh backend
  audit readback. This completes the report/alert/photo-preview/dismissal path;
  it does not prove hide/restore, suspension, audio preview or cache revocation.
- No source/runtime/deployment change was required. Next: exact-memory
  hide/restore acceptance using only the disposable fixture, including another
  member's already-open/cached view, then address the known cached-media takedown
  limitation. Proportionate filtering, final-candidate security and Apple
  submission gates remain open. This evidence supersedes the report-receipt/email
  uncertainty below, but is not an independent phone build-version readback or
  public-launch clearance.

### Build 23 uploaded for cable-free TestFlight delivery

- The owner requested TestFlight delivery because no phone cable is available.
  No direct device installation or public App Store submission is authorized by
  this request. Payments, backend, private media and screening settings unchanged.
- Source HEAD is `d66dcf4` (`report option`), clean before the build. Rebuilt using
  `scripts/build_ios_testflight_purchases.sh --no-pub --build-number=23
  --build-name=1.0.0`, preserving the existing billing defines and product IDs.
  All ten reporting widget/service/shared-vault screen tests passed again.
- Archive: `build/ios/archive/Runner.xcarchive`. Distribution IPA:
  `build/ios/ipa/Heiro.ipa`, 33.4 MB; SHA-256
  `401009ff19b1ea572518aae7ae58dcd2970696c4eeb1b8142ebcca5183cff1af`.
  Verified Heiro `1.0.0 (23)`, bundle `com.everroots.app`, team `DNLP6MCWMN`,
  Apple Distribution signing, production push, beta reports enabled and debugger
  disabled. Do not use the older `Ever Roots.ipa` left in the output directory.
- Xcode's App Store Connect export/upload succeeded at 11:20 South African time.
  Independent App Store Connect readback progressed from Processing to Complete
  and build `1.0.0 (23)` Ready to Submit after the Missing Compliance gate cleared.
  The owner then confirmed: "sorted its testable on my phone". TestFlight
  availability is owner-confirmed; exact installed-version readback and the new
  memory-report acceptance remain unverified. Existing `Internal Beta` group has
  one tester (Ross) and automatic distribution enabled. The agent added no new
  testers/public links and did not submit an encryption answer; the gate cleared
  outside its actions. Exact declaration answers and final build/group assignment
  were not independently read back and remain part of final-candidate checks.
  The App Store Connect listing still says Ever Roots; the installed display name
  in the uploaded build is Heiro. Store metadata renaming remains outstanding.
- Flutter warns that the launch image is the default placeholder. This does not
  block the successful beta upload, but final-candidate branding needs inspection.
- Next: use TestFlight without deleting the app, verify version `1.0.0 (23)`,
  and report one disposable harmless photo memory using its
  own three-dot menu. Verify the revised alert and exact case/photo through
  `Heiro Safety Review.command`. Phone acceptance and public-launch gates remain
  open; no public submission has occurred.

## Previous checkpoint - 21 October 2026

### Personal-memory reporting deployed; phone installation deferred

- The owner's screenshots show a personal shared vault and Family Feed, not a
  legacy profile. Those surfaces had only a vault/member report, so the missing
  per-memory menu was a real source gap, not a testing error. Legacy memory cards
  already offered item reports.
- Added a report-only three-dot menu to personal-memory cards and detail dialogs
  in both the shared vault and Family Feed. The feed type badge remains in its
  metadata row to avoid crowding the header. No viewer edit/delete actions added.
- New migration `20261021102247_personal_memory_reports.sql` adds the `memory`
  report kind, verified family/author binding, same-family and multi-family
  authorization, exact current text/direct-attachment preview, and restrictive
  memory/attachment/chunk/Storage visibility plus the shared-media reader. Existing
  duplicate, rate-limit, preview-audit and checked/reversible decisions remain.
  Reporting alone does not hide content. No billing, membership or write grants
  changed; no AI or new paid service. Existing cached copies/signed URLs are NOT
  revoked by these new read restrictions and remain a separate launch gate.
- Verification: 23 database safety/preview tests pass, including eight new
  personal-memory cases; eight reporting widget/service tests and two actual
  shared-vault card/detail screen tests pass. Full default Flutter suite passed
  139 with 50 configured-billing skips; separate configured
  billing/deletion/plan tests passed 79 with no skips. The 17 reviewer/alert/operator
  tests and desktop/mobile browser preview test pass. New widget/test analysis is
  clean; the two existing large screens retain 114 warning/info notices, no errors.
- Built and signature-verified Heiro `1.0.0 (23)` at
  `build/ios/iphoneos/Runner.app`, keeping the prior Apple product configuration.
  Build 23 is NOT installed and has NOT been uploaded to TestFlight. Installation
  failed before transfer with a CoreDevice connection-reset error. The owner has
  no cable available and explicitly deferred installation until later. Do not
  retry device installation until the owner reconnects and resumes. Build 22 is
  the last independently verified phone installation, not a new current readback.
- The owner approved deployment after tests passed. The exact tested migration
  was applied to live Supabase project `vbzyvaylfdhwowdbodmk` as version
  `20261021103844`, name `personal_memory_reports` (local source filename above).
  Read-only comparison confirmed all four existing function bodies to be replaced
  matched local source before deployment. Post-deployment readback matches all
  five function bodies exactly, including the new private helper, with empty
  search paths. All four restrictive memory policies are present. Authenticated
  members can call the report RPC; anonymous users cannot; ordinary members cannot
  call the operator preview RPC. A nonexistent memory returns invisible. These are
  live structural/permission checks, not a completed live photo-report acceptance.
  No real memory/report was created, previewed, hidden, changed or deleted.
- Security advisors are unchanged from the pre-deployment baseline: 18 INFO
  entries for deny-by-default tables, 36 authenticated-callable SECURITY DEFINER
  warnings, `vector` in `public`, and leaked-password protection disabled. No new
  advisor finding was introduced; this does not resolve existing security gates.
  Follow-up references: [privileged RPC review](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
  [extension schema](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public),
  [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- Resume: when the owner has a cable, install the already-built build 23 in place,
  independently verify its installed version, and launch it. Report one disposable
  harmless photo memory from the **memory's own** three-dot menu, verify the revised
  alert email, and open the exact case/photo through `Heiro Safety Review.command`.
  Do not substitute another owner report. Phone acceptance, filtering, cache
  takedown and final Apple gates remain open. Payments remain unchanged.

## Previous checkpoint - 18 October 2026

### Report delivery and independent Mac review

- The owner submitted a member-level test report. The live console opened it,
  recorded a deliberate `dismiss` decision with a QA reason and exact reference,
  and read back `dismissed` with no open reports. No hide/suspend/delete action
  was taken. The owner confirmed the report-alert email arrived in the monitored
  inbox. This proves that member-report path, not photo/audio previews or takedown.
- Corrected the misleading general Supabase dashboard link in alert emails.
  Alert worker version 4 is ACTIVE, with deployed files independently matched to
  source. New alerts give reference-only instructions for the Mac launcher; no
  names, statements, media, session URLs or credentials are included. Sender,
  recipient, worker authentication, retry/idempotency logic and limits unchanged.
  Queue was idle before and after deployment; no alert was resent. Delivery of
  the revised wording itself remains to be confirmed on the next test report.
- Added `Heiro Safety Review.command` in the project root. The owner double-clicked
  it and confirmed the page opened; independent Safari inspection verified the
  ready session and empty queue. A normal browser reload now resumes the existing
  cookie-bound session without extending its 30-minute absolute expiry. Logout,
  invalid cookies and expired sessions still fail closed; the entry link is
  single-use. No new credentials, public access or services were introduced.
- Verification: 17 HTTP/alert/operator checks and one desktop/mobile browser
  test pass, including reload, expiry, logout and cross-origin denial. Launcher
  syntax and JavaScript syntax checks pass. Alert health reports no pending,
  sending or failed jobs, active scheduling and one provider-accepted alert
  (the owner's inbox confirmation is the delivery evidence).
- Payments, optional AI, cloud screening, phone build and family data unchanged.
  Next acceptance is a specific disposable legacy-memory report with a harmless
  image/audio attachment, revised email and restricted preview. Cached-media
  takedown, reporting gaps, filtering/costs and final Apple gates remain open.

### Restricted human review implemented

- Following the owner's "proceed", added a Mac-local, case-bound reviewer console
  and deployed operator-only preview/audit/checked-decision functions in migration
  `20261018210222_content_report_case_preview.sql`. No payment, upload, family
  membership, optional-AI or cloud-screening behavior changed. No phone build or
  Apple submission occurred.
- The console uses the existing authorized Supabase CLI connection. Admin keys
  stay server-side, previews are explicit and audited, storage references are
  stripped before browser responses, and session/CSRF/origin/Host/expiry controls
  restrict access to this Mac. No third-party media processing or new paid service.
- Legacy-memory reports show only the specific current memory and scoped direct
  attachments. Profile/member/family reports do not grant archive browsing.
  Current-content revision checks reject observed changes; this is not immutable
  evidence or a lock against every concurrent content/Storage update.
- Verified: 45 local database/HTTP/operator/alert/disabled-adapter tests plus one
  desktop/mobile browser test passed. Live rollback-only QA passed operator access,
  audit and decision plus app/anonymous denial. No real family media was previewed
  or changed. Counts remained four families, seven legacy memories, nine Storage
  objects and six Auth users; reports and new preview audit rows remain zero.
- Advisors: only new finding is intentional INFO for the private audit table's
  RLS-with-no-client-policy. Existing security findings remain unresolved.
- Next: disposable phone-to-console media/report acceptance; exact-item reporting
  where only profile-level reports exist; urgent cached-media takedown; select and
  verify proportionate filtering and spending limits; final candidate and Apple
  settings. This does not clear the public-paid launch gate. Operator instructions
  are in `docs/content-safety-launch-runbook.md`.

### Privacy and cost direction supersedes blanket cloud screening

- **Latest owner request:** proceed with launch work, but reassess whether
  screening family memories unnecessarily invades privacy and adds costs.
  Keep the new cloud adapter disconnected; do not activate routine paid voice
  transcription for moderation. Existing optional AI features remain unchanged.
- **Requirement correction:** current Apple guidelines 1.2 and 5.1 require
  content safeguards and privacy protections, not a prescribed AI vendor or
  blanket cloud scanning. Do not characterize every-upload AI screening as an
  Apple-mandated launch blocker. Reporting alone is not a substitute for filtering;
  invite-only sharing is not a verified exemption. Apple's 16 October update
  explicitly reinforces prevention/removal of nonconsensual intimate imagery.
  [Guidelines](https://developer.apple.com/app-store/review/guidelines/),
  [update](https://developer.apple.com/news/?id=vvzx6cul).
- **Revised order:** provider-independent report/block testing and restricted
  case-based human review; assess a proportionate on-device/first-party filtering
  design with evidence across text/photos/audio; settle privacy disclosure and
  operating limits before any new external processing. No replacement filtering
  implementation or Apple acceptance is claimed. Full safeguards remain a gate.
- **Verified source state:** the new screening function has no application/worker
  callers and remains disabled by default. No live settings, payments, optional
  AI processing, private media or phone build changed in this reassessment.

### Automated screening started locally

- **Owner decision:** approved the existing OpenAI integration for new shared
  text/photos and voice transcription followed by screening, with separate
  disclosure/permission and protection of profit margins. No archive rescan.
  The owner also requested a clear explanation of human review and prohibited
  content; the internal proposal is in `content-safety-launch-runbook.md`.
- **Local only:** added a disabled-by-default text/photo moderation adapter,
  fixed endpoint, bounded input/response sizes, timeouts, no automatic retries,
  fixed privacy-safe diagnostics and conservative result validation. Flags mean
  review, not deletion. It is not wired to uploads, storage or publication.
- **Verification:** 14 new mocked screening tests plus 13 existing operator,
  alert and AI-cost tests passed (27 total, no skips). Syntax and whitespace
  checks passed. No provider request was made. No claim of complete publication
  enforcement, moderation accuracy or margin protection follows from these tests.
- **Cost inspection:** live definitions confirm the existing family allowances
  and app-wide transcription backstop; these are not a monetary margin guarantee.
  New paid screening remains off until shared spending reservations, free-user
  limits and the actual margin/budget calculation are ready. Legacy five-minute
  recording allowance versus the current two-minute transcription validator must
  be reconciled before voice screening, without silently bypassing checks.
- **Still missing:** durable revision-bound queue, all database/storage/privileged
  read enforcement, separate consent and pending/review UI, bounded audio workflow,
  authenticated human media previews, urgent takedown path and end-to-end tests.
- **Unchanged:** no live writes, provider processing, archive scan, payment change,
  new phone install or Apple submission. Build 22 remains the installed checkpoint.
  Public paid launch remains NO-GO. Do not describe the local adapter as deployed
  screening or a complete safety system.

### Deleted purchaser cancellation, expiry and replacement confirmed

- **User phone result:** the user answered "yes" to the requested check that
  Frank's original family returned to Free / 500 MB and existing photos and
  voice notes still open. This is user-reported device evidence, not a new
  automated media read test.
- **Live backend at 22:00 SAST:** the original family entitlement is `plan=free`,
  `status=expired`, Sandbox, with coverage ending 17 October at 17:10:09 SAST.
  Apple's `EXPIRED` server notification arrived at 17:10:15 SAST on 17 October
  and was the latest event at this check. It follows the user's
  cancellation and the renewal-status-change notification recorded below.
- **Result:** the deleted purchaser's still-renewing test subscription could be
  managed using build 22, then expired without removing the surviving family's
  existing media. The previously moving coverage end did not advance again in
  the checked state. No manual entitlement changes or purchaser rebinding were
  used to obtain this result.
- **Replacement phone result:** the user answered "working" to the controlled
  Family monthly test-purchase check as Frank, including return to 10 GB.
- **Replacement backend at 22:13 SAST:** the original family has active Sandbox
  `everroot_family` coverage. Its billing owner is Frank/Linebreakers and remains
  a current member of that family. The latest event is `client_validation`,
  product `everroots.family.monthly`, transaction reason `PURCHASE`, received
  at 22:11:58 SAST. The recorded test coverage end is 22:16:53 SAST, not a
  production monthly-period claim or a prediction of subsequent test renewals.
- **Passed scope:** purchaser account deletion, independent Apple management,
  user cancellation, trusted expiry to Free, retained-media access and a new
  member's replacement purchase are now evidenced for this family. This closes
  the specific recovery scenario; it does not prove every billing path or the
  final TestFlight candidate. Leave payment ownership and coverage logic unchanged.
- **Next launch work:** effective filtering under the latest privacy/cost direction
  above, appropriate disclosure/permission, secure review and takedown operations, then
  remaining final-device, security/operations and Apple submission gates below.
  Do not treat the completed payment scenario as permission to submit publicly.
- **Scope:** no payment logic, backend settings or Apple account settings were
  changed by the agent. Build 22 remains the last independently verified phone
  installation, not a new TestFlight submission. Broader launch gates remain
  open and public paid launch remains NO-GO.

## Previous checkpoint - 17 October 2026

### Apple management access restored and build 22 installed

- **Account clarification:** the user identifies Ross's actual Apple purchase
  account as the owner of the renewing test subscription. Do not substitute the
  separate Linebreakers Sandbox tester or infer Apple ownership from the current
  Heiro login. After installing build 22, the user reported "I cancelled it"
  in response to the Apple-management phone check. The previously inaccessible
  cancellation path is therefore user-confirmed working for this attempt.
- **Targeted UI fix:** "Manage Apple subscriptions" is available at the bottom
  of Family plan even for a free/recreated account, a non-sponsor, missing family
  or unavailable billing status. It opens the existing Apple management route;
  Apple authorizes its purchase account independently of Heiro sponsorship.
  It does not transfer a subscription by email or bypass purchaser/family checks.
  Sponsor-only plan changes and purchase eligibility remain unchanged.
- **Deletion warning included:** the clearer warning recorded on 16 October is
  now installed. Account deletion does not claim Apple cancellation, and opening
  or closing Apple's sheet is not treated as cancellation confirmation.
- **Regression evidence before the pause:** 79 configured Flutter billing,
  family-plan and deletion tests passed with no skips. The default full suite
  passed 135 tests with 50 purchase-configuration skips; those configured paths
  were tested separately. Focused analysis retained 42 pre-existing info notices.
- **Build verified after resuming:** built plist reports Heiro `1.0.0 (22)`,
  unchanged bundle `com.everroots.app`. Code-signature verification passed using
  the Mac's signing trust settings. Signed associated domains retain both
  `applinks:heiro.app` and `applinks:everroots.org`.
- **Device evidence:** independently read build 21 before installation, installed
  build 22 in place on the paired physical iPhone 14, then read back version
  `1.0.0`, bundleVersion `22`, builtByDeveloper=true and launched it successfully.
  Transient connection failures recovered without unpairing, resetting or
  uninstalling. No app data or account was deleted by the agent.
- **Boundaries:** this is a direct developer installation, not a TestFlight
  upload or Apple submission. No backend, payment-service or Apple account
  settings were changed by the agent for this update. The user performed the
  cancellation; no subscription was cancelled or purchased by the agent.
- **Cancellation evidence:** read-only live checks at 15:23 SAST show Apple's
  `DID_CHANGE_RENEWAL_STATUS` notification received at 15:21:54 SAST for the
  original family's Sandbox Family monthly subscription. Coverage remains active
  through 17 October at 17:10:09 SAST, unchanged from the prior renewal. This
  corroborates a renewal-setting change alongside the user's cancellation
  report. The audit row does not retain a subtype or auto-renew value, so it
  does not independently prove renewal is disabled. Actual expiry remains to
  be observed; no entitlement was manually shortened or reassigned.
- **Next phone check:** after the recorded coverage end, refresh Family plan
  in Frank's original family and confirm Free / 500 MB while existing photos
  and voice notes remain accessible. Verify expiry before a replacement purchase;
  do not infer an end to billing from the recreated Ross family's separate free
  allowance. All broader launch gates below remain open; public paid launch
  is still NO-GO.

## Previous checkpoint - 16 October 2026

### Deleted purchaser renewal and clearer deletion warning

- **Phone evidence:** user confirmed the build 21 signup email arrived and the
  confirmation flow worked. Password-reset and new-domain invitation checks
  remain outstanding. The user independently deleted the original Ross account,
  then recreated an account with the same email; the agent did not delete it.
- **Read-only live check at 12:09 SAST:** Frank remains in the original family
  with active Sandbox Family monthly coverage through 16 October at 17:10:09
  SAST. The latest verified Apple event is DID_RENEW, received 15 October,
  with transaction reason RENEWAL and the matching expiry. The deleted payer's
  entitlement owner is null. This is a real test renewal, not a rolling date
  generated by the app.
- **Different families:** the recreated Ross account was created on 14 October
  and is not a member of Frank's original family. Its reported 500 MB allowance
  does not establish that the old Apple subscription ended. Reusing an email
  does not restore the deleted purchaser identity or cancel Apple billing.
- **Cancellation pending:** asked the user to inspect the original purchaser's
  Apple Sandbox subscription page, outside Heiro. They reported no cancellation
  control on the recreated account; the exact Apple page still needs a screenshot.
  Do not claim renewal is disabled, promise expiry at 17:10 if Apple renews again,
  or allow overlapping replacement purchases by manually changing entitlement.
- **Local UI change, not installed:** deletion now presents the billing warning
  before the personal-data notice/password, with no automatic keyboard opening.
  A read-only, purchaser-scoped check across accessible families highlights paid
  Apple coverage. Missing/failed checks retain the generic billing warning;
  neither a failed check nor closing Apple's screen claims cancellation.
  The prominent cancellation button opens the existing Apple management sheet;
  the copy explains later cancellation in iPhone Settings using the paying Apple
  Account. Immediate password-confirmed deletion remains available.
- **Verification:** 73 configured Flutter billing/deletion tests passed with no
  skips, including the real deletion dialog at 320 px / double text size,
  active coverage, unavailable status and immediate deletion without opening
  Apple. The existing broad screen analysis has 42 pre-existing info notices.
  Payment service, Apple notifications, server deletion, entitlements and live
  settings were not changed. Build 21 is still the last confirmed phone install.
- **Next:** obtain Apple's cancellation/expiry confirmation, then verify the
  original family returns to Free and Frank can sponsor with his own Apple
  purchase account. Install the warning with the next phone build. All broader
  launch gates below remain open.

## Previous checkpoint - 14 October 2026

### Heiro domain-update phone build installed - 14 October 2026

- **User request:** connected the iPhone and authorized proceeding with the
  updated app installation and signup/invitation checks.
- **Built and verified:** release-mode Heiro `1.0.0 (21)`, 37.7 MB, using the
  existing Apple purchase defines, four product IDs and subscription group.
  The built plist confirms Heiro and unchanged bundle `com.everroots.app`.
  macOS code-signature verification passed. Signed entitlements include both
  `applinks:heiro.app` and `applinks:everroots.org`.
- **Device evidence:** CoreDevice confirmed build 20 before installation,
  installed build 21 in place on the paired physical iPhone 14, independently
  reported installed version `1.0.0 (21)`, and successfully launched the app.
  A transient CoreDevice connection reset recovered without unpairing, device
  reset or uninstall. No app-data or account deletion was performed.
- **Regression evidence:** full default Flutter suite passed 122 tests with
  50 purchase-configuration skips. A separate run of the subscription service
  and family-plan UI suites with the existing purchase configuration passed
  all 62 tests, with no skips. `git diff --check` passed. No payment logic or
  backend settings were changed for this installation.
- **Human checks pending:** asked the user to create a temporary account using
  another email they control and confirm delivery of the Heiro signup email.
  Confirmation-link return, password reset, and new-domain family invitation
  acceptance on this exact build still need device evidence. Do not count a
  successful app launch as proof of those workflows.
- **Delivery boundary:** this is a direct developer installation, not a
  TestFlight upload or Apple submission. Broader launch gates remain open.

### Heiro domain and email migration live - 14 October 2026

- **Authorization:** user approved renewing the existing Firebase CLI access,
  publishing Resend verification DNS, and separate domain-restricted sending-only
  keys for Supabase Auth and safety alerts. User restored the Supabase login.
  No paid hosting or mailbox add-on was purchased; existing Firebase/Resend
  services are reused. The pending-access notes below are historical.
- **Website live:** `https://heiro.app` now serves the existing family-invite
  site from `immortal-ink-ba580-invites`, with Heiro branding and privacy/support
  links. Root A is `199.36.158.100`; root TXT is
  `hosting-site=immortal-ink-ba580-invites`. Valid TLS and HTTP 200 confirmed.
  This is the small public/invitation site, not the separate Flutter web app.
  `everroots.org` remains attached and its legacy links are retained.
- **Public policy:** `https://heiro.app/privacy.html` is live. The hosting
  predeploy script derives it and its external stylesheet from `web/privacy.html`
  without relaxing CSP. Browser checks verified the home page, invitation page,
  policy link and unchanged native invitation callback. The AASA document retains
  `DNLP6MCWMN.com.everroots.app` and the established invite paths.
- **Email domain verified:** Resend confirmed `auth.heiro.app` ready to send
  after its DKIM TXT and two provider-supplied CNAME records were published.
  Receiving is disabled. Created separate sending-only keys restricted to this
  domain for Auth and safety alerts. Existing Ever Roots domain/keys were retained
  for rollback; no secrets are stored in source control.
- **Auth live:** Supabase SMTP now uses `no-reply@auth.heiro.app`, sender name
  Heiro and the new Auth key, retaining `smtp.resend.com:587`, username `resend`
  and the existing rate settings. Signup confirmation and password-reset subjects
  and bodies use Heiro, preserving `{{ .ConfirmationURL }}`. Auth Site URL,
  redirect allowlist and the `com.everroots.app` callback scheme are unchanged.
- **Delivery evidence:** an actual Supabase password-reset request returned
  HTTP 200 and Resend showed `Reset your Heiro password` delivered to the
  operator inbox. No reset link was followed and no password was changed.
  A benign safety-sender setup test was also delivered. A fresh signup and
  confirmation-link return to the phone still need an end-to-end check.
- **Safety worker live:** deployed `send_content_report_alert` with
  `Heiro Safety <safety@auth.heiro.app>`, Heiro subject, and server-side secret
  `HEIRO_REPORT_ALERT_RESEND_API_KEY`. Old alert secret remains available for
  rollback. Worker tests passed 5/5. Live health reported enabled alerts, active
  scheduler, no failed/pending/sending jobs and no attention flag. The new direct
  provider-send test does not replace a fresh queued-report delivery test.
- **App source (subsequently installed in build 21 above):** newly generated invites use `heiro.app`;
  parsing accepts both owned domains and iOS associated domains retain both.
  App privacy links target the new public policy. The nine focused Flutter
  invite/legal-link tests passed; focused analysis, entitlement plist validation
  and `git diff --check` passed. Build 20 preceded this migration; build 21 now
  includes it, with functional phone checks still pending.
- **Unchanged:** payment logic, purchaser binding, bundle ID, Apple product IDs,
  family entitlements, Auth callback scheme and existing support inbox. No Apple
  metadata update, TestFlight upload or App Review submission was performed.
- **Next launch gates:** phone signup/reset/invite checks on build 21;
  automated screening and secure human media review; remaining security/operations
  checks; final-candidate regression; Apple name/product metadata, privacy/age
  ratings, subscription levels, reviewer access and distribution/business gates
  recorded below. Domain migration alone does not make the public paid launch GO.

## Previous checkpoint - 13 October 2026

### Heiro domain purchased; connection pending - 13 October 2026

- **User decision:** register `heiro.app` at Porkbun, then connect the existing
  website and sign-up emails. Leave payment logic unchanged. This supersedes
  the earlier domain-decision-pending note below.
- **Verified checkout:** Safari's Porkbun cart contains only `heiro.app`, one
  year, total USD 8.75, estimated annual renewal USD 14.93. Paid web and email
  hosting are not selected or needed for the existing hosting/Resend setup.
  Prices can change; USD conversion, taxes and card charges are separate from
  the user's ZAR 500 annual budget. No purchase has been completed by the agent.
- **Registration confirmed:** the user completed checkout. Safari showed the
  successful registration, then the authenticated Porkbun domain list showed
  `heiro.app`, expiry `2027-10-13`. The current DNS contains only the registrar's
  parking records: root ALIAS and wildcard CNAME to `pixie.porkbun.com`, TTL 600.
  No hosting or email add-on was selected by the agent.
- **Live hosting inventory:** `everroots.org` resolves to Firebase
  `199.36.158.100`, with TXT `hosting-site=immortal-ink-ba580-invites`.
  Its current root serves the small Ever Roots family-invite page, not a
  marketing site. `immortal-ink-ba580.web.app` serves the existing Flutter web
  app. The unrelated `everroots.app` browser tab is not this project's site
  and must not be copied or treated as owned content.
- **Access blocker:** Firebase CLI reported expired credentials. The Google
  reauthorization screen requests broad existing Firebase/Google Cloud CLI
  access; automatic safety review blocked approval. User confirmation was
  requested before proceeding. The Firebase console also failed to load
  custom domains, and no new hosting-domain mapping has been saved.
- **Email preparation:** Resend still shows `auth.everroots.org` verified.
  Added `auth.heiro.app` as a second, unverified domain in the existing account
  (domain ID `3290dfdd-2e81-4785-842c-ba5280289e88`, Ireland region). Resend
  supplied a DKIM TXT at `resend._domainkey.auth`, CNAME `rsend.auth` to
  `rsend-euw1.forge.rmta.net`, and CNAME `send.auth` to `send.forge.rmta.net`.
  Read the current DKIM value from Resend before publishing. No DNS records
  or sending keys have been created. Requested approval to verify this new
  sending identity and create separate domain-restricted sending-only keys
  for Auth and safety alerts. Receiving remains disabled.
- **Migration order:** inventory live hosting and sender settings; connect the
  owned domain and HTTPS; verify `auth.heiro.app` with Resend using its supplied
  DNS records; update authorized sending credentials, Supabase Auth sender and
  templates, report-alert sender, web redirects and invitation/public links;
  verify confirmation, password reset, invite and report-email delivery.
- **Compatibility boundary:** keep `everroots.org`, its current DNS and working
  email routes while legacy links depend on them. The user reports disabling
  old-domain auto-renew; its expiry has not been verified. Preserve the app's
  bundle ID, native callback scheme, product IDs and all billing logic. No DNS,
  production Auth, sender, public site or payment change has been made here.

### Heiro phone preview delivered - 13 October 2026

- **User request:** show the current Heiro app on the connected iPhone before
  buying a domain. No domain, Apple metadata or submission change was requested.
- **Built and installed:** release-mode `1.0.0 (20)` with the existing Apple
  purchase defines, product IDs and subscription group. The built plist confirms
  display name Heiro and unchanged bundle `com.everroots.app`; the Heiro sign-in
  PNG is present in the packaged Flutter assets. macOS code-signature validation
  passed outside the tool sandbox.
- **Independent device evidence:** CoreDevice installed the app in place on the
  physical iPhone 14, launched `com.everroots.app` successfully, and then reported
  installed name Heiro, version `1.0.0`, bundle version `20`. No uninstall or
  account/data deletion was performed. User visual and functional review of this
  exact build remains pending; a successful launch alone is not a smoke-test pass.
- **Delivery boundary:** this direct development install includes the local
  Heiro branding and report/block UI. It supersedes the earlier local-only delivery
  notes below, but it is not a TestFlight upload or App Review submission. Apple
  subscription display names and public branding are unchanged. No backend
  deployment, purchase, cancellation, restore or entitlement write was performed.
- **Readiness:** this is the latest preview, not the final submission candidate.
  Automated screening, remaining privacy/operations checks, final-candidate
  regression and the Apple submission gates below remain open.

### Heiro rename and live Apple audit - 13 October 2026

- **Name confirmed:** user chose **Heiro**, exact spelling H-e-i-r-o, before
  submission. This supersedes "name not chosen"; it does not establish trademark
  clearance, domain ownership or Apple's acceptance of the title. Earlier
  screening remains preliminary. A fresh limited exact-name web search did not
  establish clearance. Do not confuse this spelling with Hero or Heirlo.
- **Domain decision pending:** user confirmed on 13 October that no Heiro domain
  has been purchased. A fresh read-only request to the official `.app` registry
  returned HTTP 404 with RDAP `errorCode: 404`, title `Not Found` and description
  `heiro.app not found`. This establishes no registration record at lookup time,
  not registrar availability, reserved/premium status, price or legal clearance.
  Source: https://pubapi.registry.google/rdap/domain/heiro.app . No domain was
  purchased or reserved and no DNS, Auth redirects, sender or invite URL changed.
  Keep the existing owned domain working while other launch work proceeds.
- **Local display-name update:** Flutter title, plan labels, sign-in/reset/invite
  wording, consent wording, iOS name/permission prompts, Android label and web/
  privacy source now use Heiro. Historical server quota messages normalize to
  Heiro without changing error codes. The sign-in artwork is now
  `assets/images/sign_in_logo_heiro.png`; the original artwork is retained.
  The existing wordless iOS app icon is unchanged. The artwork was edited with
  the built-in image tool: replace only EVER ROOTS with HEIRO, preserving the
  tree composition and transparency; no new logo concept was requested.
- **Identity and delivery boundaries:** preserve `com.everroots.app`, Apple app
  ID `6802720270`, all four `everroots.*` product IDs, subscription group
  `22339684`, plan keys, URL scheme, owned `everroots.org` links and existing
  SMTP/report-alert settings. No backend change, public-site publish, email/domain
  migration, new app install or TestFlight upload accompanied this rename.
  Apple still shows Ever Roots. Store display names, screenshots, public pages
  and provider-facing branding require a coordinated follow-up, not a global
  identifier replacement. Do not switch links to an unowned Heiro domain.
- **Apple access restored:** user signed into Safari. The audit below was
  read-only. No Apple settings, product ordering, agreements, privacy answers,
  banking/tax details or submission state were changed. The availability dialog
  was inspected and cancelled without changing any country selections.
- **TestFlight:** newest listed build is `1.0.0 (13)`, Testing, in Internal Beta
  and Genesis. Builds 18/19 were not listed. Cable-installed builds and local
  safety/name changes are not delivered TestFlight evidence.
- **Submission draft:** iOS version `1.0` is Prepare for Submission with no build
  selected. Description, keywords, Support URL, copyright, reviewer credentials,
  reviewer contact and review notes are empty. Automatic release is selected;
  change to manual release before an authorized submission. Final screenshots/
  Asset Library and export-compliance answers still need explicit verification.
- **App information/privacy:** primary category, content-rights information and
  age ratings are incomplete. App Privacy shows Get Started and has no privacy
  policy URL. The questionnaire must match the final implemented processing,
  including the screening work that remains unfinished below.
- **Subscriptions:** all four products and the group are Prepare for Submission.
  Current ranks are Legacy annual 1, Legacy monthly 2, Family annual 3, Family
  monthly 4. Proposed correction: both Legacy durations at level 1, both Family
  durations at level 2. Rank is service level, not billing period; mismatched
  levels change Apple's upgrade/downgrade timing. This correction has NOT been
  saved. Retest tier changes on the final candidate after it is applied.
  [Apple subscription-level guidance](https://developer.apple.com/app-store/subscriptions/).
- **Sampled product details:** Family monthly is available in Australia, Canada,
  Ireland, South Africa, United Kingdom and United States. Apple Family Sharing
  is off, distinct from the app's shared family entitlement; leave it unchanged.
  Its reviewer notes still say a family owner purchases, which must become an
  eligible family member/purchaser explanation. Review screenshot upload shows
  no file selected; verify final review artwork for every product. Other
  products' individual regions/prices/review metadata were not audited here.
  Streamlined Purchasing is on and Billing Grace Period is not configured;
  assess relevant external-purchase paths, but neither observation alone proves
  a blocker or authorizes a setting change.
- **Business:** Free and Paid Apps Agreements, the bank account and both listed
  tax forms show Active. EU DSA trader compliance still has a completion warning;
  resolve it if Ireland/EU distribution is retained. No private bank/account
  details are copied into this ledger. App-level country availability remains
  a separate unverified setting, not inferred from a subscription's countries.
- **Name and public-release risk:** search/store acceptance is not legal
  clearance. Follow the brand/country risk review already recorded in the
  submission checklist. No new domain was bought or trademark filing made.
- **Rename verification:** after wiring the new artwork, the full default
  Flutter suite passed 122 tests with 50 purchase-configuration skips. A separate
  run with the existing group/product IDs enabled passed all 62 billing/plan UI
  tests with no skips. Added assertions for the Heiro title/artwork, plan labels,
  unchanged purchase IDs and invite links, and historical error-name mapping.
  Focused Dart analysis found no issues; the iOS plist and web JSON manifest
  parsed successfully, the new PNG retains alpha at 1254 x 1254, and
  `git diff --check` passed. These are local checks, not final-device evidence.

### Confirmed payment checkpoint

- **Phone results:** on 12 October the user confirmed Frank's shared-plan access
  and Ross's cancellation with coverage retained until expiry. On 13 October the
  user confirmed that storage returned to 500 MB, then a purchase as Frank
  succeeded. The expired-purchaser recovery and replacement-sponsor scenario
  are now passed for this device test, not merely inferred from unit tests.
- **Live backend readback:** effective and stored plan `everroot_family`, status
  active, environment sandbox, product `everroots.family.monthly`, billing owner
  Linebreakers/Frank, and both Frank and Ross members of the same family. Paid end
  at this readback: 13 October 2026 11:53:20 Africa/Johannesburg, still in the future
  when queried. No ownership, quota or expiry records were manually changed.
- **Checkpoint confirmed by the user:** Ross sees the shared 10 GB after Frank's
  replacement purchase, and existing photos and voice notes still work. The
  purchase -> shared benefit -> cancellation -> expiry to 500 MB -> replacement
  sponsor -> retained-media scenario is passed. Preserve this billing behavior.
- **Remaining evidence:** this scenario does not separately establish active
  restore, refund, interrupted/offline recovery,
  exact currency, or the installed TestFlight build number. Do not reopen the
  resolved expired-history bug without a new failure. Final-candidate regression
  and the other submission gates below remain outstanding.
- The payment checkpoint above records user device results and a read-only live
  entitlement check. No purchase, cancellation or billing change was performed by
  the agent. Subsequent safety deployments are recorded separately below.
- **Next work authorized:** user requested saving this checkpoint and proceeding
  with the remaining launch blockers. Begin with reporting, blocking and moderation;
  preserve existing dirty-worktree changes and keep final TestFlight, operations
  and Apple submission checks separate from this completed payment scenario.

### Content safety checkpoint - 13 October 2026

- **User decisions:** Ross will monitor `linebreakers@outlook.com` daily and handle
  urgent reports promptly. Automated screening with clear privacy disclosure and
  human review is the chosen launch approach. Shared legacy contributions must
  survive a contributor's account deletion; a report must not automatically delete
  family memories.
- **Deployed:** `20261013104043_family_content_safety` adds scoped private reports,
  mutual member blocks, immutable contribution attribution, restrictive content/
  media reads, publication restrictions and audited operator review actions.
  App clients cannot moderate reports or read another reporter's narrative.
  This is the report/block/review foundation, not automated screening.
- **Deletion regression found and fixed:** live disposable QA exposed an existing
  media guard rejecting Auth's attribution-FK cleanup without a user JWT.
  `20261013122650_safety_attribution_deletion_cleanup` allows only attribution
  fields becoming NULL after the referenced Auth user is gone, with every other
  column unchanged. Ordinary media/path/family edits retain their checks. Live
  function readback matched; no deletion worker change was needed.
- **Live disposable QA passed:** run `acbbfbd3-8616-4f0c-bc41-e0ea6cb24d69`
  exercised scoped access, forged references, report privacy/idempotency, blocks,
  hide/restore, suspension/reinstatement and account deletion. Both contributors'
  Grandma content survived the first deletion; the survivor could contribute;
  last-member cleanup passed. All fixture accounts, deletion jobs and safety
  records were removed. Independent final counts returned to the baseline of
  three families, 15 storage objects and six Auth users. Ross and Frank were not
  deleted or used for destructive QA.
- **Implemented locally, not delivered:** report actions in personal/legacy
  vaults, Safety settings for member blocking, cache invalidation and stale-feed
  guards. The operator CLI and its runbook are at
  `scripts/review_content_reports.mjs` and
  `docs/content-safety-launch-runbook.md`. Its live read-only queue returned no
  open reports. No new phone build, TestFlight upload or App Review submission
  was performed during this safety work.
- **Verification:** all 53 database tests passed; full default Flutter suite
  121 passed / 50 purchase-configuration skips, separately enabled focused billing
  tests 62 passed / no skips, safety widget tests six passed, operator CLI tests
  four passed. The new safety files' analyzer scope is clean; integrated screens
  retain pre-existing lint findings. Security advisors had no ERROR findings but
  still require review of 36 authenticated security-definer warnings, the public
  vector extension and disabled leaked-password protection. Private deny-client
  tables intentionally have no client policies.
- **Important media limitation:** live testing observed a previously warmed
  authenticated media URL returning a CDN cache HIT after a block. New signed-URL
  creation and uncached origin requests were denied. Local cache clearing does
  not recall previously downloaded, cached or signed copies. Urgent takedown and
  cache/purge handling remain operational work; do not claim immediate universal
  revocation.
- **Resend correction:** the existing sign-up provider is Resend, as reported by
  the user and already recorded in earlier launch notes. Absence of a Resend Edge
  Function secret did not establish absence of Supabase Auth SMTP. The previous
  "no email service" statement was incorrect. Preserve working sign-up SMTP,
  templates and credentials. The signed-in dashboard now confirms verified
  `auth.everroots.org` and the existing sending-only Supabase Auth SMTP key.
  That SMTP key, templates and settings were not changed.
- **Report alerts deployed and delivered:** with explicit user approval, created
  the separate sending-only, domain-restricted `Ever Roots report alerts` Resend
  key and stored it only as `REPORT_ALERT_RESEND_API_KEY` in Supabase Edge secrets.
  `send_content_report_alert` sends fixed-recipient, report-reference-only email
  from `safety@auth.everroots.org` to `linebreakers@outlook.com`. No report narrative,
  family identifiers or media are included. The temporary credential file was
  removed and the credential was not printed or committed.
- **Queue and scheduler:** migrations `20261013142233_content_report_alerts`,
  `20261013142620_content_report_alert_schedule`,
  `20261013144031_single_use_report_alert_dispatch` and
  `20261013145108_report_alert_operator_health` are deployed. The private outbox
  has leases, idempotent payloads, five-attempt/23-hour retry bounds and a 40-attempt
  UTC daily budget. Cron checks for due work each minute. Authenticated/anonymous
  clients cannot read jobs or call the claim, finish or health RPCs.
- **Scheduler credential correction:** the intervening
  `20261013143503_restrict_report_scheduler_access` migration could not revoke
  platform-owned `pg_net` queue grants. No such revocation is claimed. The final
  design queues only a one-use, 90-second authorization tied to one report;
  reusable credentials and service/provider keys are never queued. The original
  generated Vault token was retired and its absence verified. Keep `net` outside
  Data API exposed schemas; see the runbook for the platform limitation.
- **Live alert QA:** a disposable report produced provider message
  `01a135ad-50ef-7849-b83b-ca49ba122e1c`; Resend showed Delivered. Replaying the same
  report through the actual cron path returned that same provider ID and did not
  create a second email. The one-use authorization was consumed. QA rows were
  removed; final baseline remained three families, 15 storage objects and six
  Auth users, with zero report-alert/invocation fixtures. No family content or
  purchase records were changed. `sent` in the outbox means provider acceptance;
  delivery was separately verified in Resend, not inferred from that state.
- **Latest tests:** 60 database tests, five alert-worker tests and five operator
  CLI tests passed (70 total). The operator `health` command reports failures,
  stalled scheduling and exhausted budget without exposing report content.
  Live CLI readback confirmed enabled/active, `needs_attention=false`, no open,
  pending or failed reports and two QA sending attempts. Anonymous/authenticated
  access to the health RPC was denied by grants. Fresh security advisors remain
  at 36 authenticated security-definer warnings, one public vector warning and
  one leaked-password-protection warning, with no ERROR findings; this is not a
  complete security audit.
  Existing Flutter results above were not rerun for this server-only alert work.
  A connected-device inventory attempt failed with connection reset; no new app
  installation, TestFlight upload or submission occurred.
- **Earlier Apple access interruption, now resolved:** the Safari tab initially
  redirected to login. The user signed back in and the read-only Apple audit is
  recorded above. No agreements, account configuration or App Privacy answers
  were changed.
- **Still missing:** consent/disclosure and server-enforced pre-publication
  screening for text, photos and audio; bounded worker/provider processing;
  secure human-review media access and urgent takedown/appeal operations;
  final-device verification of the new safety UI. Privacy source now describes
  reports and Resend, but this revision still needs publication with the final
  screening disclosures. Do not scan existing
  family archives under the optional AI-chat consent. The public launch remains
  NO-GO pending these and the other gates below.

## Recovery checkpoint - 11 October 2026

This checkpoint supersedes the unresolved Ross diagnostic status below.

- **Confirmed bug:** live validation at 20:51:29 UTC identified an expired,
  unrevoked sandbox transaction whose immutable retired binding matched Ross
  and the current family, but whose Apple-signed `appAccountToken` did not match
  Ross. The token check ran before the existing retired-history acknowledgment.
  The family was already free/expired; no waiting period was blocking it.
  The evidence does not establish why that later token changed.
- **Deployed:** migration `20261011205859_acknowledge_retired_apple_history`
  moves historical acknowledgment ahead of token comparison only for an expired,
  unrevoked, retired chain whose existing purchaser/family/environment binding
  matches and whose caller is still a family member. It cannot displace active
  coverage. This path returns `APPLE_RETIRED_HISTORY` without changing a binding,
  granting storage, or writing an entitlement, checkout reservation or audit event.
  Active purchases and wrong purchaser/family claims keep their existing checks.
- **Verified:** the new regression failed before the fix. All 21 sponsorship
  database tests and 62 billing/UI Flutter tests pass, including cached-error
  recovery, idempotent history acknowledgment, fresh legitimate checkout and
  negative active-token/ownership/environment cases. Live function readback matches
  the migration. A read-only, rolled-back live regression using an existing retired
  chain and an in-memory changed token returned `APPLE_RETIRED_HISTORY`; wrong
  purchaser and active-token mismatches still rejected. No production data was
  altered by those checks. Internal RPC grants and security advisor findings are
  unchanged; existing findings remain in the submission gates below.
- **Phone confirmation:** user replied "yes" after being asked to remain in Ross
  and restore once: the red error disappeared, the message became "This subscription
  is no longer active," and plan buttons became available. This is user-reported
  real-device expired-restore recovery, not a fresh active purchase. No phone update
  was needed for this server-only fix. CoreDevice could not connect for inventory,
  so build 19 remains the last independently verified install, not a new readback.
- **Fresh purchase:** user reported that the instructed Family monthly sandbox
  purchase in Ross worked. Independent live read-only SQL confirms
  `everroots.family.monthly`, sandbox, active, effective `everroot_family`, with
  Ross as billing owner and Linebreakers/Frank still a member of the same family.
  The recorded paid end is 12 October 2026 at 23:04:09 Africa/Johannesburg.
  Currency and the exact completion message were not separately supplied in this
  reply. This proves an active sandbox entitlement, not final TestFlight delivery.
- **Device steps scheduled at that checkpoint (results above):** verify Frank sees the shared 10 GB without buying or
  restoring Ross's purchase; cancel renewal using Ross's app and Apple purchase
  identities, verify access remains until the recorded paid end, then verify
  Free/500 MB and retained content. Only after coverage has ended, use Frank's own
  app and Sandbox identities for restore and one fresh replacement purchase.
  Stop on any error; do not repeat purchases or clear purchase history. Do not
  assume a one-hour reset: the recorded expiry, not elapsed time guessed from
  subscription duration, controls eligibility. Final TestFlight lifecycle and
  the other launch gates remain outstanding.

## Baseline checkpoint - 7 October 2026

This checkpoint supersedes older delivery and missing-fix statements below.
User authorized proceeding with launch fixes and connected/unlocked the iPhone.

### Deployed and verified

- Database migrations `20261007213340_media_reference_authorization`,
  `20261007213345_voice_transcription_jobs` and `20261007214130_scope_avatar_reads`
  are deployed. New media references must match the actual vault, family,
  legacy profile and memory. Historical forged references do not grant reads.
  Removed the blanket authenticated avatar read policy; own/family access remains.
- `index_voice_note` v24 is active with JWT verification. It uses authenticated
  Storage downloads plus server-side object/parent checks, bounded downloads,
  file-derived duration, content-hash deduplication and abortable provider calls.
  Dependencies are locked in `index_voice_note/deno.lock`.
- The transcription backstop reserves 120 seconds per new provider request,
  capped at 7,200 reserved seconds per UTC day across the app (60 new calls).
  Per-family quota uses file-derived duration. This conservative launch cap is
  not a dollar budget or protection for chat/egress. A metadata parser is not a
  full audio decoder; malformed-container testing and provider limits still matter.
  Ambiguous provider failures are not automatically retried or recharged.
- Live disposable QA run `918a2b27-fe93-4cba-9822-e6c17824bea8` verified rejected
  forged INSERT/UPDATE references and unreadability of a historical forged row;
  explicit AI consent, withdrawal and a synthetic five-second M4A transcription;
  repeating the request reused one succeeded job and its transcript despite a
  false one-second client duration. Shared legacy content survived contributor
  deletion, the survivor could contribute, and last-member cleanup succeeded.
  Readback: zero fixture users, family, storage objects and transcription jobs;
  original baseline of three families and 15 storage objects restored.
- Follow-up avatar run `529464b5-1440-4b57-a6d0-06ffbef76299` verified real
  authenticated owner/family downloads and denial to an unrelated user under
  the final policies, then repeated shared-media deletion checks. Independent
  cleanup readback again confirmed zero fixtures and the three-family/15-object
  baseline; the blanket avatar policy is absent.
- Privacy/Terms links are now in sign-in and the plan footer. Settings also
  exposes Privacy, Terms and Contact support. Restore/refresh remain at the bottom.
  The privacy URL is publicly updated to the 7 October policy, including shared
  legacy retention, optional AI processing and the transcription cache.
  Hosting version `3efc17b2e67461e1` changed only `/privacy.html`; all other 42
  file hashes were verified unchanged. Public HTTPS bytes match `web/privacy.html`.
  Terms link to Apple's standard EULA; legal adequacy and App Store entries still
  require review, not an engineering claim of legal clearance.
- Installed and launched `com.everroots.app` 1.0.0 (18), 36.5 MB, on the physical
  iPhone after unlock. Independent CoreDevice readback confirmed build 18 and
  `builtByDeveloper=true`. No uninstall or established-account deletion occurred.
  This is a direct developer install, not a TestFlight upload. TestFlight 13 is
  still the last confirmed uploaded build in this ledger.
- Tests: full default Flutter suite 113 passed / 47 purchase-dependent skips;
  separately enabled focused suite 67 passed / no skips; four transcription Deno
  tests and worker typecheck passed. All 14 media/deletion/claim database cases passed,
  including the additional avatar owner/family/outsider/former-member case.
  Running the whole suite with billing flags gives one expected mismatch in the
  test specifically asserting empty default product IDs; no production check was
  weakened. New legal-links/sign-in/test analyzer scope is clean. The wider
  vaults screen still has 42 pre-existing lint notices. `git diff --check` is clean.

### Remaining before submission

1. **Unverified: complete payments lifecycle on the current candidate.** Build 19
   and validation worker v15 contain the routing/recovery correction below; v16
   adds ownership diagnostics. The 11 October database fix resolves Ross's retired
   history rejection, now confirmed by the user on the phone. Ross's fresh Family
   monthly sandbox purchase also succeeded. Shared access for Frank, cancellation,
   expiry to 500 MB and Frank's replacement purchase now pass on the phone; live
   SQL confirms Frank as the new active billing owner. Ross's shared 10 GB and
   retained photos/voice notes after replacement are also user-confirmed. Still verify localized Apple confirmation,
   rightful active restore, wrong-account rejection, upgrade, refund and
   interrupted/offline recovery on the final candidate.
   Repeat the essential lifecycle on the final TestFlight distribution build.
2. **Partly implemented: UGC safety flows.** Reporting, blocking and audited human
   review are implemented; the database foundation and deletion compatibility fix
   are deployed and disposable-account QA passed (13 October checkpoint above).
   Resend report-reference alerts are deployed and delivery/retry behavior is
   verified. Automated pre-publication screening, its consent/privacy disclosures,
   secure review/takedown operations and final-device safety tests remain.
   Neither a support email nor the foundation
   alone closes this gate. Preserve shared legacy contributions.
3. **Unverified: final device core flows.** Invite/join, legacy contribution,
   photo/audio playback, AI decline/grant/withdrawal, legal links and deletion
   disclosure on the delivered build. Live disposable deletion is proven;
   interrupted-network and actual paid-sponsor deletion still need coverage.
4. **Unverified: production operations and security follow-through.** Check
   monitoring/alerts, recovery backups, provider-wide cost limits and remaining
   privileged RPC findings. The fresh security advisor still flags
   [disabled leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection),
   [vector in public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public)
   and [authenticated security-definer RPCs](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
   New job tables intentionally deny client access and have no client policies.
5. **Unverified / must wait: Apple and business gates.** Fresh agreements,
   banking/tax, subscription products, App Privacy answers, screenshots, reviewer
   account/access, age rating, export compliance, final brand/countries/legal
   decision. Upload the final distribution candidate, verify TestFlight, then
   submit with manual release. None of this is implied by today's cable install.

No public release or App Review submission was performed at this checkpoint.

### Payment recovery correction - 7 October, build 19

- User reported build 18 returning four ZAR products (storefront ZAF), but
  refresh/restore repeatedly showed awaiting confirmation. Safe app diagnostic:
  `VALIDATION_REJECTED (HTTP 400)`. The user subsequently clarified that Ross
  was signed into both the app and sandbox, not Linebreakers as first requested.
- Live function logs at 21:39-21:43 UTC showed `apple_http_status: 401` before
  entitlement application. Inspection of deployed v13 confirmed client validation
  always attempted the production API first. Only transaction-not-found 4040010
  selected sandbox, so a production 401 prevented sandbox verification.
  Apple secret digests show no rotation since August; this does not alone prove
  their current validity. Currency/product lookup is a separate successful path.
- Recovery also discarded StoreKit's signed receipt. The installed plugin's
  unfinished API supplies a JWS, but its all-history API explicitly sets receipt
  to nil. Build 19 preserves unfinished receipts and uses the existing native
  subscription channel to return the latest locally verified subscription's JWS
  from `Transaction.all`, including expired history.
- Deployed `validate_apple_subscription` v15, JWT verification still enabled.
  Signed transaction environment is checked using Apple's signature verifier
  before selecting an API endpoint; the fresh API response is independently
  verified before product, purchaser, family and entitlement checks. Old clients
  without a JWS can select an endpoint using an unambiguous previously verified
  audit event for the exact transaction ID, but must still fetch/verify with Apple.
  Unknown environments keep the documented production/4040010 discovery path.
  No authentication-error fallback, manual entitlement grant or ownership bypass.
- Reuses the existing Apple verifier's bounded certificate cache, as the
  notification worker already does, to avoid duplicate certificate network checks.
  Apple API authentication errors now expose a safe explicit code; build 19
  identifies a server verification outage rather than urging immediate repeated
  restores. No receipts, credentials or customer identifiers are logged.
- Verification: 10 environment-routing tests; 13 signature/certificate regression
  tests; separate live Apple certificate-chain/OCSP test passed. Billing-enabled
  Flutter suite: 61 passed, including the native history-channel contract,
  unfinished receipt preservation, ownership rejection and fail-closed errors.
  Worker typecheck and changed Flutter analyzer scope pass. Live source readback
  matches deployed v15. Signed release build 19 compiled, installed and launched;
  independent CoreDevice inventory reports `com.everroots.app` 1.0.0 (19).
- **Post-fix result:** Linebreakers reported "This subscription is no longer
  active." Live audit events at 21:59:02 and 21:59:45 UTC confirm successful
  sandbox validation of its expired Legacy annual purchase. This proves expired
  restore, not a fresh active purchase or the final TestFlight lifecycle.
  Production API acceptance remains unproven; sandbox success is not proof of it.

### Ross purchaser mismatch - 8 October

- User confirmed Ross is signed into both Ever Roots and the Sandbox Apple Account.
  Do not repeat account-switch instructions or assume the user is on Linebreakers.
- Live family state is free/expired, paid coverage ended 29 September at 13:11:09
  UTC, with no live checkout holds or other active Ross sponsorship. There is no
  extra month/year waiting period blocking replacement.
- Function logs at 7 October 22:05:23 UTC show `APPLE_PURCHASER_MISMATCH`, not an
  Apple API authentication failure. Live SQL checks the Apple-signed appAccountToken
  against the authenticated app user. A bound purchase owned by another user would
  normally fail earlier with `APPLE_PURCHASE_ALREADY_BOUND`.
- Existing audit evidence: Linebreakers' latest accepted transaction token matches
  Linebreakers; Ross' older accepted history had no token and its binding is now
  retired. These records do not identify the newly rejected transaction. Do not
  infer that removing the purchaser check or ignoring expired history is safe.
- Deployed validation v16 with JWT verification unchanged. Only after verified
  transaction and product checks, purchaser rejection logs hashed transaction
  fingerprints, expired/revoked state and boolean token/binding relationships.
  No raw receipt, account UUID, appAccountToken, email or credential is logged.
  Diagnostic lookup failure cannot change validation outcomes. No database,
  entitlement, ownership or phone-build change was made for this diagnostic.
- Verification: 13 focused Deno tests pass (3 diagnostic/privacy cases plus 10
  existing routing cases), worker typecheck passes, deployed source readback
  matches all nine expected files. Await one Ross restore to locate the conflict;
  the purchasing block is not yet fixed or classified as a confirmed code bug.

## Launch contract

- One purchaser-bound Apple subscription sponsors one family. Members share its
  allowance; billing does not change personal vault or collaborative tree rights.
- Free: 500 MB. Family: 10 GB. Legacy: 50 GB. Cancellation stops renewal, not
  already-paid coverage. Expiry returns to free without deleting memories.
- A different member may sponsor after coverage ends using their own Apple
  purchase identity. No pooled subscriptions or early purchaser transfer at launch.
- Store prices come from Apple, not a hardcoded currency or the app login.
- Confirmed by the user on 2 October: all authorized family members may contribute
  to shared legacy profiles. Deleting a contributor or profile creator's account
  removes their personal vault, but retains all legacy contributions for the
  remaining family. User said "perfect you understand proceed" after clarification;
  deployment and disposable-account verification may now proceed.

## Evidence and work order

1. **Payments - in progress.** Prior live events prove purchase, upgrade,
   cancellation retaining coverage, and expiry. They do not prove a new
   purchaser's replacement checkout on the current TestFlight build. The latest
   phone screenshots show account-binding rejection and dollar prices.
   Source inspection now confirms the installed StoreKit plugin restores cached
   current entitlements without AppStore.sync; our unfinished-purchase precheck
   can stop an explicit restore before Apple is refreshed. Fix and test this
   first, without bypassing server ownership checks. Price refresh and safe
   diagnostics must distinguish Apple-returned currency from stale local state.
2. **Family admission - deployed and database tested.** Direct membership writes
   are locked down; authorized invite and role-protection tests pass. Final
   candidate invite/join device smoke test remains.
3. **Deletion and shared media - backend fixed and live verified.** The unsafe
   delete_account v9 has been replaced by v10. Shared legacy contributions and
   creator succession passed a disposable-account live test. Updated deletion
   disclosure is in installed build 17, pending visual/device confirmation.
   See evidence below.
4. **AI consent - deployed; device and operations checks remain.** Explicit
   permission is implemented in installed build 17 and enforced by the backend;
   the old chat route is retired. Test decline/grant/withdrawal on the phone and
   verify provider-wide spending protection separately from per-family quotas.
5. **Production and Apple review - unverified.** Both Apple environments now
   have deployed routing and isolation. End-to-end candidate proof is still
   required. Recheck agreements, banking/tax, review
   metadata, privacy disclosures, reviewer access, notifications and monitoring.
   Trademark/legal clearance remains a business decision, not engineering proof.

## Delivery status

- User authorizes fixes and reports the iPhone connected. CoreDevice lists it as
  available after the read was retried outside the filesystem sandbox.
- Latest previously delivered TestFlight build: 1.0.0 (13).
- Local payment recovery now explicitly calls AppStore.sync before restore,
  reloads StoreKit prices on refresh, and exposes safe Apple billing diagnostics.
  Sixty focused Flutter tests passed. Release build 14 succeeded; installation
  was blocked by the iPhone lock screen. It has NOT been installed or uploaded.
- Deployed membership-write lockdown (20261001214854): authenticated/anonymous
  direct INSERT, UPDATE and DELETE privileges verified absent. Three isolated
  database tests passed, including valid invite redemption and role-change denial.
- Deployed opt-in AI consent (20261001215816), vault_ai_chat v85,
  index_voice_note v23 and retired legacy_vault_ai_chat v10. Flutter consent UI
  is implemented and included in installed build 17. Four Flutter tests, one database test,
  two Deno tests and the three handler type checks passed. Older builds cannot
  start AI processing until consent is granted in the updated app.
- Deployed legacy gallery read authorization (20261001215851); one isolated RLS
  test passed. Follow-up inspection found the profile photo also uses
  vault_photos, requiring the follow-up migration recorded below.
- The 2 October checkpoint below supersedes the initial build and unfinished-work
  notes above. No established account has been deleted; no new purchase was made
  by the agent.
- Do not delete either established test account. Use disposable fixtures for
  destructive lifecycle tests. Do not claim submission readiness from unit tests.

## 2 October checkpoint

- **Payment backend deployed:** validate_apple_subscription v13 and
  apple_subscription_notifications v11 now use verified environment routing.
  Production lookup falls back to Sandbox only for Apple's transaction-not-found
  response. Environment-isolation migration 20261001221344 prevents Sandbox
  receipts from replacing production family coverage. Purchaser binding remains
  enforced. Fresh real-device purchase and replacement-sponsor proof is pending.
- **Gallery follow-up deployed:** 20261001221334 also authorizes referenced
  legacy profile photos in vault_photos for current family members.
- **Client installed and launched:** release build 17 completed successfully
  (36.4 MB), including payment recovery, AI consent, deletion-response handling
  and the explicit distinction between personal and retained legacy content.
  After the user unlocked the phone, CoreDevice installed and launched it.
  A separate installed-app query confirmed com.everroots.app, version 1.0.0,
  bundleVersion 17 and builtByDeveloper=true. No uninstall was performed.
  This is a direct development-signed installation, NOT an App Store Connect
  upload. TestFlight 13 remains the last confirmed uploaded delivery. A matching
  distribution candidate must still be uploaded and tested through TestFlight.
- **Deletion deployed after explicit approval:** after the initial safety review
  blocked deployment, the user clarified shared-legacy retention and said to
  proceed. Applied migration 20261001225542 and deployed delete_account v10
  (JWT verification enabled). Ross and Linebreakers were not deleted or selected
  for destructive testing. Three newly created disposable accounts were used.
- **Verification:** full Flutter suite passed 110 tests with 47 skips; the
  separately billing-enabled focused suite passed 64 tests. Combined isolated
  database suite passed 35 tests, including six deletion-preservation cases.
  Six deletion-workflow Deno tests passed. Apple routing/verification tests
  passed, and the separately enabled live Apple OCSP check passed. Focused
  analyzer checks were clean; the wider repository still has existing warnings.
  Follow-up checks passed seven deletion database cases, six worker tests and
  four deletion-notice Flutter tests. Real Storage-copy behavior is now verified
  below; phone payment lifecycle success is still unverified.
- **Privacy source updated, not published:** docs/privacy_policy.md and
  web/privacy.html now describe explicit AI permission, push-token use and
  retention of contributions to shared legacy profiles after account deletion.
  Hosting publication and App Store privacy answers remain to be verified.
- **Remaining review gates:** current-device payment and two-account lifecycle;
  updated deletion disclosure and AI consent on the
  phone; agreements, banking/tax and Apple review assets/access. Fresh security
  advisors still flag disabled leaked-password protection and other warnings;
  no blanket security clearance is claimed. Public paid launch remains NO-GO.

## Live deletion evidence - 2 October

Authorized fixture run: c2c58233-0629-4319-9603-0e9b25987cb5.
Isolated family: 12472873-c8dd-4b8c-b9c9-35502242ea30 (removed after testing).
Runner: supabase/verification/account_deletion_live_qa.mjs. It requires explicit
EVERROOT_RUN_LIVE_QA=1 and operates only on its generated disposable accounts;
credentials are held in memory, not written to the evidence manifest.

- Two members each created a legacy profile and contributed to both profiles
  through authenticated client requests: four photos, four stories, four WAV
  recordings, plus personal media and a fixed-path family avatar.
- Deleted the first contributor through the deployed endpoint. Both profiles,
  all four photos/stories/recordings and the family avatar survived. Downloaded
  photo/audio bytes matched the originals exactly. Profile creator and family
  owner handoff succeeded. The departing personal vault and file were removed;
  the survivor's personal file stayed readable.
- An unrelated third account could not read the legacy photos before or after
  deletion. The surviving member could add and read a new contribution.
- Deleted the final member and unrelated fixture through the same endpoint.
  Auth users, the fixture family, legacy profiles, fixture storage and job records
  were removed. Read-only SQL confirmed zero fixture users/objects/jobs; total
  family and storage counts returned to the pre-test baseline: 3 and 15.
- Client roles cannot read deletion job tables or execute the privileged
  finalizer. Advisor notices for policy-free job tables are intentional deny-all
  client access; the retained-media helper is intentionally callable and checks
  current family membership. Existing vector/password-protection warnings remain.
- Limits: real interrupted-network recovery and an actual paid sponsor deleting
  their account were not exercised in this live fixture. Retry and copy-failure
  ordering are covered by the local worker/database tests.

## Required payment proof

Fresh sync/restore; rightful restore; wrong-account rejection without charge;
localized prices matching Apple's confirmation sheet; one replacement sandbox
purchase after expiry; shared member access; cancel/expiry with content retained;
over-quota reads preserved and writes denied; interrupted checkout recovery.
