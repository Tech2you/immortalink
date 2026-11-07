# Private media backup checkpoint — 6 November 2026

## Authorization and scope

Ross approved R2 activation after reviewing its usage charges and absence of an
account-wide billing cap. He then approved bucket-scoped access, server-side
credentials, a 9 GB retained-copy ceiling, 1 GB copied per UTC day, and 30-day
recovery retention for deleted/replaced media and daily indexes. The expired
Supabase installation confirmation was reopened at his request and succeeded.

This batch adds an independent backup worker, private database controls and an
owner-dashboard status panel. It does not modify mobile app source, existing
family data, Apple products, TestFlight or the App Store draft. Existing unrelated
uncommitted work was preserved. No live source file was deleted or overwritten.

## Live configuration

- Supabase project: `vbzyvaylfdhwowdbodmk`.
- Local migration: `20261106090245_media_backup_launch.sql`.
- Remote migration: `20261106101647`, name `media_backup_launch`.
- These timestamps differ because the MCP tool assigns the deployment version.
  Reconcile migration history before a future CLI push; do not deploy it twice.
- Edge Function: `media_backup_worker`, **ACTIVE version 4**.
- Deployment bundle SHA-256:
  `adc15eaaf53fc5f354be644b31081a15bfd804a68cd4f0f0b2eddb1a2573038f`.
- Independently retrieved deployed entrypoint, core and transport sources exactly
  matched their local files. JWT verification is intentionally off for this
  scheduled worker; it requires a short-lived, single-use database-issued token.
  An unauthenticated live POST was denied with HTTP 401 / `UNAUTHORIZED`.
- Cron: `heiro-private-media-backup`, active, every five minutes,
  `select public.dispatch_media_backup();`.
- Cloudflare R2 Standard bucket: `heiro-media-backup-launch`, WEUR. No public
  development URL or custom domain. The credential has Object Read & Write
  permission for this bucket only. It is installed in Supabase server secrets;
  the protected temporary local credential file and directory were deleted after
  verification. No credential is recorded here or in source control.
- Lifecycle: `manifests/` indexes expire after 30 days. Current `objects/` files
  have no blanket expiration; the worker retires deleted/replaced versions and
  removes their recovery copies after 30 days.
- Cloudflare budget alert: **Heiro launch — US$1 usage alert**, threshold US$1,
  existing billing recipient retained. This is an alert, not a billing cap.

## Initial backup and restore proof

At **2026-11-06 10:33:58 UTC**, the worker finished the initial daily manifest:

| Check | Verified result |
| --- | --- |
| Current source objects | 50 |
| Source and verified backup file bytes | 59,903,893 |
| Current files missing a complete copy | 0 |
| Pending copies | 0 |
| Worker error after completed inventory | None |
| Independent R2 check | All 50 objects matched manifest size, SHA-256, MD5 and ETag metadata |
| Customer media downloaded for the verification tool | No; metadata and HEAD checks only |

The generated-data recovery drill exercised the real copy and restore routines:
65,536 random bytes were backed up, downloaded into a new isolated local folder,
and verified against their SHA-256 and MD5. Unauthenticated R2 access was denied
with HTTP 400 and the provider's explicit Authorization error. Generated remote
objects and local recovery files were removed afterwards.

The first hosted attempt exposed a missing global Buffer; the worker now imports
it explicitly, and a regression test covers a runtime without that global. The
full restore drill then exposed compressed metadata/HEAD length behavior; the
transport now requests identity encoding, disallows transformation on writes,
and rejects a missing length. The complete drill and final 50-file inventory
check passed with those corrections. Failed attempts retained their conservative
budget reservations; no usage counters were reset to bypass a limit.

This proves generated-file recovery and the current inventory's remote metadata.
It is not a byte-for-byte download of every family file or a full database-plus-
media disaster recovery rehearsal. Periodic copies are not a transactional
database/file snapshot. That larger isolated recovery exercise remains separate.

## Access and cost verification

Independent live SQL confirmed enabled controls, 9,000,000,000 retained bytes,
1,000,000,000 daily copy bytes and 30-day retention. Admission reserves sidecar
and daily-index overhead inside the retained ceiling. Anonymous and ordinary
signed-in clients cannot dispatch jobs or read the private ledger. The updated
live access audit returned zero findings across its ten catalog checks.

Local tests covered bounded downloads, checksums, recovery path validation and
no-overwrite behavior, single-use jobs, quota admission, deletion/reappearance,
and owner access. Real PostgreSQL concurrency testing admitted only one claim
for competing requests and kept simultaneous reservations within the budget.
Deno checks passed for the worker and verification/restore tools.

## Owner dashboard and operations

The Media recovery panel is published at
<https://immortal-ink-ba580-business.web.app> behind the existing owner/MFA gate.
Browser checks passed for healthy, paused, error, overdue, pending and unavailable
states, alongside access, logout, injection and narrow-layout checks.

Downloaded live files matched local SHA-256:

- `index.html`: `21bba6068895220178721e540a0d09fde9239edf98404660c88491bfbc8eeb7a`
- `dashboard.js`: `7660b58f294ce8d68829db31702af695da6aa781539d090e57f4afd0230dd50e`

Check this panel daily during launch. It does not send failure emails; the
Cloudflare usage alert is separate. Limits pause backup work without blocking
normal app uploads. They do not guarantee a maximum Cloudflare invoice.

The [media recovery runbook](../media-backup-runbook.md) contains recovery steps,
retention details, the stop switch, cost limitations and incident handling.
Remaining launch checks in the broader security review are not all completed by
this backup deployment.
