# Media takedown implementation constraints

Status: 23 October 2026. Deployed; disposable personal-photo integration passed.
The launch ledger contains the exact disposable run and cleanup evidence.

## Deployed integration

Migration `20261023101256_memory_media_retirement.sql` creates private durable
jobs for exact personal/legacy memory photo and voice attachments. The audited
Hide RPC records the restriction and jobs together. The local console/CLI runs
at most four fixed jobs per action using the official Storage move API. Remaining
or failed work stays in the review queue, including on resolved reports, with
an explicit retry control. There is no background scheduler in this version;
operators must finish/retry outstanding work rather than assume it ran later.

A service-only, exact-job trigger preserves ownership and updates direct
attachment references inside the Storage metadata transaction. Destinations
retain their original folder and extension with a random filename. The original
address is reserved against re-upload/reattachment. Restore is blocked while
retirement is pending or held and only lifts the restriction at the new address.
Shared references outside the reported memory, malformed parents, changed family
scope, ambiguous buckets and unsupported Storage modes are held for attention,
not silently relocated or expanded into an archive scan.

Only private, unversioned buckets are supported. Read-only production inspection
confirmed those settings on the five affected buckets and the expected metadata
keys. Current upstream unversioned Storage move uses rolled-back permission
probes, a byte copy/HEAD, then an in-place metadata update. The comparison allows
only HEAD's changed `lastModified`, preserving the original content fingerprint,
size, MIME/cache fields and ownership. This source inspection is NOT a substitute
for testing the integrated move against the actual deployed Storage API. The
personal-photo live canary below supplies that evidence for this deployment.

A short transaction advisory lock orders relevant metadata writes and the
existing account-deletion claim/finalization RPCs. It is never held across a
Storage/network request. If deletion has claimed the content first, retirement
waits while deletion proceeds; retained legacy paths are then rescanned. If the
move commits first, deletion snapshots the new paths. This lock serializes media
metadata mutations across families, so watch write latency and lock waits during
the live canary. Load/throughput characteristics are not proven by unit tests.

The quota exception is limited to the same-byte, same-bucket, service-only
approved move. It does not grant new allowance or relax ordinary upload checks.
Private tombstones/audit contain identifiers and metadata, not media bytes;
their retention policy still needs to be included in the wider retention review.

Local verification: 97 SQL tests passed, with the real-PostgreSQL case skipped
in that command and run separately. Real PostgreSQL 17 passed three concurrency
scenarios (delete first, move first, restore during a move; four Node test entries
including the parent). All 29 worker/CLI/console/browser/live-runner-guard tests
passed. Desktop and mobile browser screenshots were checked with synthetic
content. These are local tests; live evidence is recorded separately below.

Live canary `06ac3d34-c362-4024-863e-a1456d765459` passed after explicit deployment
approval: normal personal save/upload and family read, exact-memory Hide,
integrated Storage move/reference switch, hidden new-signing denial, warmed old
link denial after 56.16 seconds, identical-byte new-address Restore, sibling read,
and normal account-deletion cleanup. Existing media fingerprints, billing hashes
and public/Storage policies were unchanged after cleanup. All 20 function bodies
and new private grants/triggers were read back. The restarted Safari reviewer
showed a ready session, healthy alerts and no open reports. This does not prove
all CDN locations, production scale, or live legacy/audio end-to-end behavior.

## Rollout and recovery

1. Explicit approval for this migration and a disposable live canary was obtained.
   The previous isolated-experiment approval alone did not cover production logic.
2. Apply only this migration, read back definitions/privileges, then restart the
   private console. Completed for this deployment; source and live version match.
3. Run `--run-integrated` with tagged temporary accounts and the generated PNG.
   Prove the warmed OLD link stops returning bytes, hidden new-link requests are
   denied, Restore returns the identical bytes at the NEW address, and a sibling
   stays available. Verify cleanup and record live counts separately.
4. The personal-photo canary passed without moving real family media. Live legacy/audio and
   production write-latency coverage remain distinct from local fixture coverage.
5. On failure, stop operator retries, keep restrictions/jobs/tombstones intact,
   and investigate/repair forward. Do not reuse old names, drop tombstones or
   reverse-move bytes as a quick rollback. Account deletion remains available.

Whole-vault/member hides and suspensions do not retire an entire archive's links.
The console explicitly says this; the broader takedown/retention/filtering gates
are not closed by implementing exact-memory retirement alone.

## What the experiment proves

Hiding a personal memory denies its rows and new signed URLs but does not stop an
already-issued, warmed URL serving bytes. Moving the fixture to a new address
retired that old URL after approximately 50 seconds at the observed CDN location.
The new family-authorized address returned identical bytes. A separate service-
role move still satisfied the existing media ownership/scope helper on this
deployment. These do not prove a crash-safe moderator-side workflow, all Storage
versions, all CDN locations, legacy retention, full-quota behavior or old clients.

The experiment restored the memory BEFORE the owner-authorized move to isolate
Storage/CDN behavior. It did not pretend the owner could move an already-hidden
file, or that an admin move automatically updates application references.

## Intended behavior

- Hide denies normal reads immediately and starts durable retirement of ONLY the
  reported memory's direct attachments. An incomplete retirement must remain
  visibly pending and retryable, not silently become a completed takedown.
- Preserve bytes at a new, unpredictable address with equivalent authorization.
  Reviewers retain case-bound access, not an archive browser.
- Restore lifts the restriction at the new address. Never move the object back
  to an old address that an earlier signed URL can still name.
- No blanket archive scan, new AI processing, automatic memory deletion, new
  family allowance, subscription change or user impersonation.
- Files already saved on another device cannot be remotely recalled. Clearly
  separate that limit from preventing future downloads from the service.

## Design requirements and evidence boundaries

1. **Storage bytes and metadata are separate operations.** Use Storage APIs
   for byte operations, never raw SQL deletion of `storage.objects`. A successful
   move followed by a failed metadata rewrite must be recoverable. The local
   exact approved-move database trigger updates references atomically
   with the Storage metadata transaction, plus a durable service-only operation
   record. Still confirm integrated deployed API behavior before relying on object ID/ownership
   preservation. Do not broadly grant clients move privileges or disable RLS.
2. **Reference scope:** enumerate all direct references to each object and fail
   safely on an unexpected shared reference. Personal and legacy memory media
   have different path, table and ownership rules. A vault/member report does
   not authorize silently opening or relocating its entire archive.
3. **Quota:** `everroot_assert_storage_object_capacity` subtracts old bytes only
   for a same-name update. A move can be charged as additional storage, and an
   expired family may not be writable. Any maintenance exception must validate
   the specific service-role job, source object, destination, unchanged byte
   count and same billing scope. No general service-role or user quota bypass.
4. **Deletion:** `claim_account_deletion` snapshots actual paths and
   `legacy_media_references`. An unreferenced quarantine copy can otherwise be
   removed as private content, breaking retained grandparents' contributions.
   Coordinate using transaction locks and existing job state, and prove both orderings
   of deletion versus relocation. Never make account deletion depend indefinitely
   on a reviewer returning. A separate quarantine bucket alone is not a solution.
5. **Concurrent edits and path reuse:** prevent reattachment or re-upload to a
   retired path; otherwise the old URL can become useful again. Validate the
   preview revision, keep target restrictions active throughout a move, account
   for new attachments and duplicates, and prevent restoring midway through an
   incomplete operation. Check suspended contributors and family outsiders too.
6. **Retries:** handle lost API responses, process exit after a successful move,
   duplicate Hide, multiple reports on one target, partial attachment batches
   and a deleted target. Do not overwrite a destination or infer completion only
   from a successful HTTP response. Keep sensitive paths/keys out of browser
   responses, logs and email.
7. **Cache propagation:** observe the previously warmed URL, not just a fresh
   cache-busted request. Distinguish denied/not-found from 5xx/network failure.
   Do not label a move immediately globally revoked. A gateway or short token
   expiry alone does not retire existing cached bearer URLs.

## Verification before deployment approval

- Local SQL/state-machine tests for exact target and sibling preservation,
  service-only access, owner/scope preservation, quotas, stale snapshots,
  malicious paths, duplicate/lost-response retries and both deletion orderings.
- Personal and legacy photo/audio fixtures; shared legacy content survives
  contributor deletion before and after a retirement/restore.
- Full and expired-family fixture cases cannot create extra allowance or cause
  takedown to silently fail. Existing account-deletion tests remain green.
- A fresh explicitly scoped live test: hide while a signed URL is warmed, verify
  retirement after propagation, restore through a NEW link, and verify the OLD
  link remains unavailable. Clean up only generated fixtures and compare state.
- Ask for production deployment approval after passing checks. No production
  storage moves or policy changes were authorized by the disposable-test approval.

## Repeatable experiment

The runner defaults to help and requires `HEIRO_RUN_MEDIA_QA=1` plus `--run`
(historical infrastructure experiment) or `--run-integrated` (new Hide workflow).
It creates its own IDs and refuses existing account/path arguments. Credentials,
passwords and signed URLs remain in memory. A private JSON manifest in
`/private/tmp/heiro-media-qa-RUN.json` contains only fixture identity and bounded
status/header/byte-match evidence; use its `--cleanup` mode if interrupted.
Cleanup verifies server-side QA account tags and family membership, uses the
existing deletion endpoint even if retirement failed, then reconciles pending
jobs and clears only the matching synthetic restriction. The integrated worker
also rejects any returned move job outside this run's exact generated source.
Do not reuse this runner as an ad hoc real-content removal tool.

References: [Supabase Smart CDN](https://supabase.com/docs/guides/storage/cdn/smart-cdn)
and [Storage copy/move](https://supabase.com/docs/guides/storage/management/copy-move-objects).
API implementation reference: [upstream Storage object operations](https://github.com/supabase/storage/blob/master/src/storage/object.ts)
(current upstream source, not a pinned assertion about production version).
