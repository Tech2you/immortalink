# Launch recovery status - 1 October 2026

Public paid launch: **NO-GO until the gates below are verified**.
This is the current work ledger; earlier recovery notes are historical evidence.

## Latest checkpoint - 21 October 2026

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
