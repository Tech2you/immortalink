# Content safety launch runbook

Status: 24 October 2026. Report/block/review foundation and Heiro Resend alerts deployed.
A text/photo screening adapter, separate permission controls, bounded queue and
queue-to-provider worker are tested locally. A later default-off app candidate
connects completed saves/edits to consent, sharing status and retry. It is not
deployed or active. Local exact-generation read
ceilings are now staged but are not deployed or active. A WASM decoder candidate and pre-download
resource limits pass local tests. Approved hosted diagnostics now verify three
generated single-JPEG requests, but the four-photo batch exceeds hosted CPU.
Temporary diagnostics were removed. The bundled single-image diagnostic now
passes locally and on the host; the complete hosted screening/publication path
remains unverified and disabled.
The later local split worker uses direct bounded HTTP photo responses, not
persistent image staging. With the bundled-loader candidate, the combined local
suite passes 318 tests. Packaging proof is limited to the generated-image
diagnostic, not full deployment, classifier quality or publication enforcement.
The later local sharing-request migration now adds server-observed new-source
eligibility and an account-bound explicit queue entry point. It is not deployed.
The later local candidate connects flagged text/photo generations to a
separate automatic-check queue in the existing review console. The newest local
candidate adds automatic-case alerts and durable first-publication notifications,
with bounded dispatch, duplicate prevention and private delivery-health status.
These are still disabled and undeployed; hosted delivery remains unverified. The publication
migration adds default-off read enforcement; its integration limits are below.
With this gate, the latest combined local database/image/worker regression run
passed 351 tests, with zero failures or skips, including 33 new sharing cases.
With the later publication ceiling, the combined run passed 388 tests with zero
failures/skips, including 37 new publication/concurrency entries. The
status/notification-guard checkpoint passed **413 tests**. The latest human-review
candidate passed **453 database/image/worker tests** plus **29 reviewer/server/browser
tests**. The delivery checkpoint passes **508 database/image/worker tests** plus
**30 reviewer/server/browser tests**, with zero failures/skips. The earlier default Flutter suite passed **198**, with 50 existing
purchase-config skips; the separately configured fake-StoreKit billing suite
passed **79** without skips, and focused consent/sharing tests passed **59**. No live or
phone screening behaviour is established by these local results.
An operator-only case-preview backend is deployed, with a local review console.
Item-level reporting/photo/audio preview and Hide/Restore are owner-confirmed.
Urgent cache takedown, adequate filtering and final-candidate verification remain.
This runbook is not evidence of App Store approval or legal compliance.

23 October access preflight: the SELECT-only
`supabase/verification/launch_access_audit.sql` returned zero findings across nine
checks on the live backend in a read-only transaction. Run it with authorized
database access before future releases; it reads catalog metadata and bucket
visibility, not family content. Do not auto-apply grants or revokes based on it.
Seven tests check that it detects unsafe grants/overloads, absent RLS, unsafe
views and public buckets. Its expected client signatures do not establish correct
authorization inside every function; existing advisor warnings and the filtering,
retention and operational launch gates remain. No live behavior changed.

Latest deployment checkpoint: exact-memory retirement is deployed as migration
`20261023101256`, with a successful disposable personal-photo canary. The
migration/worker makes Hide keep a durable
pending state until direct photo/voice addresses are retired; Restore uses new
addresses and cannot skip pending work. Resolved cases with unfinished work stay
in the queue. A failed move is retried explicitly by the operator, not a background
scheduler. Whole-vault/member reports do not relocate archive media. No files are
automatically deleted and payments/AI screening are unchanged.

The owner approved deployment, definitions/privileges were read back, the
integrated Storage/CDN test passed and all generated fixtures were cleaned up.
The old warmed link stopped serving bytes after 56.16 seconds in that test;
Restore used a new link and preserved identical bytes. Existing media/billing
fingerprints were unchanged. The restarted private console is ready.
Look for the media status separately from the report status,
use **Retry media retirement** if pending, and resolve any stated blocking issue.
Do not interpret a resolved report or a completed metadata move as instantaneous
global CDN revocation. See `docs/media-takedown-design.md` for rollback/recovery
constraints and the launch ledger for exact local test counts.

Post-deployment phone acceptance, 23 October: the owner confirmed **"Photo and
recording both work"** for the requested disposable-memory save/reopen check.
Ordinary photo display and voice playback therefore have owner-reported device
confirmation after deployment. No app update was required. This is not live
evidence of old-link retirement for voice or legacy attachments.

23 October cached-link evidence: an explicitly approved disposable live test
confirmed that Hide denies new links but an old warmed link still serves bytes.
Relocating a restored test photo retired its old address after about 50 seconds
at the observed CDN location; the new authorized link preserved the image. This
is an infrastructure experiment, NOT integration with the normal Hide button.
All temporary accounts, family data and files were cleaned up and baseline
counts/policy fingerprint verified unchanged. Do not manually move real memories
or describe Hide as revoking every old link instantly. The later deployment above
adds direct-memory path retirement, atomic reference updates and retry handling,
with local quota/deletion tests and live personal-photo proof. Whole-archive
links, live legacy/audio coverage and already-downloaded copies remain separate. See
`docs/media-takedown-design.md` and the latest launch ledger checkpoint.

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

Latest 23 October direction: after the comparison the owner selected the free
OpenAI text/photo moderation route. Infrastructure and human review are not free;
paid moderation transcription stays off. The new local-only permission migration
`20261023110215_content_screening_permission.sql` and nine tests establish
separate, revocable, policy-versioned permission, not permission for archives or
automatic reuse of AI-chat consent. It is NOT deployed. The getter/setter are
caller-only; the setter also requires the account UUID that opened the dialog,
preventing a delayed choice from affecting a newly signed-in account. Its exact
signature is `set_content_screening_permission(boolean,text,uuid)`. The worker
predicate also requires the exact permission revision.

The separate Flutter disclosure/withdrawal controls are now implemented locally
in `lib/widgets/content_screening_permission.dart` with 29 passing tests. The
`contentScreeningControlsEnabled` release switch remains false, hiding the new
settings action and making no RPC/provider calls by default. Lookup failures and
changed disclosures cannot grant permission; withdrawal can still be attempted,
and an unconfirmed save never claims checks stopped. The new permission table is
not itself a publication decision. Claim/finish coordination and work caps are
now staged locally as described below. The account-bound sharing request is
implemented locally; publication/read ceilings are also tested locally.
App integration and held-item review still need implementation before deployment. The app
and public privacy disclosure must match that final behavior
before this switch is enabled. Do not prompt users for a disconnected feature.
Withdrawal cannot undo an already-dispatched provider request. No live screening
is enabled, and audio/video remain explicit coverage gaps.

### Staged screening queue contract (not active)

Migration `20261023164835_content_screening_queue.sql` adds only new private
tables and worker-only functions. The permission, queue, processing-budget,
photo-ticket, sharing-request and publication migrations remain undeployed.
The last candidate adds restrictive read/update policies, generation triggers and
updates the two visibility helpers plus checked worker completion. It does not
replace existing policy definitions, quota/deletion routines or payment logic.
Enabling the controls table alone is not a complete filtering system.

The local `20261024111907_content_screening_share_requests.sql` candidate records
actual source INSERTs after the private server capture cutoff. It does not scan
or backfill archives. Client dates and feed flags cannot create an origin. After
capture starts, pausing the worker still records new inserts to prevent a
pause/resume exemption. Origins contain IDs/scope/timestamps, not copied content;
they cascade with source deletion and are inaccessible even to service-role
table queries. The existing disabled default has no capture cutoff.

The proposed app flow must use the authenticated session, never an actor UUID
selected by the client, and use this sequence:

1. `request_content_screening(kind, target, expected_user_id)` checks `auth.uid()`,
   the expected account, current ownership/contribution, membership and deletion
   state. The expected UUID is an account-switch guard, not the caller identity.
   It requires a trusted origin and records an explicit sharing request, then
   calls service-only `enqueue_content_screening` with the verified actor. The
   updated snapshot checks origins, scoped attachments, every contributor's
   current permission and restrictions. Duplicate requests cannot reset review
   or spend additional provider capacity. Origin generation binds the revision;
   source deletion removes its job/tickets and ID reuse rejects old results.
   The request itself does not change read permissions or make feed=false a
   private ACL for existing archives.
2. `claim_content_screening()` returns a job, exact revision and two-minute
   single-worker lease, without content. Call `prepare_content_screening` with
   `false` to reserve processing capacity and obtain source text and exact object
   metadata for bounded retrieval. The worker requires `processing_reserved=true`,
   checks bytes against that version, decodes and re-encodes photos, strips
   metadata, and never follows arbitrary external media URLs. For each ordinal,
   the split child calls `claim_content_screening_photo`, prepares that one
   image, then `finish_content_screening_photo` to recheck and bind its output
   digest/size. It returns a bounded JPEG directly, not a public or staged URL.
3. Immediately before one provider request, call `prepare_content_screening`
   with `true`. This rechecks source/permissions and reserves request capacity
   exactly once. Every photo ticket must be ready, current and unexpired; the
   parent must first match all returned bytes to the ordered database manifest.
   Do not dispatch if either check fails. A reserved request consumes capacity
   even if its network call fails. Withdrawal cannot recall an in-flight request.
4. `finish_content_screening` accepts only the current unexpired, authorized
   lease and a bounded `clear`, `review` or `pending` outcome. Rechecks reject
   stale content, withdrawn consent or deletion. Retry backoff is bounded and
   processing stops after three attempts or 24 hours. No raw provider response
   or content body is stored in the queue.
5. `content_screening_revision_clear` remains a service-only fresh-source check,
   not an end-user read permission. The newer publication candidate stamps the
   exact origin generation only after a valid `finish_content_screening` result.
   Read ceilings use that stamp, not the job's cached state or ongoing provider
   permission. Existing family/block/report authorization still applies.

### Local publication candidate (not deployed)

`20261024114120_content_screening_publication.sql` adds an independent default-off
`enforce_publication` switch. A configured capture cutoff is required, but that
constraint is not an activation checklist. Enrolled pending rows are readable
only by their identified authors, subject to existing authorization. Other family
members cannot read the memory, direct attachments/chunks, shared-vault media
metadata or obtain new Storage access through the tested paths. Candidate-row
policies retain owner INSERT RETURNING. Existing archives are not enrolled.

Source/ref/object changes rotate the origin UUID, already bound to every worker
snapshot; successful completion stamps that generation. Edits followed by reverts
cannot accept an old result. Parent ownership/family moves invalidate approval.
Pausing processing or withdrawing provider permission does not unpublish
unchanged approved content, and never releases pending content. Author FK nulling
after account removal and verified same-byte maintenance retain approval, so
approved shared Grandma contributions survive deletion without needing new
provider consent. Existing report restrictions still override publication.

Private media-address markers cover upload-before-reference and removed-reference
paths. New tracked bytes cannot become readable merely by attaching them to an
excluded archive. While enforcement is on, client UPDATE preflights deny overwrites
of these files and INSERT rejects old-address reuse even after deletion. Normal
composers already use fresh addresses. Trusted same-byte retirement and deletion
maintenance retain their scoped paths; they are not general quota/write bypasses.
Markers retain path/ID metadata after deletion, not media bytes; bounds, retention
and operational recovery must be approved before activation. Hosted Storage
preflight/byte/CDN semantics still require disposable integration proof.

The split-worker test now checks actual relative-visible rows with four generated
images and a mocked classifier, not just the worker's return value. Local
generation, role, mutation and real-PostgreSQL race tests cover the read gate.
These do not close private-draft UX, collaborative pending legacy edits,
edited-archive text/media handling, durable notification dispatch
or full hosted-flow gates. The later local notification candidate checks current
publication as described below; that change is not deployed. Do not enable either
switch, deploy the candidate or prompt phone testers until these dependent paths
are completed and separately approved.

### Local app status and notification candidate (not deployed)

`20261024120503_content_screening_client_status.sql` exposes a small fixed status
vocabulary through `get_content_sharing_status(text,uuid,uuid)`. Only the current
personal owner or legacy contributor/editor with existing family authorization
can inspect it. Foreign/deleted/restricted targets are indistinguishable. Expected
account and authenticated identity must agree. It returns no source, media path,
provider response or other person's identity. Refresh is read-only: it never
requests work, resets a review/lease/budget, grants consent or releases content.

The default-off Flutter integration opens status only after successful attachment
saves, with separate provider permission before a sharing request. A request
acknowledgement is not a publication claim: the client re-reads current status.
Decline/close sends no new request; timeout leaves the saved memory intact. Retry
uses the existing target, not a second save/upload. Held, unsupported, paused and
archive states do not silently resubmit. Account switches stop the request, and
the RPC independently verifies the captured account. The status dialog has manual
refresh, no periodic polling. Existing upload/payment behavior is preserved when
`contentScreeningControlsEnabled` is false, as it remains now.

The service-only `memory_notification_audience(uuid,uuid)` checks owner, family,
share intent, current generation and restrictions. It excludes blocked pairs,
hidden-feed vault recipients, suspended/deleting users and the author. The local
Edge handler supplies the actor returned by `getUser()` and uses only that
checked audience; malformed/error results fail closed before token lookup or
Firebase sending. The app also suppresses its immediate new-memory notification
when the screening flag is enabled. Family-joined handling is unchanged.

The later delivery candidate below supplies the first-publication outbox and
changes the handler to `memory_notification_route(uuid,uuid)`, which wraps the
same audience check and returns `direct` or `outbox`. Enrolled sources cannot
also use immediate dispatch after approval; unenrolled archives retain their
existing direct route. The tests use local SQL, fake clients and handler-wiring
assertions, not hosted FCM.
Node syntax checking passed; Deno runtime/typechecking remains a deployment gate.
There is no claim of an atomic database/network-delivery guarantee. Current
deployment must not use the changed handler without its new RPC migration.

Widget checks cover permission decline, account changes, timeout/recovery and
small-phone/tablet layouts at 200% text. End-to-end composer/device testing,
collaborative pending edits, archive edits and
voice/video alternatives are still activation gates. No real AI calls were made.

### Local automatic-check review candidate (not deployed)

`20261024162740_content_screening_human_review.sql` creates private cases for
current `HUMAN_REVIEW_REQUIRED` and `RETRY_LIMIT` outcomes, only with publication
enforcement enabled. There is no archive backfill, synthetic user report, provider
call, email or scheduler. The separate queue contains IDs, fixed reason/status
codes and timestamps, not private narrative or attachment links. It currently
returns at most 100 oldest cases per filter; pagination/retention remains an
operational gate. Source changes mark pending cases obsolete without deleting
the source or copying its content into a case archive.

After separately approved backend deployment, the console can opt into this
capability with `--screening-review`. Its default and the normal Finder launcher
remain unchanged/off. Do not ask testers to look for this staged section yet.
The local candidate supports:

1. **Automatic checks**: awaiting-review, kept-private, approved and closed/changed
   filters, plus exact check-reference lookup. These are not report references.
2. **Mark under review / Keep private**: records a reason and decision, but keeps
   the target unavailable to relatives. Kept-private cases remain revisitable.
3. **Approve this version for family sharing**: requires a recent text preview
   and each direct image's successful checked retrieval by the same reviewer,
   an exact confirmation reference, a reason and an explicit browser confirmation.
   The browser waits for each image to display. Preview logs record access, not
   proof of human attention. Approval releases only the unchanged generation and
   never removes existing report restrictions or grants provider permission.
4. **Close unavailable check**: allowed only when the source is no longer
   reviewable; never shares or deletes it. A changed/deleted source cannot cause
   an old case to open a replacement memory. Historical decisions remain visible
   by filter/reference, but obsolete versions have no content preview.

The server uses session/CSRF-protected routes and service-only RPCs, never accepts
a client-supplied file path or reviewer identity, redacts Storage metadata before
returning cases to the browser, and rechecks the source around image retrieval.
Ordinary app roles cannot inspect cases/audits or call these review RPCs. All
approval/edit/deletion decisions use the same media lifecycle lock. Provider
permission withdrawal stops external processing but does not suppress the
previously disclosed human review of a held source or give permission to process
it again. The UI/server disclosure must stay consistent with this distinction.

These actions now queue first-publication notifications in the later local
delivery candidate below, but no live messages are sent. User-report alerts still
use their existing independent outbox. Hosted dispatch proof and operator
retention/recovery remain required before activation. Unsupported audio,
video, oversized and unattributed sources still need an explicit alternative;
they cannot use this text/photo approval to bypass an incomplete check.

Local verification uses the staged SQL in disposable PGlite/real PostgreSQL,
mocked Storage/provider transport, and desktop/mobile browser automation. It
covers exact-scope approval, all-image preview requirements, lost membership,
deletion initiation, report restrictions, stale content and simultaneous decisions.
Six real PostgreSQL race cases pass. Browser hold/reopen/approve and family-row
readback pass on desktop and mobile sizes; original report/media-retirement
browser checks pass too. This is not hosted Supabase, actual provider moderation,
email/push delivery or phone acceptance evidence.

### Local screening-delivery candidate (not deployed)

`20261024170015_screening_delivery_outboxes.sql` adds private delivery configuration,
reference-only first-publication notices and per-case/per-device delivery records.
All new tables have RLS and no direct app/service-role grants; operations go through
explicit service-only RPCs. It does not replace any existing function, policy or
table permission, modify payments, scan archives or backfill notices.

- A new held generation creates one operator email job. Resolved, obsolete,
  unavailable or restricted cases are suppressed before sending. The email has
  only its case reference and directions for the separately enabled **Automatic
  checks** console; names, text, media and session links are excluded.
- The first exact-generation clearance/approval of an enrolled personal or legacy
  memory snapshots currently eligible registered devices. Each job stores a
  token hash, not the raw registration token. No author is notified. Dispatch
  re-resolves the token for the same recipient and rechecks current membership,
  blocks, feed hiding, deletion, restrictions, share intent, scope and generation.
  Approval does not grant provider consent or remove user-report restrictions.
- `dispatch_screening_delivery('email'|'push')` issues one pending job and queues
  a request to the fixed Edge URL with a 90-second one-use invocation. It never
  puts a reusable service/Resend/Firebase key in pg_net. The migration creates no
  schedule and performs no HTTP calls during installation. Hosted pg_net/gateway
  behavior has not been tested; local integration uses a recording stand-in.
- `send_screening_delivery` defaults off unless
  `HEIRO_SCREENING_DELIVERIES_ENABLED=true`. It uses the existing server-side
  `HEIRO_REPORT_ALERT_RESEND_API_KEY` and `FIREBASE_SERVICE_ACCOUNT_JSON` only after
  separate deployment approval. The new config entry uses `verify_jwt=false`
  because the one-use token is consumed through a service-only RPC; possession of
  an app JWT never authorizes sending. Credentials, recipients and provider URLs
  cannot be supplied through the request body. Nothing was configured live.
- Claim renews a two-minute exclusive lease. Firebase OAuth preparation occurs
  before fresh send authorization, so eligibility is checked after that delay.
  Invalid/expired tokens fail an indexed lookup before the shared media lifecycle
  lock; this reduces database contention, not a guarantee against network DDoS.
  The authorization permits an immediate send for 15 seconds, not a cached future
  send. HTTP calls have bounded bodies/deadlines and prohibit redirects. The fixed
  Firebase OAuth scope is messaging only. Errors return fixed codes, not provider
  responses or credentials. Family-joined sending remains unchanged.
- A generic push contains a family/event reference, not the memory text, author,
  attachment URL or screening outcome. APNs/Android expiry is zero: offline
  devices may miss the notice. Collapse/tag identifiers reduce redundant display
  but are not an exactly-once guarantee. The app's current read permissions remain
  authoritative when a user opens the feed.

New default limits, independent of the existing user-report and sign-up quotas:
20 email attempts and 200 push attempts globally per UTC day; 1,000 active delivery
jobs; 100 registered devices per first-publication notice; three send attempts and
eight leases per job. Queue/device overflow increments an omission counter without
failing a valid memory save. Counters are server-persisted and serialized. These
are provisional operating limits, not a profitability or delivery guarantee.
Validate combined Resend capacity, expected family/device counts and processor
limits before activation. There were no actual provider calls in these tests.

Email retries reuse `screening-review/<case-id>/v1` and an identical payload; recovery
stops 23 hours after the first attempt, within Resend's documented 24-hour key window.
Do not change the v1 payload during outstanding retries. Known retryable failures
honor Retry-After and exponential backoff. Push timeouts, malformed success and
expired in-flight sends become **uncertain** and are not blindly retried. Failed,
stalled, uncertain, omitted and budget-limited delivery is surfaced separately
from approval in the private console. **Accepted by provider** is not inbox/device
delivery. The review queue is the fallback, not an email receipt.

Notice deduplication is one first publication per source, not one per edit or
Restore. If an edit invalidates a queued initial notice, this candidate skips that
notice instead of following a different generation. A later edit approval does
not generate a replacement notice; new devices/members also receive no backfill.
This conservative no-retarget/no-edit-spam behavior and operational recovery need
to be included in the complete edit/activation acceptance checks. Source deletion
cascades its notice/delivery references; no memories are deleted by this worker.
Historical delivery retention and a carefully scoped manual recovery process are
still outstanding, so uncertain pushes must not be reset casually.

Deployment ordering, only after separate approval: required screening migrations
and this migration first, then compatible routing/delivery workers; verify worker
disabled states, secrets, gateway authentication and permissions before any
activation. The operator must have the matching `--screening-review` console
available before email delivery is enabled. The existing Finder launcher is still
unchanged. Approve and test a bounded dispatcher schedule separately; none is
created here. The app, source capture, publication enforcement, screening worker
and delivery switches require coordinated activation so no pending work is
mistakenly published or falsely announced. Do not enable this stage alone.

Local proof includes actual staged SQL, a recording pg_net stand-in, fake Resend/FCM,
exact approval and readback, eight real PostgreSQL dispatch races, current-access
rechecks, Hide/retirement/Restore, existing function/ACL/RLS preservation and
desktop/mobile console status. Node syntax checks pass. Deno runtime/typechecking,
hosted split decoder/Storage/classifier integration, actual email/push delivery,
old-client behavior and phone acceptance are still deployment gates. The final
database-to-network boundary is not atomic: a later permission change cannot
recall a generic message already handed to a provider.

Provider references: [Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys),
[FCM error handling](https://firebase.google.com/docs/cloud-messaging/error-codes),
[FCM message lifespan](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan).

Provisional limits are 1,000 active/review jobs globally and 20 per initiating
account, with 1,000 provider reservations per UTC day and 20 per initiating
account per UTC hour. They are independent of report-submission throttling and
do not prove a money budget or profitability. The global cap still applies when
different contributors initiate work. Counters survive restarts. Queue/budget
retention, family-level cleanup, operator recovery and health alerts still need
an operational policy before activation. The new source-delete hook cleans only
that target's screening metadata. No family content is automatically deleted.

The eligibility helper bounds text at 20,000 UTF-8 bytes and four direct image
attachments, each at most 12 MiB in stored metadata. These are not a validated
provider payload or permission to send original files. The disconnected adapter
now accepts four images plus text in one request, with a combined 10 MiB image
limit and 15 MiB serialized-body ceiling. Never send multiple requests using one
reservation. Voice/video, missing attribution/permission and restricted
sexual-content reports return fail-closed codes; they do not yet create a usable
held-item case. Do not activate until the alternative/review path is available.

The full local database/mock suite passed 166 tests; both separately enabled
real-PostgreSQL concurrency suites passed 11 tests. This includes existing media
retirement/deletion races and new consent, source-change, claim and budget races.
No production or provider request was part of those tests. See the launch ledger
for the outstanding integration and final-device gates.

### Local processing worker and deployment constraint

`scripts/content-screening/worker.mjs` composes claim, checked private-file
retrieval, explicitly supplied normalization, single-request authorization,
moderation and rechecked finish. It defaults off, has no scheduler/CLI and never
returns the provider's `clear` when database completion is stale or unconfirmed.
The backend permits only five processing/photo-ticket RPCs and the existing fixed
Supabase project. It rejects arbitrary URLs, redirects, weak/mismatched ETags,
wrong MIME/length/digest, oversized streams and stalled responses. No reviewer
session, sign-up key or browser credential is reused.

The reference `photo.mjs` uses pinned Sharp only for local Node verification.
It strips EXIF/XMP/ICC/IPTC metadata, applies orientation, resizes without cropping,
rejects animation or damaged input and leaves stored originals unchanged. Limits:
24 million input pixels, 2048-pixel output edge, 2 MiB per output JPEG, 24 MiB total
compressed source per memory. Native processing cache is disabled and concurrency
is one; these are not process isolation or target-host resource guarantees.
The caller must inject the runtime-appropriate normalizer explicitly; omission
returns `WORKER_NOT_CONFIGURED` before any claim or network request.

**Do not deploy this native decoder as a Supabase Edge Function.** Supabase
documents that native Sharp is unsupported and offers a WASM ImageMagick example.
The new local `photo_wasm.mjs` candidate uses pinned `magick-wasm 0.0.45`, header
checks and JPEG decoder downsampling before resizing. It rejects animation,
multi-picture JPEG, corrupt inputs, over-limit rasters and resource exhaustion;
applies orientation and strips metadata; and does not enlarge small pictures.
Its screening copies have a 1024-pixel output edge (changed locally on 24 October,
not the originals or the separate Sharp reference). JPEG shrink hints round up
to eighth-scale steps to avoid silently reducing output below the intended size.
It has a 48 MiB pixel-cache limit, 32 MiB allocation limit, no disk spill and an
800 ms cooperative per-image deadline. These do not cap total isolate memory or
guarantee interrupting every native decoding instruction. Large PNG/WebP may fail
closed, so a human-review/recovery path is still required, not a reduced upload
allowance. Stored originals and existing photo/audio features are unchanged.

`benchmark_photo_wasm.mjs` creates only random-noise fixtures and uses fresh child
processes. It includes retention of all outputs and JSON/base64 serialization.
On 24 October, the 1024-edge candidate measured four 2048x1536 JPEGs at 363 ms
cold CPU / 166 MiB peak process RSS; four 4032x3024 at 614 ms / 185 MiB; one
6000x4000 at 351 ms / 190 MiB. The earlier 2048-edge numbers remain historical
in the launch ledger. The hosted four-large-photo test below still FAILED.
This is local Node evidence, NOT proof of Supabase's 256 MB / 2-second CPU limit,
all image types, malicious worst cases, or moderation accuracy. No new hosting
was provisioned. Native and WASM paths both pass queue-to-mocked-provider tests.

### Processing budgets (local only)

Migration `20261023174955_content_screening_processing_budgets.sql` changes only
the staged screening prepare function and private screening tables. It adds no
upload hooks, publication grants or billing/storage-policy changes. Under the
existing lifecycle/control lock, the first prepare reserves these allowances:

| Scope | Source download bytes | Outgoing payload allowance | Attempts | Photos |
| --- | --- | --- | --- | --- |
| Global UTC day | 256 MiB | 256 MiB | 1,000 | 1,000 |
| Global UTC month | 2 GiB | 2 GiB | 10,000 | 5,000 |
| Initiating account UTC hour | 48 MiB | 48 MiB | 20 | 40 |

Outgoing allowance conservatively reserves one binary child response AND base64
for each maximum 2 MiB output, worst-case text escaping and wrapper overhead.
No cap was raised for split processing. Rechecks share the same lease's
reservation; new leases, edits and failures spend new capacity and receive no
refund. Monthly and global limits remain across worker restarts and different
contributors. Any exhausted dimension prevents all partial charges and prevents
downloads/decoding. Missing configuration fails closed. Downstream request limits
are also checked before downloads and again atomically before dispatch.
Limits queue/hold screening work; they do not delete files or change subscription
allowances. They bound this processing workload, not the entire Supabase bill,
unrelated media egress or reviewer costs. Bundled loading now avoids per-start
WASM downloads, but complete hosted flow and total transfer/compute cost remain
unverified. Profitability is not established.

### Split single-photo contract (24 October; local only)

`20261024092200_content_screening_photo_tickets.sql` keeps the existing staged
prepare/budget implementation private and exposes a wrapper that also requires
all expected photo tickets before dispatch. Tickets are private metadata only,
bound to parent lease, source ID, revision, ordinal and expiry, with immutable
completed size/SHA-256. At most four are retained per parent job; a new lease
replaces old ticket rows, and parent deletion cascades. There are no duplicate
image files or temporary Storage objects to clean up. Overall completed-job
retention and queue operations still need an activation policy.

`photo_job.mjs` prepares only one checked source per successful claim. Failed or
ambiguous work consumes the claim; a repeated request cannot decode again. The
parent's existing bounded retry obtains a new lease and processing reservation.
Both claim and finish recheck source, permission and deletion. A result cannot
be accepted after withdrawal even if its decode was already in progress.

`photo_transport.mjs` is a pair of factories, not a deployed entrypoint. The
child defaults off, accepts a bounded exact-shape lease/ordinal request with a
separate worker secret, and returns only a JPEG plus ticket/digest/revision.
The parent uses one fixed endpoint, deadline and size limits; it never retries
or follows redirects. Configure gateway JWT verification as an additional layer
before deployment; ordinary app credentials must never authorize this path.
No existing signup key or reviewer credential is reused. One in-flight decode
per handler isolate prevents overlap; global work limits come from the database,
not this process-local guard.

The parent holds at most four bounded screening copies in memory, matches every
output to the current manifest, and performs one aggregate classifier request.
Owned buffers are cleared on success/failure; runtime/HTTP copies are not claimed
to be securely erased. The old monolithic normalizer remains a local reference,
but cannot authorize photo dispatch against the new ticket schema.

The full local suite passed **308 tests, zero failures/skips**, including both
real-PostgreSQL concurrency suites. New coverage includes ticket replay, expired
leases, duplicate/concurrent finish, deletion/consent races, authenticated HTTP
shape/size/deadline checks and the full checked-object-to-mock-provider flow with
four native/WASM images. Existing storage/media/deletion regressions pass.
No actual provider calls, family content, production writes or phone changes
were involved. These tests do not establish real gateway behaviour, complete
hosted runtime limits, classifier accuracy or publication enforcement. All new
screening migrations remain undeployed and all activation switches remain off.

### Hosted diagnostic (approved; single-photo pass; batch CPU failure; removed)

`prepare_runtime_canary.mjs` creates three offline generated fixtures and a
temporary standalone deployment folder. It does not deploy. The checked template
lives under `supabase/verification/screening_runtime_canary/`, outside deployable
app functions. `--single-photo` generates the same three resolutions with one
decode per request; the default benchmarks a batch. The checked `run.mjs` requires
explicit `--approved-generated-only` operator opt-in after human approval. It
confirms that its separate function name is unused and the ten-function baseline
matches; a changed baseline requires inspection, not bypassing the guard.
It preserves and reads back gateway JWT verification and pins the exact operator
key's SHA-256 fingerprint for a separate `x-heiro-canary-key` header. Only the
fingerprint is written into the temporary configuration. It accepts only
whitelisted fixture hashes, rejects expired requests
after 30 minutes and returns numeric metrics only. It cannot access app database,
Storage or AI APIs in its code. Concurrent or repeated fixture runs on an isolate
are refused; this is a diagnostic restriction, not the production global budget.

The earlier completed hosted runs used API bundling and an integrity-checked, fixed
public CDN download of the pinned WASM binary because this Mac had no Docker
runtime. The 15,425,791-byte binary was independently matched to the installed
package. Those results do not verify production packaging.

A later local candidate uses `--single-photo --bundled-wasm` to copy that exact
asset into the isolated function's `static_files`, alongside license/notices.
The pinned JavaScript distribution is copied unchanged, avoiding the full npm
package's duplicate/unused binary assets. Its loader checks the fixed
local file's size and SHA-256, caches one initialization per isolate and fails
closed without a network fallback. The runner verifies the asset and a running
Docker-compatible engine before obtaining keys, then uses local CLI bundling
without `--use-api`. Missing packaging metadata or an unavailable engine stops
the run. The original diagnostic remains available only as an explicit mode.

Six loader/preparation tests and twelve fake-runner scenarios pass locally,
including actual pinned-WASM processing with no loader network request. The owner
then approved installation of Colima/Docker build tools. The dedicated profile
is limited to 2 CPUs/2 GiB RAM with only a disposable directory mounted, no login
service and no change to the default Docker context. It was stopped after use.
The generated-only local harness uses the CLI-pinned runtime with one-shot user
workers, 256 MiB memory and 2-second CPU limits. It builds offline, mounts only
the bundle at worker runtime and deletes its test container afterward. The final
bundle is 16,086,872 bytes, versus 47,760,710 for the initial whole-npm candidate.
`Deno.stat` is unsupported for this bundled static asset; supported `readFile`
is followed by the unchanged exact byte-count/hash checks.

The previously approved temporary hosted diagnostic was repeated at 10:51 UTC
on 24 October using this bundled candidate. Three generated JPEGs (2048x1536,
4032x3024, 6000x4000) returned 200 with processing wall times of 373/703/438 ms.
Authorization probes passed, cleanup and independent ten-function fingerprint
readback passed. Final observed lifecycle CPU was 1,383 ms; shutdown memory was
56,974,150 bytes, not peak memory. See `results-bundled-2026-10-24.json` beside
the canary. No app database, Storage or AI call occurred. Bundling avoids a
per-start CDN fetch, not all infrastructure/transfer costs. Complete hosted
split-flow, concurrent-load and adversarial coverage remain open.
The combined database, worker and image regression rerun passed **318 tests,
zero failures/skips**, including real-PostgreSQL concurrency. Those tests are local
evidence; the separate hosted pass is only the generated diagnostic. Screening
stays off and all new screening migrations remain undeployed.

The owner approved the temporary generated-image test on 23 October. Three
short-lived deployments ran between 18:19 and 18:26 UTC, each followed by removal:

- First attempt: client transport error during a rejected large-body request.
- Second attempt: empty-body unauthenticated and public-app-key requests both
  returned 401; the authorized 2,188,411-byte generated JPEG request timed out at
  the client's 90-second deadline, without image metrics.
- Third attempt: switched the upload client to curl; both rejection probes again
  returned 401, but the generated JPEG request timed out after 75 seconds.

On 23 October the larger two generated fixtures were not attempted after the first authorized
fixture failed. Scoped function logs do not identify whether request consumption,
the fixed binary download, or decoder initialization stalled. They do not prove a
CPU/memory-limit failure or successful decoding. Do not infer hosted performance
from the local benchmarks or increase budgets to mask this failure. That earlier
timeout record is not a successful performance test.

24 October continuation isolated the stages, using generated fixtures only:

1. The old diagnostic comparison rejected an authorized GET with 401 before
   decoding. After pinning the exact operator key independently of injected
   credentials, anonymous/app-key probes returned 401 and authorized GET/empty
   POST returned 405/413. No shared credentials or production auth changed.
2. Four 2048x1536 images with 2048-edge screening copies reached serialization,
   then failed HTTP 546: scoped lifecycle logs reported `CPUTime` at 2,064 ms.
3. With 1024-edge copies, four 2048x1536 images passed, but four 4032x3024 images
   failed HTTP 546 / `CPUTime` at 2,113 ms. The four-photo worker is NOT deployable
   as-is, even though all local image tests pass.
4. One photo per request passed for 2048x1536, 4032x3024 and 6000x4000 JPEGs.
   Processing wall times were 741, 594 and 1,099 ms respectively. The final
   isolate reported 1,188 ms lifecycle CPU and 52,860,758 bytes at shutdown, not
   a peak-memory guarantee. Processing wall time excludes upload/body consumption.

Sanitized identifiers, times, controls and metrics are saved in
`supabase/verification/screening_runtime_canary/results-2026-10-24.json`.
These results support investigating split single-photo preparation, not enabling
the current worker. They do not establish all-format, adversarial, concurrency
or classifier-quality coverage. No stored family originals were accessed,
changed or sent anywhere.

The later split design above binds direct HTTP outputs to the exact lease,
source and permission revision without persistent staging or new Storage rules.
Its bounded aggregate classifier request covers every photo and text together.
Do not loop unmetered classifier calls or scan existing archives. Complete hosted
runtime verification still needs approved disposable fixtures; production
deployment/activation is not authorized by the temporary diagnostic approval.

After each attempt, the diagnostic was absent and all ten existing functions'
IDs, versions, status, JWT settings and bundle hashes matched the pre-test
snapshot. The runner retained credentials only in process memory/stdin, not
argv, files or output. No database/Storage/AI request or screening activation
occurred. Missing cleanup/readback or changed existing functions makes the
operator runner fail even when image probes passed. The runner's eight fake CLI
tests exercise success, failed fixtures, unexpected authorization, JWT disabled,
cleanup failure, changed baseline, expiry and missing approval without networking.
No phone update is needed for this diagnostic result.

The 24 October combined local suite passed **258 tests, no failures/skips**,
including both real-PostgreSQL concurrency suites and eight fake-runner cases.
The initial sandboxed run aborted in Node on the local database tests; a complete
rerun with localhost permissions passed. No assertions were weakened. These are
local tests, not proof of complete deployed screening or classifier quality.

Supabase sources rechecked 24 October; other sources checked 23 October:
[Supabase image manipulation](https://supabase.com/docs/guides/functions/examples/image-manipulation),
[hosted limits](https://supabase.com/docs/guides/functions/limits),
[static-file WASM bundling](https://supabase.com/docs/guides/functions/wasm),
[OpenAI moderation input contract](https://developers.openai.com/api/docs/guides/moderation),
[Sharp metadata behavior](https://sharp.pixelplumbing.com/api-output/#keepmetadata).
This worker's tests mock the provider. They prove orchestration/failure handling,
not classifier quality, hosted performance or a complete filter.

23 October comparison: see
`docs/filtering-privacy-cost-comparison-2026-10-23.md`. The owner authorized an
assessment, not screening activation. The initial self-managed experiment
recommendation was superseded by the owner's later choice above. Apple's device
framework must not send detection flags to this review console. Voice AND video
remain explicit coverage gaps. No classifier was installed or run, and the cost
examples are sensitivity calculations rather than a measured budget.

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
plan. The 23 October direction above selects local work on free text/photo
screening only, not that earlier audio plan. Separate user disclosure/permission
is still required. Do not scan existing
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

- **23 October member block/unblock:** the owner replied "yes working" to the
  requested phone check that blocking Ross from Frank's Safety screen hides Ross's
  shared memories, and unblocking returns them. This is owner-reported acceptance,
  not independent device/backend inspection. No agent action was applied. This
  does not prove all legacy surfaces, offline/cached-copy revocation or moderator
  suspension. The harmless audio report's dismissal remains unconfirmed.

- **23 October reported voice-note playback:** the owner answered "yes" to
  hearing the disposable harmless voice-note recording after opening its report
  and selecting Open audio then Play in the private reviewer console. This is
  owner-reported acceptance, not fresh device/backend inspection. No report ID
  or dismissal confirmation was supplied. Close the harmless QA report with a
  recorded dismissal. Member block/unblock was subsequently owner-confirmed above;
  no moderator suspension, deletion or billing change was requested or performed.
  Cached-media and other launch gates remain open.

- **23 October resolved-case reopening:** the owner confirmed reopening report
  `4a08c3fa-94ea-410a-8002-4ae28c17b268` by reference after ending/restarting
  the private reviewer session. This is owner-reported acceptance; no fresh
  independent UI/backend inspection or agent moderation action was performed.
  Voice-note playback and member block/unblock were subsequently owner-confirmed
  above. Other remaining launch gates are not implied to pass by this result.

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
  Device visibility is owner-reported. Explicit sibling visibility, audio preview
  and cached-copy revocation are not established by this result. Cross-session
  reopening was subsequently owner-confirmed on 23 October above. No agent
  moderation action was applied.

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
