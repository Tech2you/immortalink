# Launch content checking and recovery notice — 5 November 2026

## Authorized scope

The owner selected the free OpenAI text/photo checker with separate user
permission. Recordings and videos retain report/block; attached text/photos
still require checking. No paid transcription is added for moderation.
The owner has a Cloudflare account. R2 activation and backup costs are not yet
approved. App Store submission/draft must remain untouched.

## Published

Heiro terms and the original-copy/recovery clarification were deployed to
Firebase Hosting, and public bytes matched the generated files. Apple standard
EULA and mandatory consumer rights are retained; no blanket liability waiver.
The subsequent automatic-check privacy paragraphs are also published. They
describe separate permission, new/edited text/photos, no scanning of untouched
archives, and report/block handling for recordings/videos. Public HTML and CSS
are independently checked against local generated files.

## Current state — enabled 5 November 2026 at 22:35 South African time

The nine October 23–24 screening migrations and three November 5 follow-ups were
installed atomically as remote migration `20261105181629`, named
`content_screening_launch_disabled`, after the owner approved the reopened
Supabase confirmation. Do not push those twelve local files again as new work.
The ordered source manifest is recorded below.

The parent worker, isolated photo worker and delivery worker are deployed.
The photo worker requires gateway JWT authentication plus an internal worker
secret; the parent and delivery workers validate short-lived, single-use
database-issued invitations. Runtime and database checking, publication, worker
and delivery switches are enabled. The exact new-capture cutoff is
`2026-11-05T20:35:53.115596Z` (22:35:53 South African time). No archive backfill
was requested. Material edits follow the existing rechecking rules.

Build 50 was installed in place on the owner's iPhone. The owner confirmed that
existing feed/photos open and a new shared memory saves normally. The owner then
confirmed **all current testers have build 50**. Its permission/checking UI is
enabled. This confirmation removes the old-client compatibility gate; no further
permission is needed to activate the already-authorized checking scope.

The generated-only live tests below passed. All 42 generated Storage objects
were removed through Storage. The separately approved, guarded database cleanup
then removed four synthetic accounts, two families, four memories and their
checking records. Independent readback confirmed zero fixture users, families,
memories, objects, jobs, reviews, permissions and runs. Global work/cost counters
were preserved. The cleanup and guarded activation SQL are retained under
`/private/tmp/heiro-screening-live-qa/` for this session's evidence; they are not
general-purpose deletion or deployment scripts.

`content-screening-recovery` runs once per minute. It invokes only the existing
bounded dispatchers, which make no network requests without enabled switches
and eligible work. Post-activation recovery succeeded at 20:37:00 UTC; the
independent 20:37:23 UTC readback confirmed all switches enabled, no pending
delivery/attention, no public buckets and no anonymous/authenticated grants on
private checking tables. Both enabled parent/delivery HTTP endpoints reject
missing invocation tokens with 401. No reusable credential or content is stored
in the cron command.

The ten pre-existing functions retain their identities, source hashes, JWT
settings and update timestamps. Platform-reported version numbers moved together;
do not describe versions as unchanged. No real family content was sent to OpenAI
in QA, and no email or push was sent by the live delivery canary. App Store and
TestFlight remain untouched.

## Implemented behavior

- Twenty photos supported, including memories with recordings/videos attached.
- Full text up to 60,000 Unicode characters in bounded chunks; all provider
  requests reserved before work; all chunks must clear. Photos sent once, with
  **one image per provider request**. Requests equal the greater of text chunks
  and photos; a 20-photo memory reserves 20 requests, not one.
- Image previews max 1024 edge/512 KiB, one image per isolated worker request.
- Existing permission rechecked before download, dispatch and publication.
- Recording/video-only items use no moderation API call; reporting remains.
- Untouched archives excluded; material edits enroll and require fresh sharing.
- Single-use, short-lived database-issued worker tokens; service-only RPCs,
  fixed destinations, default-off dispatch, global run and processing limits.
- Consent, save/status and bounded foreground refresh UI; no duplicate upload.
- Verified pinned WASM decoder; defaults remain off for unconfigured deployments.
- Maximum 1,000 provider requests/day and 20/user/hour, 1,000 pending jobs and
  20/user pending; worker and decoding budgets are also enforced. Large batches
  can exhaust the hourly allowance. Failed/ambiguous work never auto-approves.
- Safety review launcher enables the separate automatic-check queue. A flagged
  item requires deliberate review; recordings/videos are not automatically judged.

## Evidence

### Initial installation checks (before final hosted fixes and activation)

- Full screening database/worker/image/adapter suite: 372 passed, zero skipped.
- Final migration-chain real PostgreSQL concurrency suite: 5 passed (four
  scenarios plus parent test): whole-batch budget reservation, material edit,
  permission withdrawal and single worker dispatch. Initial failures were test
  expectations about returned fields/bigint representation, corrected before
  the passing run; no production behavior was changed to satisfy them.
- Focused Flutter tests: 62 passed; analysis of the five changed checker/legal
  files reports no issues. Web privacy/terms checks: 5 passed.
- Both production entrypoints and the staged delivery function pass Deno checks.
- Hosted generated-only image diagnostic passed at 18:00–18:01 UTC: 2048x1536,
  4032x3024 and 6000x4000 images, 1.58–2.45 seconds client elapsed. Unauthorized
  requests were rejected. Temporary diagnostic removed and existing ten
  functions unchanged. This proves the hosted decoder, not the whole provider
  and publication flow.
- While disabled, the deployed parent returned 503 SCREENING_DISABLED; the
  unauthenticated child returned 401 before worker execution.
- `supabase/verification/content_screening_launch_rollback_qa.sql` passed live:
  owner insert/read, unaffected archive, private queue access denial, consent,
  20 photos plus a recording, oversized output rejection, family/outsider
  isolation, material edit, withdrawn permission, recording-only zero-provider
  requests and edited-archive permission. All synthetic rows/control changes
  rolled back. Postcheck confirmed zero jobs/origins/permissions/runs and all
  switches off. No media bytes were uploaded, fetched or sent to a provider.
- New internal tables have no PUBLIC/anon/authenticated grants, and zero Storage
  buckets are public. Advisor additions are intentional deny-all internal tables
  and the four authenticated permission/status/request RPCs; their authorization
  paths are tested. Existing vector-in-public advisory is unchanged.

### Final hosted and phone verification

- Two independent 20-photo memories completed actual download, isolated decoding,
  per-image provider requests, whole-batch reservation and checked publication.
  A separate generated 24-megapixel JPEG also cleared. A synthetic text/photo
  case was flagged, opened in the real private console, explicitly held,
  reopened and approved; the database recorded `HUMAN_APPROVED`.
- Live authenticated RLS verification after approval: the synthetic family member
  could read all three first-family memories; an unrelated account could read
  none. The earlier pending-content/permission/revision rollback tests remain
  recorded above. This is not a test of every possible CDN cache scenario.
- Hosted fixes: explicit Node Buffer imports, strict acceptance/normalization of
  balanced quoted Storage ETags, and one image per moderation request. The
  provider returned a 400 for the former multi-image request. The temporary
  diagnostic function was removed after diagnosis.
- The reviewer now accepts successful 204 responses from its preview audit RPC;
  initialization avoids competing initial queue requests. Actual generated-photo
  preview and decisions passed in a desktop/mobile browser check (390px viewport).
- Latest targeted regression runs: 20 adapter/batch checks; 12 database/concurrency
  checks; 50 worker/image/transport checks; 22 reviewer/server/browser checks.
  Hosted-runtime Buffer regression and Deno entrypoint checks passed. The earlier
  372-check suite above predates the final hosted fixes; these targeted runs cover
  the changed paths. The final app scope passed 93 focused Flutter tests. Analyzer
  had zero errors but 55 existing warnings/information messages, not a clean run.
- The final two dispatcher regression checks passed using the existing isolated
  PGlite runtime; the first invocation lacked its local module mapping and did
  not execute tests. `git diff --check` passed after the final documentation edits.
- Deployed delivery worker consumed a legitimate one-use invitation for the
  already-approved synthetic case, returned 200 `NOT_ELIGIBLE`, and recorded
  `NO_LONGER_ELIGIBLE` with zero email/push attempts. This proves non-sending
  eligibility enforcement, not real mailbox delivery or notification receipt.
- Post-activation owner acceptance passed: “Permission shown; memory shared
  normally.” Independent metadata-only readback at 20:40:28 UTC confirmed one
  permission record, one clear job and one current published generation. No
  caption, image, password or personal content was opened. Scheduled recovery
  succeeded at 20:40 UTC. This completes the new-memory permission/sharing check.
- Notification delivery is separate: that readback showed one provider-accepted
  push and 23 queued deliveries, with zero health attention. This is not proof
  of receipt on every device or a fully drained notification queue. The existing
  bounded dispatcher processes one item per channel per minute; review its
  backlog before increasing launch notification throughput.

## Installed source manifest

1. `20261023110215_content_screening_permission.sql`
2. `20261023164835_content_screening_queue.sql`
3. `20261023174955_content_screening_processing_budgets.sql`
4. `20261024092200_content_screening_photo_tickets.sql`
5. `20261024111907_content_screening_share_requests.sql`
6. `20261024114120_content_screening_publication.sql`
7. `20261024120503_content_screening_client_status.sql`
8. `20261024162740_content_screening_human_review.sql`
9. `20261024170015_screening_delivery_outboxes.sql`
10. `20261105172337_content_screening_launch_compatibility.sql`
11. `20261105173918_content_screening_worker_dispatch.sql`
12. `20261105180100_content_screening_material_edits.sql`

Subsequent installed migrations (local name -> server history version):

- `20261105195157_content_screening_single_image_requests.sql` -> `20261105195436`
- `20261105200216_content_screening_recovery_schedule.sql` -> `20261105201622`

Do not push the earlier twelve local files again as pending migrations.

## Remaining launch operations

1. Owner operates the private safety-review queue and checks delivery health.
   This is not a staffed moderation service or independent uptime monitoring.
2. No independent media backup exists yet. Cloudflare account availability is
   confirmed, but R2 activation/costs are unapproved. Prepare private destination,
   deletion handling, retention/cost bounds and isolated restore proof separately.

Disabling publication enforcement is not the emergency stop: it would remove
the checking read ceiling. For an incident, pause worker/delivery dispatch while
retaining enforcement and saved private work, then investigate. Do not delete
family content or reset budgets as a recovery shortcut.
