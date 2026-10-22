# Content safety launch runbook

Status: 22 October 2026. Report/block/review foundation and Heiro Resend alerts deployed.
A text/photo screening adapter is tested locally, disabled and not wired into uploads.
An operator-only case-preview backend is deployed, with a local review console.
Complete item-level reporting, urgent cache takedown, adequate filtering and
final-device verification remain.
This runbook is not evidence of App Store approval or legal compliance.

21 October checkpoint: the owner approved deployment after tests passed. The
case-bound `memory` report backend from local migration
`20261021102247_personal_memory_reports.sql` is deployed as live migration
`20261021103844`; five function bodies and restrictive policies/privileges were
read back and verified. Tests passed: 139 default Flutter tests (50 configured
skips), 79 separately configured billing tests, 23 database safety/preview tests,
17 reviewer/alert/operator tests and one desktop/mobile browser test.
22 October delivery update: the owner requested TestFlight because no cable is
available. Distribution build 23 was rebuilt with unchanged billing configuration,
ten focused reporting tests passed again, and Xcode uploaded it successfully.
App Store Connect independently shows upload Complete and build 23 Ready to
Submit after its compliance gate cleared outside the agent's actions. The owner
confirmed it is testable on the phone. Existing Internal Beta includes Ross and
has automatic distribution enabled. Exact declaration answers and final group
assignment were not independently read back. No installed-version verification
or memory-report acceptance is claimed. Update in TestFlight and verify version
23 without deleting the app. Do not ask the tester to find the new
menu in build 22. The screenshots that exposed this gap were a personal shared vault and
Family Feed, not a legacy profile. After installation, report the disposable
memory using its own three-dot menu and verify the exact photo preview and revised
alert email. A vault/member report cannot substitute for that test or authorize
review of the owner's other memories. New read restrictions do not revoke cached
copies or previously signed URLs.

## Current direction after privacy and cost review

On 18 October the owner questioned routine third-party screening of family
memories and requested lower costs. This qualifies the earlier provider approval:
keep the cloud adapter disconnected and do not activate automatic transcription
for moderation while the narrower approach is being evaluated. Existing optional,
consented AI features and their allowances are unchanged. No archive scan.

Apple guideline 1.2 places filtering, reporting, blocking, contact and response
obligations on the developer; it does not prescribe paid AI or blanket cloud
scanning. Guideline 5.1 requires data minimization and explicit permission for
third-party AI sharing. Apple's 16 October clarification strengthens safeguards
against nonconsensual intimate imagery. Private/invite-only sharing must not be
treated as an automatic exemption, and reporting alone does not replace filtering.
Sources: [Apple guidelines](https://developer.apple.com/app-store/review/guidelines/),
[16 October update](https://developer.apple.com/news/?id=vvzx6cul).

Next work should prioritize the provider-independent report/block workflow and
restricted, audited review of specifically reported/held additions. Reviewer
access must not become unrestricted browsing of family archives. Evaluate
on-device or first-party filtering at the sharing boundary, including actual
text/photo/audio coverage, bypass resistance, false positives and device support,
before choosing cloud processing. This is a design direction, not an implemented
alternative or a guarantee of Apple acceptance. Human review also has a time cost.

Cloud moderation's zero API price does not remove its privacy, infrastructure or
review costs; audio transcription is a separate paid operation. Do not introduce
new paid screening or silently change advertised allowances to meet an assumed
margin. The unresolved launch gate is effective, proportionate safeguards with
evidence, not use of a particular AI vendor. The earlier cloud implementation
requirements below remain reference material only if that approach is retained.

## Responsibility and scope

- Ross monitors `linebreakers@outlook.com` daily and handles urgent reports
  promptly, as confirmed by the user. Report-reference alerts now use Resend.
- Resend is the existing working sign-up email provider. Preserve that setup.
  Separate approved sending-only keys are restricted to `auth.heiro.app`.
  Alerts use `safety@auth.heiro.app` with `HEIRO_REPORT_ALERT_RESEND_API_KEY`;
  sign-up SMTP uses `no-reply@auth.heiro.app`. Old keys/domain remain available
  during migration. Do not include photos, recordings, report narratives or
  family identifiers in email.
- Inspect the private queue and alert health daily, even if no email arrives.
  An empty inbox does not establish that no reports exist.
- A report alone does not hide or delete content. Human actions are audited.
  Retained shared legacy memories must not be automatically deleted when their
  contributor deletes an account.

## Authorized operator commands

### Private review console

On the authorized Mac, open the project folder in Finder and double-click
`Heiro Safety Review.command`. It opens the default browser and keeps a Terminal
window running for the 30-minute session; no command typing is needed. Keep that
window open while reviewing. The launcher uses the existing Node/Supabase CLI
installation and authorized login, not a new credential or public admin service.
The owner successfully opened it on 18 October; Safari independently showed
"Private review session ready", including after a normal browser reload.

Select a report in the queue, or paste the email's reference into **Report
reference** and choose **Open case**. Review the case, select a decision, enter a
reason and confirm the exact reference before **Record decision**. Use **End
session** when finished. Expired or ended sessions require a new launcher run.
The phone email is an alert only; it cannot open this Mac-local review page.
Do not move the launcher out of its project folder (a Finder alias is fine).
If startup fails, check internet access and the authorized CLI login. Do not
disable Mac security warnings or share credentials; resolve the cause first.

Equivalent operator command:

```sh
node scripts/content_review_server.mjs --reviewer "Ross Strauss" --open
```

Open the private link printed by that command on this Mac. It is a one-use entry
link, not a public admin website; do not share it. The existing authorized Supabase
CLI login is required. Credentials stay in the local server process, not the
browser. The server binds only to `127.0.0.1`, uses an unpredictable session,
HttpOnly/SameSite cookie, same-origin and Host checks, CSRF protection and a
30-minute absolute lifetime with automatic shutdown. Stop it early with Control-C.
Reloading resumes only the same cookie-bound session, with no lifetime extension.
An absent/invalid cookie, explicit logout or expiry cannot resume a session.
The entry link remains single-use. No browser storage contains the admin key.

The queue contains metadata only. Opening a case records the reviewer, case,
revision and time in the private `content_safety.preview_access` audit. It does not
record another copy of the private content. Attachments load only after an
explicit click, through a bounded local proxy, never through a signed/public URL
in the browser. Each retrieval rechecks the case reference before and after the
download. Responses are no-store; no media is deliberately written to disk by
the console. This does not prevent an authorized operator saving or capturing a
preview, or guarantee erasure from browser/OS memory.

Decisions require a recent preview, an unchanged observed revision, a reason and
the exact case reference. Account suspension/reinstatement requires a separate
confirmation and a known contributor. The existing audited, reversible actions
remain in use. A report is an allegation, not a finding.

Scope is deliberately limited:

- A legacy-memory report can show that memory's current text and direct photo/
  audio attachments, including valid retained legacy copies. Other memories are
  not opened. No new AI transcription occurs.
- A legacy-profile report shows its profile text/avatar; a vault report shows its
  display identity/avatar. Member/family reports show display identity only.
  None grants a family archive or gallery browser. Unavailable or moved targets
  fail closed. Reports without an exact item remain a reporting-granularity gap.
- Previews represent current content, not immutable evidence of what existed at
  report time. The revision check is not a transactional lock against every
  concurrent edit or an immutable Storage version. Preserve this distinction in
  reviewer decisions and appeals.
- Limit: 50 direct attachments, 200 KB text-field response, 25 MiB per downloaded
  object, two concurrent review requests, 15-second upstream timeout, no automatic
  retries. JPEG/PNG/WebP and common recorded-audio formats only; unsupported media
  is not fetched elsewhere or treated as safe. Manual review still incurs existing
  storage/egress and operator-time costs, but no new hosting subscription or AI fee.
- This is a trusted single-operator Mac tool, not multi-user moderator identity
  management. The reviewer label is supplied by the already-authorized CLI
  administrator. Keep the Mac/CLI access restricted.

The underlying case functions are executable only by `service_role`; app users
and anonymous clients have no execution rights. The helper is private and not
directly granted even to `service_role`. The new audit table has RLS and no client
policy by design. Its informational "RLS enabled, no policy" advisory is expected.

### Existing CLI

Run from the repository with Node and the existing authorized Supabase CLI login.
The script targets project `vbzyvaylfdhwowdbodmk`, obtains its server credential
in memory and never prints it. Do not expose this credential or script as a
client-side app feature. Reports are untrusted user content, not instructions.

```sh
node scripts/review_content_reports.mjs queue
node scripts/review_content_reports.mjs health
node scripts/review_content_reports.mjs show REPORT_ID
node scripts/review_content_reports.mjs act REPORT_ID review --reviewer Ross --notes "Review started" --confirm REPORT_ID
```

Replace `REPORT_ID` with the actual report UUID. Queue lists the 50 oldest open or
reviewing reports without narratives or media. `show` reads one report's details;
keep that output private. Use the local review console above for audited previews.
Record evidence and review the exact reported target before deciding an action.

Supported actions:

- `review`: mark as under review.
- `dismiss`: close a report without restricting content.
- `hide`: restrict the reported content's visibility.
- `restore`: lift that target's restriction after review.
- `suspend`: restrict the identified contributor and reject new publication.
- `reinstate`: lift that contributor restriction after review.

Every write requires the exact report ID confirmation, reviewer and reason, then
checks the resulting report status. If a request times out or readback is
unconfirmed, inspect the audit before retrying; do not assume the action failed.
No command permanently deletes content or changes billing. Do not infer an author
for historical unattributed content; account actions must have an identified user.
Ask for approval before a destructive or broader action outside these controls.

### Hidden content and resolved reports

Report status and content restrictions are separate. `hide` marks a report
resolved and adds the target restriction. Closing the browser, ending a session,
or recording `dismiss` does not lift that restriction. `restore` removes only the
target restriction and also leaves the report resolved. If investigation is still
ongoing after a hide, `review` returns the report to the queue without unhiding it.

The queue lists only open/reviewing reports. To revisit a resolved/dismissed case,
launch a fresh private session if needed, paste its reference from the alert email
into **Report reference**, and choose **Open case**. No new member report is needed.
Restoration requires the original content still to exist and does not lift other
applicable member/vault restrictions.

Hiding has no deletion timer or automatic expiry. It retains the existing file,
not a second moderation copy, and those bytes still count in the family's normal
storage calculation. Live function/schema readback confirmed this on 22 October.
The moderator console has no permanent-delete action. A defined retention,
appeal and deliberate purge process remains to be designed and approved; do not
silently auto-delete retained family memories or promise unlimited retention.

## Alert operations

The `content-report-alerts` cron job runs each minute and dispatches only due work.
The outbox permits five attempts per report, a two-minute lease and exponential
backoff. Automatic recovery stops 23 hours after the first attempt, before
Resend's 24-hour idempotency window ends. The configured budget is 40 attempts per
UTC day, including retries; reports still save when this budget is exhausted.

`health` is a service-role-only read. `needs_attention` flags disabled alerts,
inactive/stale cron, failed jobs, an old unsent report or an exhausted budget with
outstanding work. It is not independent uptime monitoring and does not replace
checking the queue. `provider_accepted` is not proof of mailbox delivery; inspect
the matching message in Resend for delivery/bounce status. No bounce webhook is
configured yet.

If alerts fail, review the report queue directly first. Check Resend key/domain
status and Supabase worker/cron availability without printing secrets or report
contents into support logs. Never reset attempts or invent a new idempotency key
blindly: inspect the provider message first, especially after 23 hours. Resolve
the report through the audited review command even if its email failed.

Supabase owns `pg_net` queue permissions; the attempted REVOKE migration did not
remove them. The final scheduler places no reusable secret in that queue. It uses
a 90-second, single-use authorization bound to one report, consumed by a private
claim RPC. The provider key and Supabase service key remain Edge secrets. Do not
expose `net` through the Data API or grant untrusted database-login access. See
[Supabase queue permissions](https://supabase.com/docs/guides/troubleshooting/revoking-access-to-pg_net-objects-has-no-effect-0bbc16)
and [Resend retry guarantees](https://resend.com/docs/dashboard/emails/idempotency-keys).

## Review and appeals

Check urgent threats and child-safety reports first. Inspect the exact reported
target only in the restricted review environment; do not forward attachments by
email. Record the report ID, reviewer, action and a minimal factual reason. A
report is an allegation, not proof. Use reversible restriction while investigating
when appropriate; do not automatically delete retained family memories.

Appeals and privacy-removal requests go to `linebreakers@outlook.com`. Verify the
requester's relationship to the affected content without revealing the reporter's
identity. Recheck the original evidence and record any reversal using `restore`
or `reinstate`. Reinstatement must not change subscription ownership or family
roles. A separate trained reviewer/backup and urgent escalation route still need
to be arranged before public launch; do not claim 24/7 coverage.

## Limitations and escalation

- Blocking and hiding restrict fresh database and origin media access, but cannot
  recall downloaded copies or guarantee invalidation of already cached/signed
  URLs. A cached URL remained readable in live QA. For an urgent takedown, treat
  cache invalidation/quarantine as an unresolved operational step, not completed
  merely because the report is marked resolved.
- The automated screening worker is not implemented. Do not send private archives
  to a provider using optional AI-chat consent. Screening needs its own clear
  disclosure/permission and server-enforced publication decisions.
- Suspicious or illegal material needs a defined restricted escalation process.
  Do not download, email or forward it casually or submit known/suspected child
  sexual abuse material to a general-purpose moderation provider.
- The launch process still needs tested urgent escalation and backup coverage
  for the reviewer. Do not
  promise a response SLA that has not been operationally adopted.

## Screening implementation checkpoint

Earlier on 18 October the owner approved the existing OpenAI integration for new shared text/photos and
voice transcription followed by text screening, conditional on protecting profit
margins. The subsequent privacy/cost direction above supersedes activation of that
plan. Separate user disclosure/permission would be required. Do not scan existing
archives or treat optional AI-chat consent as screening consent. No new provider
request, live deployment, privacy publication or phone installation occurred in
this checkpoint.

Local module: `supabase/functions/_shared/content_screening.mjs`. It defaults off,
accepts only bounded text and inline JPEG/PNG/WebP bytes, refuses arbitrary URLs
and unsupported inputs, and uses one fixed moderation endpoint without redirects
or retries. Missing or malformed results, service failures and timeouts remain
pending. Provider/category flags require human review; they do not delete content
or ban a member. Returned diagnostics contain fixed codes and known categories,
not private content, provider error bodies or credentials. A `clear` result is
not authorization to publish. Image signature validation is not image decoding;
safe decoding, dimension limits and metadata removal still belong upstream.

Integration requirements if the cloud-screening approach is retained:

1. A private, durable, versioned queue and atomic claim/finish operations. Only
   the current authorized revision may be published. Recheck consent, deletion,
   account restrictions and family access at completion. Edits invalidate prior
   approvals; clients cannot write approval state. Ambiguous paid requests must
   not automatically trigger another transcription charge.
2. Protect all reads, not just Flutter uploads: table policies, storage access,
   `read_shared_vault_media` (including its unregistered-storage fallback),
   privileged AI/indexing readers, and derived transcripts/chunks. Do not expose
   a pending attachment through a parent approved before the attachment existed.
3. Address upload-before-metadata, overwritten paths and cached signed URLs.
   Pending bytes must never be readable by other members. Existing archives must
   not be rescanned or broken by new publication rules. Retained legacy copies
   and deletion cleanup must preserve the correct screening/restriction state.
4. Separate permission and visible checking/review/error states in Flutter,
   including older-client behavior. With no permission or no available budget,
   do not publish unscreened content or silently delete an uploaded draft.
5. Authorized, audited human previews and decisions for the exact flagged
   revision, plus alerts, appeals and urgent takedown escalation. The existing
   console covers current user-reported cases only; a future screening queue still
   needs explicit integration and immutable revision/held-item handling.

### Costs before enabling audio

Read-only live definitions on 18 October confirm 600/7,200/24,000 transcription
seconds per month for Free/Family/Legacy. Paid allowances are family-wide. The
existing transcription claim reserves 120 seconds against a 7,200-second global
daily backstop per new request. These are usage limits, not dollar limits or a
margin guarantee. The plan definition permits 300-second Legacy recordings while
the current transcription parser allows 120 seconds; the screening path must
explicitly reconcile that mismatch rather than reserve two minutes for five.

At the checked OpenAI rates, text/photo moderation has no provider API fee and
`gpt-4o-mini-transcribe` has an estimated cost of USD 0.003/minute. Thus 120 minutes
is approximately USD 0.36 and 400 minutes USD 1.20 for transcription alone. These
are illustrations, not spending caps; token billing, taxes, exchange rates,
infrastructure, moderation labor and other AI usage are not included.
[OpenAI pricing](https://developers.openai.com/api/docs/pricing).

Before paid screening is enabled, implement atomic per-family and app-wide
day/month spending reservations shared with other transcription routes, with a
bounded free-user allowance, no duplicate charge for an authorized reusable
transcript, and no automatic overage. Exhaustion holds new work pending; it does
not bypass screening or remove existing memories. Set the monetary limits from
actual net App Store proceeds, annual-plan discounts, storage/egress, other AI,
support costs and a chosen margin. Those inputs and the final budget are not yet
verified. Provider budget alerts alone are not a hard stop.

### Proposed review policy

This is an internal proposal, not yet published community rules or automatic
enforcement. The owner asked which content would be prohibited before activation.

- Prohibit child sexual exploitation, sexualized depictions of minors,
  pornography and non-consensual intimate material. Suspected illegal material
  needs the restricted escalation path, not casual preview or general API review.
- Prohibit credible threats, targeted abuse/harassment, hateful attacks and
  encouragement or practical facilitation of violence or self-harm.
- Prohibit scams, spam, malicious impersonation, dangerous illegal facilitation
  and unauthorized disclosure of other people's private information.
- Do not automatically prohibit family photographs, ordinary disagreements,
  religious/political views, grief, medical experiences, survivor testimony or
  historical accounts of war/abuse. Review context; a keyword or model flag alone
  is not grounds to suspend an account.

The intended human reviewer is the owner or an explicitly authorized moderator,
not OpenAI staff. An email should contain only a case reference. A private,
authenticated reviewer screen should show the exact flagged addition and minimal
necessary context, allow approve/keep hidden/escalate, record the reviewer/reason,
and provide an appeal route. Account suspension is a separate deliberate action
for serious/repeated abuse, not the default consequence of a flagged memory.

The moderation endpoint supports text/images, not direct audio; transcription
does not assess non-speech sounds. Image-only moderation does not cover every
text category, so a clean response is not proof that all prohibited conduct was
detected. Member reports and human escalation remain necessary.
[OpenAI moderation guide](https://developers.openai.com/api/docs/guides/moderation).

## Acceptance evidence

- **22 October memory-create regression:** fixed the restrictive memory SELECT
  policy rejecting INSERT RETURNING because its STABLE helper reread the not-yet-
  visible memory. Deployed approved migration
  `20261022213230_memory_insert_returning_safety`; same moderation/ownership
  restrictions, no additional grants. All 34 focused database tests pass, including
  a reproduction of the original failure. Live disposable rollback-only checks
  passed insert/update, family access, unauthorized-write denial, hide/restore,
  outsider-read denial and suspension; baseline row counts were unchanged. The
  owner then confirmed the same draft saved and its photo appeared on the phone
  ("worked"); this is owner-reported device acceptance.

- **22 October disposable photo-memory hide/restore:** the owner confirmed the memory
  was hidden in Heiro after applying Hide reported target. The supplied Safari
  snapshot shows report `4a08c3fa-94ea-410a-8002-4ae28c17b268` resolved with
  no open reports; the restricted reviewer preview still shows the photo, as
  intended. The owner then confirmed it returned with its photo after Restore.
  Subsequent read-only live audit confirms `hide` at 21:41:21 UTC and `restore`
  at 21:51:01 UTC, status `resolved`, and no current exact-target restriction.
  Device visibility is owner-reported. Explicit sibling visibility, audio preview,
  cached-copy revocation and reopening across reviewer sessions are not established
  by this result. No agent moderation action was applied.

- **22 October owner-operated memory report:** live metadata confirms the exact
  personal-memory report received at 11:39 South African time. Resend shows
  Delivered; Outlook Junk Email contains the matching report reference at 11:40
  and the revised Mac-launcher instructions. The owner confirmed the correct
  memory/photo preview and subsequent Dismissed status. The latter two are
  owner-reported acceptance, not fresh backend audit readback. No agent moderation
  action was applied. Hide/restore on this final-candidate path, audio preview,
  cached-media takedown and filtering remain unverified or unresolved. This
  supersedes the earlier memory-report acceptance uncertainty above.

- **18 October restricted review:** migration
  `20261018210222_content_report_case_preview.sql` deployed and local filename
  aligned to the server's migration-history version. Eight new database cases,
  six local HTTP/security cases, seven existing safety database cases, five
  existing operator cases, fourteen disabled-adapter mock cases and five alert
  worker cases passed (45 total). One additional browser test passed using separate
  desktop (1280x900) and mobile (390x844) sessions: safe untrusted-text rendering,
  explicit image preview, deliberate decision, unknown-author account controls,
  logout and no horizontal overflow. Screenshots inspected with a harmless Heiro
  logo fixture, not family media. No real provider screening request was made.
- **Live verification:** `content_review_rollback_qa.sql` passed preview, audit,
  checked decision and actual `anon`/`authenticated` denial. All fixture/report/
  outbox/audit changes rolled back. Before/after counts: zero reports and preview
  audits, four families, seven legacy memories, nine objects, six Auth users.
  Live grants read back as operator-only. Security-advisor comparison found only
  the expected new no-client-policy audit-table INFO; the 36 pre-existing callable
  definer warnings, public extension warning and leaked-password setting remain.
  Real Storage-backed media review, item-specific reporting from the phone and
  owner-operated review acceptance still need a disposable end-to-end check.

- **18 October local checks:** 14 new mocked screening tests passed, covering
  default-off behavior, bounded/unsupported inputs, flag/review decisions,
  malformed responses, network/HTTP failures, response limits and stalled headers
  or bodies. The existing five operator, five alert and three AI-cost tests also
  passed: 27 total, no skips. No real moderation request was made. Node syntax
  and `git diff --check` passed. These do not prove database publication gating,
  provider accuracy, human-review usability or profit margins.

The remaining entries are the earlier 13-14 October foundation evidence, not
fresh end-to-end screening tests:

- Database: all 60 tests passed, including scoped/private reports, member blocks,
  immutable attribution, operator permissions and deletion compatibility.
- Live disposable QA: reporting, blocking, hide/restore, suspend/reinstate,
  shared-media retention after contributor deletion and last-member cleanup passed.
  Final fixture cleanup returned to three families, 15 objects and six Auth users.
- Operator CLI: five unit tests passed; alert worker: five tests passed.
  Live `health` returned enabled/active, no failed/pending reports and
  `needs_attention=false`; client execution of that RPC is denied.
- Flutter: six safety widget tests passed; new safety files' analyzer scope clean.
  Physical-device and final TestFlight safety tests remain outstanding.
- Live Resend QA: provider ID `01a135ad-50ef-7849-b83b-ca49ba122e1c` delivered to
  `linebreakers@outlook.com`. Scheduled replay used the same ID without a duplicate
  email. QA report/outbox/invocation rows removed, original family/user/media
  counts unchanged. No automated screening was deployed or private archive sent.
