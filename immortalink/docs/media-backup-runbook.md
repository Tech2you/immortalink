# Heiro private media recovery

Deployment evidence is recorded in `checkpoints/media-backup-launch-2026-11-06.md`.

## Scope and guarantees

Supabase database backups do not contain Storage file bytes. The independent
Cloudflare R2 Standard bucket `heiro-media-backup-launch` stores versioned copies
of Heiro's photos, videos, voice recordings and avatars. It has no public domain
or public development URL. The worker's key has Object Read & Write access to
this bucket only. App users cannot invoke backup controls or read the ledger.

The worker runs from Supabase, so the Supabase service-role key never goes to
Cloudflare. R2 credentials live only in Supabase server secrets. The job reads
the fixed Supabase project and writes only to the fixed R2 account/bucket.
Authentication uses a short-lived, one-use database-issued token. Request bodies
cannot choose files, hosts or destinations. No media contents, object names,
credentials or private URLs are logged by the worker.

Every five minutes, a bounded batch copies up to five new or changed objects.
Each object is limited to 50 MiB. Transfers have timeouts and no automatic
network retries. Interrupted jobs retry later; ambiguous attempts keep their
daily budget reservation. SHA-256, Content-MD5 and remote size/ETag checks prevent
failed or truncated copies from being acknowledged as protected. Existing
verified immutable copies are reused after a crash.

This is periodic media recovery, not a transactionally consistent database/file
snapshot. A new file deleted before it is copied cannot be recovered here.
Queues, outages and copying limits can delay protection. A database restore must
be reconciled with the available file versions in an isolated environment.

## Copying and cost safeguards

- 9,000,000,000-byte retained-copy ceiling. Admission reserves room for file
  bytes, up to 16 KiB per sidecar and 31 daily indexes of up to 8 MiB each.
- 1,000,000,000 source bytes reserved per UTC day, including uncertain failures.
- At most 288 runs per UTC day, five objects per run and 50,000 retained versions.
- The private owner dashboard shows retained file bytes, pending current files,
  last complete inventory, paused/error state and an overdue warning at 36 hours.
- Cloudflare has a US$1 monthly usage alert to the existing billing recipient.

These are backup-job safeguards, **not an account-wide Cloudflare billing cap**.
Other account activity, compromised credentials, delayed metering/lifecycle work,
request overages and taxes can still create charges. Source transfers also count
toward Supabase egress. Reaching a guard pauses new backup copies; it does not
block normal Heiro uploads or delete source files. Review limits deliberately as
the service grows; do not silently increase them.

R2 Standard currently includes 10 GB-month and separate request allowances.
Check the current [R2 prices](https://developers.cloudflare.com/r2/pricing/)
and [budget-alert limitations](https://developers.cloudflare.com/billing/manage/budget-alerts/)
before changing retention or volume.

## Retention and deletion

Current source versions remain protected while they exist and the service is
operational. Deleted/replaced versions are marked retired when observed missing,
then become eligible for backup-only deletion after 30 days. Cleanup never
deletes the current Supabase source. Reappearance during cleanup is requeued.
The Cloudflare lifecycle rule expires `manifests/` indexes after 30 days; it does
not expire current `objects/` copies. Provider delays or a paused job can delay
cleanup. Account deletion continues through the existing app flow; old recovery
copies are restricted to disaster recovery and age out under this policy.

Do not restore deleted accounts or content back into production without
reapplying deletion and access decisions made after the recovery point.

## Recovery procedure

1. Pause affected app writes only if necessary for a real incident. Preserve the
   original source, database backup and R2 copies; never test by overwriting live
   production data.
2. Create a temporary **read-only**, bucket-scoped R2 credential using the owner
   account. Keep it in a protected environment file, never in source control or
   command arguments. Revoke it and remove the local file after recovery.
3. Obtain the required fingerprint from a daily manifest or version sidecar.
   `scripts/media-backup/restore_one.ts` downloads one version into a new local
   directory, verifies SHA-256 and MD5, and refuses to overwrite existing files.
   It names local files by fingerprint, so stored object paths cannot escape the
   chosen directory. The JSON sidecar contains the original bucket/path mapping.
4. Validate the restored file and its matching database record in a separate
   environment. Restore only approved content with correct ownership and privacy.
5. Reconcile subsequent deletions, then plan and approve production recovery.

Example with an installed Deno runtime and an owner-created protected env file:

```sh
deno run --env-file=/private/path/read-only-r2.env \
  --allow-env=HEIRO_R2_ACCESS_KEY_ID,HEIRO_R2_SECRET_ACCESS_KEY,HEIRO_R2_ACCOUNT_ID,HEIRO_R2_BUCKET \
  --allow-net=adbac5c130c03a9d10f46d805da51629.r2.cloudflarestorage.com \
  --allow-write=/private/path/new-recovery-directory \
  scripts/media-backup/restore_one.ts FINGERPRINT /private/path/new-recovery-directory
```

The environment file uses `HEIRO_R2_ACCESS_KEY_ID`, `HEIRO_R2_SECRET_ACCESS_KEY`,
`HEIRO_R2_ACCOUNT_ID`, `HEIRO_R2_BUCKET`. Never use an account-admin token.
`check_r2.ts` is a generated-data write/restore/delete drill, while
`verify_inventory.ts` reads metadata and performs HEAD checks without downloading
family media. Do not run repeated drills as a substitute for investigating errors.

## Operations and rollback

Check **Media recovery** in the owner dashboard daily during launch. Paused,
unavailable, overdue or attention-required status needs investigation. This panel
does not send email failure alerts. The Cloudflare budget alert is independent.

An authorized database operator can stop new work without changing app behavior:

```sql
update media_backup.control set enabled=false where singleton;
```

Keep the cron entry installed: disabled dispatch does no copying. To recover,
investigate the redacted worker stage/error, verify the key and budgets, then
reenable the control. Never reset usage counters just to bypass a limit. Rotate
only the bucket-scoped R2 key if compromised, update the server secrets, redeploy
the single worker and verify a generated-data restore. Retain the old recovery
copies until the replacement is proven. Removing the app feature is unnecessary.
