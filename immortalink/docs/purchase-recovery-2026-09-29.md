# Purchase recovery and deletion reconciliation

Evidence captured 29 September 2026 SAST (28 September UTC).
This supersedes billing runtime/device status in family-sponsorship-2026-09-28.md.
Public paid launch remains NO-GO pending the real lifecycle tests and deletion work.

Latest update: see **Follow-up: successful purchase, expiry and sponsor handover**
below. The later live evidence proves Linebreakers' active purchase and expiry;
earlier sections describing only expired Ross history are historical snapshots.

## Confirmed causes

- Supabase runs Deno 2.1.4. Apple's Node verifier called unimplemented certificate
  methods (`toString`, `raw`, `infoAccess`, `verify`). Its jsonwebtoken verification
  also relies on EC key metadata absent from this runtime. Valid Apple fixture
  verification reproduced the failure locally under 2.1.4, although newer Deno
  tests had passed. The user's restore at 22:30 UTC logged RUNTIME_UNSUPPORTED.
- A failed verification left the family checkout reservation in place. Switching
  app accounts does not release that server-side hold; it lasts up to 15 minutes.
- StoreKit 2 rejects a repeated purchase when the same product has an unfinished
  transaction. Plugin source confirms this path. The earlier client converted
  the exception to a generic connection/start error; the specific original
  on-device exception was not captured, so this remains the likely explanation
  for the pre-sheet failure, not a proven receipt-level diagnosis.
- The historical sandbox subscription has an existing Ross purchaser binding
  and an earlier successful client-validation event for Ross. Linebreakers'
  restore after the runtime fix reached the database and returned
  APPLE_PURCHASE_ALREADY_BOUND at 22:34 UTC. This is not an owner-only purchase
  restriction and was not bypassed. App login and Apple Sandbox login are separate.

## Implemented and deployed

- Apple's MIT-licensed v3.1.0 verifier source with a narrow certificate adapter
  and pinned ES256 WebCrypto verification. Chain trust, Apple-purpose extensions,
  dates, online revocation, bundle and environment checks remain enabled.
- Privacy-safe fixed diagnostic categories; no receipts, credentials or raw
  exception payloads are emitted by the new diagnostics.
- Migration `20260928223253_sponsorship_checkout_lifecycle.sql`: checkout nonces,
  account/nonce-scoped release, private attempt history for delayed restores,
  six new attempts per user per minute. Existing reservations were backfilled;
  no entitlement or purchaser binding was manually reassigned.
- Checkout history contains UUIDs and timestamps, not receipts or identity text.
  It currently lasts until account/family deletion; no timed pruning is claimed.
- Client explicitly recovers unfinished transactions before another checkout,
  finishes only after verified backend acceptance, deduplicates replay/in-flight
  validation, prevents double taps, and checks identity after async verification.
- Before starting a new purchase, the client verifies the latest previous
  supported Apple transaction, including finished/expired history. A different
  purchaser binding blocks checkout before Apple can start a renewal or change.
- Cancelled/unstarted checkout releases its own reservation. Unknown StoreKit
  bridge failures keep the hold because a charge may already exist. Failed
  verification remains unfinished and prompts restore instead of another purchase.
- App Store localized prices, one-active-sponsor enforcement, original purchaser
  binding, tree permissions and plan allowances are preserved.

Initial recovery versions: validate_apple_subscription v11 (JWT on),
apple_subscription_notifications v10 (JWT off intentionally, signed Apple payload
verified). Sensitive history and verification RPCs are not client-readable or
client-callable; authenticated member checkout is available, anonymous checkout
is not. Migration filename matches the recorded live version.

Signed iPhone build 1.0.0 (2026092901), com.everroots.app, was installed without
uninstalling the app. Automatic launch was denied because the phone was locked;
the user then opened it manually and completed the Ross restore test. Final
build 2026092902 was also built and installed and adds the pre-check for finished
purchase history. These are local
development-signed release builds, not TestFlight uploads.

## Verification

- 27 purchase-enabled Flutter service tests passed, including the last pre-check.
- Final default Flutter suite: 99 passed; 24 purchase-config tests skipped, covered by
  the separate enabled run. Running the entire suite with purchase flags produces
  one expected failure in the test that asserts purchases are disabled by default.
- 19 PGlite tests passed: sponsorship/recovery, successor, read-only expiry and
  usage bursts. These do not prove simultaneous live database sessions or Storage.
- 19 Deno tests passed on 2.1.4, including live Apple OCSP checks, valid signatures,
  tampered signatures, wrong bundle/environment/root, purpose/expiry rejection and
  all four product mappings. Both billing handlers type-check with Deno 2.9.0.
- Focused Flutter analysis and git diff --check passed.
- Phone/server proof: runtime failure was reproduced before deploy; after deploy,
  the real restore passed Apple verification and reached purchaser-binding checks.
- Ross's real restore then succeeded: backend client-validation event at
  22:42:48 UTC, family.monthly, sandbox, expired at 22:17:18 UTC, plan free,
  purchaser still Ross. Phone displayed "This subscription is no longer active."
  This proves rightful-account expired restore, not a new active purchase or renewal.

## Deletion: intended rule versus deployed behavior

The user's intended rule is correct: preserve the tree and family-owned legacy
content while a real member remains; last-real-member confirmed leave cleans up
the legacy-only tree; ordinary leave does not delete someone's personal vault.
Account deletion deletes that person's personal vault, not other members' vaults.
No ordinary leave or private/legacy editing permissions were changed in this task.

Live delete_account v9 was fetched again this turn and differs from local source:

1. It gathers families by the departing member's `owner` role, deletes all their
   legacy records/relationships, then deletes family_groups by owner/creator.
   This path does not first count remaining real members or call the successor
   helper. Local removal of that old block has not been deployed.
2. Both live and local code delete legacy-media references by uploader UUID prefix
   and remove whole uploader storage folders. A family-owned legacy memory may
   still rely on those bytes even though other real members remain.

For example, a photo contributed to a shared grandparent legacy profile can be
stored under the contributor's UUID. Deleting that contributor's account must not
erase the retained family's shared photo merely because of the storage path.
This is cleanup-code behavior, not a proposal to change normal editing authority.

Do not delete either test account yet. Next deletion work must preserve/re-home
retained shared references and bytes, use successor/last-member checks, make
cleanup retry-safe, then test against two disposable accounts and live Storage.

## Next phone steps

1. Rightful Ross restore and wrong-account Linebreakers rejection are now verified.
   Do not start another purchase to clear an unconfirmed one.
2. For Linebreakers' independent sponsor purchase, use a separate fresh South
   African Apple Sandbox tester. Do not rebind Ross's historical purchase to it.
3. Prove successful purchase and rightful restore, shared access and join after
   purchase, wrong-account rejection, cancellation, expiry/replacement, delayed
   approval, renewal/refund, offline recovery and storefront changes.
4. Finish and prove deletion safety, then production Apple configuration/review,
   rebrand/domain/email/legal updates and operating cost limits. No claim of
   complete security or public-payment readiness is made from these unit tests.

## Follow-up: slow verification and Linebreakers (29 September, midday SAST)

Fresh evidence:

- The Linebreakers request at 10:16:55 UTC reached verifier v11 and returned
  APPLE_PURCHASE_ALREADY_BOUND. Edge execution took 2,678 ms; this does not
  measure the phone's total StoreKit/network/UI time.
- The existing sandbox binding is still Ross's, the family plan is free/expired,
  and no fresh active purchase is proved. The user confirmed they only switched
  app logins, not the Sandbox Apple Account on the iPhone.

Changes:

- Remove the unconditional 8-second restore wait and 2-second validation-error
  delay. Wait for StoreKit's actual restore callback and queued verification;
  a missing callback fails closed. Native restore and backend verification each
  have a 20-second timeout. This is not a guarantee for total operation duration.
- Remove storefront/price queries from the purchase-update verification path.
  Pricing errors are now separate from purchase errors, so the automatic price
  refresh cannot erase an account-mismatch message while leaving checkout blocked.
- Deduplicate repeated binding rejections within the current service session.
  Explicit restore rechecks both rejected and completed transactions, including
  expired history, so changing the Apple test account or a refund is not hidden
  by the replay cache. Empty history after an Apple-account change clears the
  local recovery block without granting an entitlement or opening checkout.
- Show progress/account guidance and recovery actions before plan tiles. Only a
  server-reported sandbox mismatch offers Sandbox Apple Account instructions.
- No purchaser rebinding, entitlement grant, new purchase, schema change,
  family permission change, or usage-limit change was performed.

Verification and delivery:

- 36 purchase-enabled Flutter tests passed (9 new regressions).
- Default Flutter suite: 99 passed, 33 purchase-config skips covered by the
  separate enabled run. Service/test analyzer: no issues. The vault screen has
  42 pre-existing informational lints outside this change, not a clean analyzer
  result for that whole file.
- 19 Deno tests passed on 2.1.4, including live OCSP; handler type-check passed.
- validate_apple_subscription v12 deployed with JWT verification enabled.
  Unauthenticated POST still returns 401. Apple notification handler stays v10.
- Signed local iPhone build 2026092903 completed. Installation has not succeeded:
  CoreDevice reports the paired phone cannot satisfy its connectivity assertion.
  Reconnect/unlock the phone before installing and testing. Not uploaded to TestFlight.
- Actual new phone timing and a fresh Linebreakers sandbox purchase are still
  unverified. Do not present the tests as proof of a successful active purchase.

Apple's documented setup for this development-signed build is Settings >
Developer > Sandbox Apple Account. Use a separate fresh South African sandbox
tester for Linebreakers; ordinary Ever Roots sign-out does not switch Apple
purchase history. Do not sign out of the device's main iCloud account. Reference:
https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox

## Follow-up: successful purchase, expiry and sponsor handover

29 September 2026, afternoon SAST. Live backend reads, user screenshots and local
regression tests are distinguished below; this is not a public-launch sign-off.

### Deployed and verified

- Linebreakers' new sandbox Family Monthly transaction was verified at 12:47:04
  SAST and bound to Linebreakers, not Ross. Apple renewal-status notification
  arrived at 12:49:01. The screenshot shows cancellation in Apple's sheet.
- Paid coverage ended at **12:51:56 SAST**, so the screenshot still showing 10 GB
  at 12:50 was correct. Apple's EXPIRED notification was applied at 12:53:53.
- Fresh reads confirm `free` / `expired`, effective plan `free`, and a storage
  allowance of **524288000 bytes (500 MB)**. The effective-plan SQL checks the
  paid-through timestamp itself, so quota expiry does not depend on a timely
  EXPIRED notification. No allowance or purchaser was manually reassigned.
- Migration `20260929111512_returning_family_sponsor.sql` is deployed. Its
  filename matches the live migration version. The verifier remains v12 and
  notification handler v10; neither Edge Function changed during this follow-up.
- The new returning-sponsor path preserves the immutable purchaser/family
  binding. An expired, retired purchase may clear its rightful purchaser's
  preflight without changing the family's entitlement. A rollback-only live
  check using Ross's stored verified transaction returned APPLE_RETIRED_HISTORY;
  the family still belongs to Linebreakers' expired subscription afterward.
- Reactivation requires current membership, the matching signed appAccountToken,
  a new Apple transaction with transactionReason PURCHASE, a checkout created
  after retirement, and no competing active family coverage. Old auto-renewals,
  mismatched accounts/families and released/old checkout attempts cannot take over.
- Live privileges still deny anon/authenticated callers direct access to the
  apply-verification RPC and deny authenticated reads of the binding ledger.

### Implemented and tested locally

- Family-plan management is shown only to its recorded purchaser, and checked
  again before opening Apple's sheet. Generic Apple management remains available
  in deletion/leave warnings so people can stop their own renewal.
- Account mismatch text explicitly says **original purchaser's app account**.
  Switching app logins never switches the phone's Apple/Sandbox identity.
- The dialog refreshes current plan, storage and sponsor after verification,
  return from Apple's management sheet, foreground resume, the paid-through
  deadline, manual refresh, and every 30 seconds while open in the foreground.
  A failed usage lookup shows unknown status rather than claiming Free is current.
- The paid-through date/time and sponsor-change rule are visible. The app does
  not claim auto-renew is cancelled from transaction expiry alone; renewal status
  remains authoritative in Apple's sheet. An early cross-person billing transfer
  with overlapping subscriptions has not been implemented.
- 45 purchase-enabled Flutter service/widget tests passed. Full default Flutter
  suite: 105 passed, 36 purchase-configuration skips (covered by the enabled run).
- 22 database regression tests passed, including 16 sponsorship tests. These
  include returning-sponsor purchase, expired-history no-op, replay/renewal
  rejection, concurrent-sponsor rejection and cancellation versus expiry.
- Billing service/new tests analyzer: no issues. Vault screen still has 42
  pre-existing informational lints outside the changed billing section.
- Security advisors before/after: unchanged. Private billing tables intentionally
  have RLS and no client policies. Existing warnings still need the broader
  launch audit: [public vector extension](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public),
  [authenticated definer RPC review](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
  and [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
  No broad security-clearance claim is made.

### Phone delivery and next test

- Signed build **2026092904** completed; CFBundleVersion checked directly.
- Installation was attempted without uninstalling or clearing app data. CoreDevice
  lost its connection (installation error 3002 / remote connection interrupted).
  Subsequent device queries report unavailable. Installation is **not confirmed**;
  do not assume the new controls are on the phone. No TestFlight upload occurred.
- Reconnect/unlock the iPhone, install this build, then use Ross's own Sandbox
  Apple Account with Ross's app login. Verify expired-history restore and one new
  sandbox purchase after checking the family remains Free. Verify Linebreakers
  receives shared access without family management controls. Use each purchaser's
  own Apple account; do not rebind the other account's subscription.
- Still needs testing: the new phone UI and returning-sponsor purchase, renewal,
  refund, interrupted/delayed approval, join after purchase and other lifecycle
  gates. Do not delete either account until shared-media deletion is fixed.

Apple references: [paid-through cancellation behavior](https://developer.apple.com/documentation/storekit/handling-subscriptions-billing),
[sandbox acceleration](https://developer.apple.com/documentation/storekit/testing-an-auto-renewable-subscription),
[customer purchase versus automatic renewal](https://developer.apple.com/documentation/appstoreserverapi/transactionreason).

## Follow-up: covered-member notice and footer controls

29 September 2026, approximately 14:50 SAST. No backend writes, deployments,
purchases, cancellations or account deletions were performed in this follow-up.

### Fresh phone and backend evidence

- The user reports verification now takes approximately three seconds and that
  tests 1-4 appear to work. Screenshots show the new paid-through date, sponsor-only
  management and shared 50 GB access. This confirms the newer UI is present,
  although the exact installed build number could not be read over CoreDevice.
- The backend records a Linebreakers Family Monthly purchase at 14:10 SAST and
  an upgrade to Legacy Annual at 14:11. A fresh read at 14:49:23 SAST confirms
  active sandbox Legacy Annual, with coverage through **15:11:09 SAST today**.
- Recent successful validations took approximately 2.2-2.9 seconds on the server.
  Ross's failed restore at 14:27:21 returned APPLE_PURCHASER_MISMATCH in 2,955 ms;
  shared family coverage remained intact. This does not establish which Sandbox
  account the phone was using when StoreKit replayed that transaction.
- A renewal-status notification exists, but the stored event does not include
  autoRenewStatus. Do not infer renewal is off from that event or the paid-through
  date. Apple's subscription screen remains the source for cancellation status.

### Narrow client changes

- Restore purchases and the Refresh plan and prices icon now sit after all plan
  tiles. Refresh updates both family allowance and the localized price catalog.
- A purchaser-binding mismatch is a neutral notice only for a non-purchaser with
  known, unexpired shared paid coverage. It says family access is already available
  and that the checked Apple purchase was not restored to this account.
- Original-purchaser mismatches, unknown/expired coverage and other payment
  failures retain actionable error treatment. Backend validation, unfinished
  transactions, purchaser binding, recovery blocks and management restrictions
  are unchanged. Neither receipt ownership nor family access is reassigned.
- Restore asks Apple for existing purchases and verifies them against the current
  app account/family. It does not buy, cancel or transfer a subscription. An
  ordinary covered member does not need to restore the sponsor's purchase.

### Verification and delivery

- 52 purchase-enabled Flutter service/widget tests passed, including both
  purchaser mismatch codes, expired/unknown coverage, actual payment failures,
  footer refresh, action ordering and large-text layout.
- Full default Flutter suite: 106 passed, 42 purchase-configuration skips covered
  by the separate purchase-enabled run.
- 17 local database tests passed: 16 sponsorship cases plus the expired,
  over-limit read-only case. Existing records remain readable, new additions are
  blocked over quota, and renewal or reduced usage restores writes. This is not
  yet physical-phone proof of retained Storage photo/audio playback after expiry.
- Service and test analysis: no issues. Vault screen: 42 existing informational
  lints, all outside the changed billing section. git diff --check passed.
- Signed build **2026092905** completed and CFBundleVersion was verified locally.
  Installation failed with CoreDevice error 4016 (trusted device connection not
  available). No uninstall or data reset was attempted. **Not installed or uploaded
  to TestFlight.** Reconnect/unlock the iPhone before retrying installation.

### Remaining expiry check

Apple's default Sandbox renewal speed makes an annual period one hour, not a
calendar year. The observed annual period here is 14:11-15:11 SAST. Settings can
change that speed; use the actual paid-through timestamp, not the product label.
Reference: [Apple Sandbox renewal settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings).

Confirm renewal is off in the purchaser's Apple subscription screen. After the
paid-through time, refresh/reopen Family plan and check **Free Family / 500 MB**,
then open an existing photo and play an existing recording from both app accounts.
The family currently uses about 13 MB, below the free allowance, so new uploads
should still be possible within free limits. Over-quota behavior is covered by
the local 600 MB fixture rather than filling this live family's storage.

Do not clear Sandbox purchase history, change the phone clock, or delete test
accounts to force expiry. On-device expiry/media retention and subsequent
purchaser handover still require evidence; this is not public-paid launch approval.

## TestFlight delivery: 1.0.0 (13)

29 September 2026, 16:06 SAST. At the user's request, the source used for local
development build 2026092905 was exported for TestFlight as **1.0.0 (13)** with
the purchase-enabled build script and all four Ever Roots product IDs. No app
source, backend, purchase ownership or subscription state was changed for this
delivery. Earlier test results above were not rerun during the packaging step.

- Release archive and App Store Connect export completed successfully.
- IPA metadata verified: com.everroots.app, version 1.0.0, build 13.
- IPA: build/ios/ipa/Ever Roots.ipa, approximately 32.2 MB.
- SHA-256: d6bd4e66fa435ec54e230e13ad492f22371027ad27de75e13314e73e3c976ffc.
- Transporter confirmed Delivered at 16:06 SAST; App Store Connect independently
  lists build 13 as Processing. Processing is not yet installation availability.
- The existing Account Holder was added to the existing Internal Beta group at
  16:13 SAST; App Store Connect confirms one tester with status Invited. No new
  App Store Connect role or external testing access was granted. Build 13 still
  needs processing/compliance clearance and assignment to this group.
- Flutter reported a default launch-image placeholder warning. This did not
  prevent export; it remains a launch-polish item.
- No public App Store submission was made. This upload does not establish
  on-device expiry/media retention or public-paid launch readiness.

## TestFlight account and currency follow-up

29 September 2026, 23:01 SAST. User screenshots show Free Family / 500 MB,
13 MB used, dollar prices from the catalog, and a purchaser-binding error on
Ross's app login. The footer actions are present, but the screenshot does not
independently identify the installed build number or the active Apple account.

- Read-only live inspection confirms effective and stored plan `free`, status
  `expired`, and Linebreakers' last Legacy Annual Sandbox period ending at
  15:11:09 SAST. No additional waiting period remains for that coverage.
- Server logs at 22:55-22:56 SAST show `APPLE_PURCHASE_ALREADY_BOUND`. This is
  historical purchase ownership protection, not an active-sponsor hold. Expiry
  does not transfer a previous purchaser's Apple transaction to Ross.
- The app displays StoreKit's localized `ProductDetails.price`; it does not
  substitute a dollar fallback. The phone's actual active storefront has not
  been independently read, so the source of its dollar storefront is unverified.
- Four focused purchase-enabled service tests passed again: expiry usage refresh,
  retry after rejection, fresh-account recovery, and USD-to-ZAR catalog refresh.
  These are mocked service tests, not confirmation that the phone switched its
  Apple purchase identity correctly.

Correction to the earlier testing guidance: TestFlight apps use the Sandbox
environment, but using a specifically selected Sandbox Apple Account requires
signing out of **Media & Purchases** first, then signing into that Sandbox account
under Settings > Developer. Switching only the app login or Developer Sandbox
account may leave TestFlight using the production Media & Purchases identity for
its simulated purchases. Do not sign out of iCloud. Signing out of Media &
Purchases can temporarily affect access to purchased media; signing back in
makes TestFlight use that Apple account again.

Use Ross's separate Sandbox account configured for South Africa, reopen Ever
Roots as Ross, refresh the catalog, and Restore once to recheck purchase history
before attempting a new test purchase. Do not clear history, rebind a transaction,
alter entitlements, or force a Rand label over an Apple dollar price. The earlier
one-hour annual period was observed for that Sandbox setup, not a universal
TestFlight expiration guarantee.

References: [Apple TestFlight purchase account setup](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox),
[TestFlight subscription testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/),
[Sandbox account storefront settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).
