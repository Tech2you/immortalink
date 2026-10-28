# Scoped pre-launch security check - 26 October 2026

## Status and Scope

Owner authorized the family-growth deployment, disposable rollback checks,
build 27 and draft replacement, then separately approved both findings below.
The four named migrations and notification edge version 9 are deployed to
`vbzyvaylfdhwowdbodmk`. Screening remains disabled. No submission or release
is authorized. This is a targeted audit, not a guarantee against all attacks.

## Findings Fixed

1. Authenticated family members could directly alter the derived personal
   memory AI index under old write grants/policies, without editing the original
   protected memory. This could poison AI answers. Migration
   `20261026072750_harden_memory_index_client_writes.sql` revokes client table
   and column writes on both memory indexes. Source editing, authorized reading
   and trusted service indexing remain available. No existing index data changed.
2. Valid callers could repeatedly request the same family notification.
   `20261026072757_guard_family_notification_dispatch.sql` and
   `send_family_notification` v9 claim each event once, derive authorized actors
   and recipients server-side, and cap dispatch claims at 20 per sender and 50
   per family per rolling hour. Clients cannot execute the privileged claim RPC.
   Ownership, current membership, blocks, hidden vaults and account restrictions
   are checked. These limits do not block saving memories or cap member totals.

The edge handler bounds request size, token-page sizes, parallel sends and
provider timeouts; caller-supplied notification text/audiences are not trusted.
Dispatch is at-most-once and best-effort: claiming before provider delivery
prevents replay but an outage or time budget can leave a notification undelivered.
The underlying memory remains available. No real push was sent during these tests.

## Other Checks

- Twelve live Storage buckets are private with MIME allowlists and size limits;
  HTML, SVG, JavaScript and general document uploads are not allowed types.
  The live per-photo guard rejected oversized test metadata before the fixture
  was corrected to valid 10 MiB entries. Test objects had no uploaded bytes.
- MIME metadata is not malware scanning or proof of file contents. No antivirus
  service was added. Native image/audio/video display and the separate Storage
  origin reduce script-execution exposure, but decoder vulnerabilities and
  malicious media are not proven impossible.
- Invite-page parsing uses constrained codes and textContent/encoded links.
  The live public site returned CSP, nosniff, HSTS and no-referrer headers.
  Review-console tests exercised inert hostile text on desktop/mobile; the
  private console checks Host, Origin, CSRF, session lifetime and preview bytes.
  Report email helpers use fixed routing and plaintext content.
- Client-source scanning found no service-role or private API credentials in
  the checked client/public directories. This is not an exhaustive binary or
  infrastructure secret audit. Public RPC bodies were checked for identity,
  membership and fixed search paths rather than blanket-disabling definers.
- AI still treats user memories as untrusted context. Removing index writes is
  not a claim that all prompt injection is solved; AI has no SQL/code tool here.

## Verification

- Full default Flutter suite: 208 passed, 50 existing configuration-specific skips.
- Targeted database suite: 30 passed (growth, index privileges, access audit,
  notification guard). Notification helper/audience suite: 8 passed.
- Real PostgreSQL concurrency suite: 13 passed (growth and notification races).
  After splitting the approved growth deployment into two migrations, its
  12 behavior and 8 concurrency tests passed again. These counts overlap.
- Earlier scoped media/membership/deletion/safety regression: 37 passed;
  console/email helper checks: 26 passed; desktop/mobile XSS browser test passed.
- Deno type check passed; git diff whitespace check passed.
- Hosted `growth_security_rollback.sql` passed using temporary records in one
  transaction, ending in ROLLBACK. It exercised denied index/client-RPC writes,
  valid/repeated/other-author push claims, sender caps, more than 30 real members,
  legacy limits, consumed-invite rate accounting, full-storage admission/invite
  denial, and existing-member rename access. No email, AI or provider call ran.
- Before/after hashes of existing families, members, vaults, memories,
  entitlements and Storage rows match. RLS policy hashes match. Only the ten
  expected functions changed or were added. Local evidence is under
  `build/ios/release-27-evidence/` (ignored build artifacts, no credentials).
- Live access audit has zero findings for missing RLS, public buckets, client
  index writes, private-review access, unsafe views/search paths, anonymous
  privileged RPCs and unexpected authenticated privileged RPCs. Eight missing
  screening functions are expected because screening is deliberately undeployed.

## Residual Work

- Supabase reports leaked-password protection disabled, vector in public,
  authenticated security-definer exposure and private RLS tables without policies.
  Private deny-client tables and reviewed callable RPCs are intentional; these
  warnings were not blindly suppressed. Leaked-password protection requires
  a supported paid plan; no upgrade or paid service was authorized here.
- This did not certify administrator MFA, backups/recovery, every dependency,
  volumetric denial-of-service resistance or arbitrary uploaded-file safety.
- Build 27 is uploaded, Validated, export-compliance complete, assigned to
  Internal Beta and saved/staged in the existing six-item draft with manual
  release. Phone cold-start/photo/voice/tree acceptance remains unverified.
  Request-count reductions are not measured end-to-end speed improvements.

## References

- https://supabase.com/docs/guides/auth/password-security
- https://supabase.com/docs/guides/platform/ssl-enforcement
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
