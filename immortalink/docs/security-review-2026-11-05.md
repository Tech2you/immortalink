# Heiro security review and launch implementation plan

Reviewed 5 November 2026 after the Supabase Pro upgrade. **The old media access bypass is now closed and independently verified.** The first launch-hardening batch is deployed. **6 November update:** private R2 media backup is now live, all 50 current files were verified, and a generated-file restore passed. See the [media backup checkpoint](checkpoints/media-backup-launch-2026-11-06.md). Full database-plus-media recovery, final phone checks and the remaining items below are distinct follow-ups.

This review covered the current Flutter checkout, deployed Supabase functions, database permissions and policies, storage configuration, authentication settings, backups, public email DNS, owner dashboard and local abuse/regression tests. The initial audit was read-only; the subsequent authorized implementations are recorded below. No customer memory contents or password hashes were retrieved. Existing uncommitted application changes were preserved. App Store and TestFlight configuration were not changed.

## Implementation status after approval

| Protection | Status and verification |
| --- | --- |
| Old media endpoint | `vault_view_bundle` v11 deployed; source read back; live unauthenticated request returns 401, public-token request returns 410 with `Cache-Control: no-store`. No database or media access exists in the replacement. |
| Password protection | Leaked-password rejection enabled; backend minimum changed from six to eight characters. Settings reopened and verified. Existing accounts/passwords not changed. |
| Text/index abuse | Six server text-bound triggers and atomic, rate-limited, unchanged-content-aware indexing deployed. `index_memory` v33 read back and matched to local source. Existing saved text is not truncated. |
| Total daily AI ceiling | US$2 per UTC day approved by Ross and deployed across chat, embeddings and transcription. `vault_ai_chat` v90 and `index_voice_note` v27 independently read back and matched. Private budget ledger and 30-day retention verified. |
| Owner dashboard | Mandatory authenticator verification enforced by the database; enrollment flow and budget display published. Downloaded HTML/JavaScript match the tested files and security headers. **Ross confirmed on 5 November 2026: “Dashboard opens after verification.”** This completes the owner-reported enrollment/login acceptance check; recovery is still unverified. Normal Heiro family access is unchanged. |
| Resend | Ross completed the Pro upgrade; billing/usage UI verified US$20/month, 50,000 transactional emails and no daily limit. Transactional/automation/inbox overage switches and domain add-on are off. |
| Email credentials | Current Heiro SMTP and safety-alert keys are sending-only and restricted to `auth.heiro.app`. The domain is verified. No keys were revealed or replaced. |
| Email suppression | Resend UI confirms automatic blocking of addresses that bounce or complain; no suppressions currently listed. No custom delivery-event webhook exists. |
| Database compute | Included Nano-to-Micro upgrade completed after Ross explicitly approved the brief restart. Dashboard confirms Micro / 1 GB memory; independent project status is `ACTIVE_HEALTHY` and a SQL read succeeded at 16:23:59 UTC. Reviewed additional cost: US$0/month. Spend cap remains enabled. |
| Media backup | Updated 6 November: private R2 copying and 30-day recovery retention deployed; 50 files / 59,903,893 bytes verified, generated-file restore passed. 9 GB retained / 1 GB daily copying guards and US$1 usage alert configured. See the media backup checkpoint; this is not an account-wide billing cap or full database restore proof. |

The US$2 control is a conservative application spending guard for these deployed handlers, not a provider account billing cap or a guarantee covering other uses of an API key, taxes or future price changes. It reserves before dispatch, includes a pricing margin, retains reservations on ambiguous failures, and stops new paid requests if the ledger is unavailable. Missing provider usage can cause an earlier pause. Renewed family quotas do not bypass it. It resets at midnight UTC (02:00 in South Africa), approximately US$60 for 30 days, or US$62 for 31 days. Existing per-family quotas and the separate 60-job/day transcription backstop remain.

Known follow-up: the chat handler consumes a family answer allowance before attempting the global spending reservation. A request paused by the global guard can therefore use one family answer without producing a model answer. This does not bypass the spending cap, but deserves a separately tested reservation/refund improvement; no quota lifecycle refactor was included in this batch.

Post-deployment verification used a single transaction which rolled back: normal text preserved, oversized text rejected, exactly-at-cap reservation accepted, over-cap reservation denied, duplicate refunds ignored, and client/owner access gates checked. A separate read confirmed zero test reservations/spend remained. No paid model request or customer-data mutation was used in this check.

Validation for this batch: 453 local database checks passed (14 concurrency cases skipped in that invocation), with the new real-Postgres concurrency suite passing separately; 13 budget/indexing/transcription-wiring tests passed; 33 chat handler/grounding checks passed; owner MFA database and browser enrollment/login/logout checks passed; nine refreshed access-audit tests passed. The audit's live catalog checks show zero unexpected client-callable privileged functions, unprotected client tables/views, public buckets, private-ledger access or client-writable indexes. Eight intentionally undeployed optional screening functions are still reported as missing. These are distinct checks, not one coverage percentage.

The local app source and native dependencies have not been changed by this security batch. The previously run 441-test Flutter suite remains the app baseline; a new phone login/upload/chat/restore smoke check is still needed against the deployed backend. No claim of complete exploit immunity is made.

## Findings and remaining implementation

### 1 Close the old media access endpoint before launch

**High priority; now retired.** The former `vault_view_bundle` version 10 verified a signed-in user, then used the privileged server client to read media and create download links. Its access check accepted the vault owner or anyone in the same family. It did not apply the current blocking, hidden-vault or content-safety checks.

Consequently, a blocked family member could still receive media links through this route. This finding does not establish access by anonymous users or unrelated families; both were denied in the reproduction. No real user's media was requested. **Scope clarification:** the synthetic fixture used the label “private-memory”, but `share_to_family_feed=false` is not by itself a private-vault permission in the current product. Ordinary same-family access to an unshared feed item is therefore not counted as a separate confirmed breach. The confirmed defect is the bypass of blocking/hidden-vault/content-safety enforcement.

The old endpoint was absent from the source tree and had no caller in the current app or located Git history. A retirement handler is now tracked in source so this route cannot silently be forgotten again.

**Implemented:** no caller was found in the current app or searched history. Replaced the route with a `410 Gone` response and independently verified it. Existing gallery paths were preserved. Keep a deployed-function inventory check in release reviews and never restore this unsafe handler during rollback.

Evidence: old downloaded handler SHA-256 `f3ea77d18a3572bfaee654f9fa76d6c3a0365395d0ad74d45b0d4c387cf25ef9`; four synthetic checks covered family/blocked/outsider/anonymous cases. Retirement deployment hash: `19bd81ef509d874404162197cbc5d63ef9e64784dc82e13d2b130a426b9f479a`. This demonstrates and closes a flaw; it is not evidence of past exploitation.

### 2 Strengthen password and owner account protection

**Initial finding, now corrected:** leaked-password rejection was off and the backend minimum was six. Both now match the stronger settings described above. Secure email change, secure password change and requiring the current password remain enabled. Client database roles have no access to `auth.users`.

**Implemented:** leaked-password protection and the eight-character minimum are saved and verified. A stronger policy can follow with matching app guidance. Still check sign-up, reset and existing-user sign-in on the phone; do not force a bulk password reset without evidence requiring one. [Supabase password security](https://supabase.com/docs/guides/auth/password-security)

At the audit, the one permitted owner account had **no verified MFA factor**. The deployed dashboard now requires enrollment and a verified authenticator session. Ross subsequently confirmed that the dashboard opens after verification on 5 November 2026. This is user-reported live acceptance; no setup key or verification code was requested or recorded. Recovery confirmation remains outstanding. This is separate from Supabase administrator MFA, which could not be verified in this review. Verify MFA and recovery for Supabase, Resend, the owner email, GitHub and Apple developer access too.

CAPTCHA is currently off. Integrate and test its token flow in sign-up/password recovery before enabling it in Supabase, so existing app flows do not become unusable. Keep server rate limits even after CAPTCHA is added.

### 3 Bound database text and indexing costs

**Initial finding, now corrected.** Storage quotas count stored media bytes. Before this batch, relevant text columns had no application-specific length constraint; memory count limits did not prevent repeatedly enlarging one existing record.

The previous `index_memory` handler split the entire input into 900-character chunks, deleted previous chunks and inserted replacements without an overall input/chunk ceiling, request rate limit or unchanged-content shortcut. It did not itself call a paid AI model, but repeated or oversized indexing could consume database space and processing capacity.

**Implemented:** limits apply to new or changed text on six tables; existing unchanged text is grandfathered and nothing is truncated. Indexing uses canonical database content, bounded input/chunks, an unchanged-content hash, caller rate limits and atomic replacement. Direct-request, rollback and concurrency tests passed. The live handler delegates to the service-only database function after checking the caller's read access.

### 4 Add a total AI spending limit and review transcription capacity

**Existing safeguards are useful:** server-side family/user allowances, short model output limits, request timeouts, per-user burst limits, verified audio duration and transcription deduplication. Separate account allowances could add up across many abusive accounts. The newly deployed total daily budget now addresses that missing application-wide guard.

**Implemented:** atomic reservation before chat, embedding and transcription calls, conservative settlement, duplicate-settlement protection and fail-closed behavior. The owner dashboard shows current reservations/settled estimates and warning/paused states. Push/email budget alerts remain a follow-up; no new alert messages were sent. Existing per-family quotas remain.

There is already a global transcription backstop: it reserves 120 seconds for every new job against 7,200 reserved seconds per UTC day. That permits **at most 60 new paid transcription jobs per day across the app**, even when clips are short. Cached results do not start another paid job; unstarted work can release its reservation. This is conservative cost protection, but it could interrupt a successful launch. Make the budget visible/configurable and plan accurate reservations or a queue before increasing it. Do not simply remove the cap.

Supabase Spend Cap is enabled. It applies to covered Supabase usage, not OpenAI, Resend or every separately billed add-on/compute charge. Reaching it can restrict service, so alerts and controlled degradation are needed alongside the cap. [Supabase cost control](https://supabase.com/docs/guides/platform/cost-control)

### 5 Verify media access after blocking or unsharing

The app issues signed media links lasting one hour. A previously issued link is a bearer credential: rechecking a cached image for changes is not the same as rechecking family membership or privacy permissions.

Pro enables Smart CDN. Supabase documents that cached signed-URL responses may remain available after token expiry until cache expiry, and revoking a token does not itself purge those cached responses. Object updates/deletions invalidate CDN caches asynchronously; browser copies are separate. This is a provider-documented risk combined with the current app's URL design, not a live customer-data exploit test. [Supabase Smart CDN](https://supabase.com/docs/guides/storage/cdn/smart-cdn)

**Implementation:** test with synthetic media across block, leave-family, unshare and takedown events, including a warmed cache. For content requiring current authorization at every request, use an authenticated delivery path that checks it before serving bytes. Otherwise define and communicate the permitted revocation window. Shortening a signed token alone does not prove immediate revocation. Preserve private buckets and originals; do not delete memories to invalidate a cache. Previously downloaded copies cannot be recalled.

### 6 Establish recovery for actual photos and recordings

**6 November implementation:** Ross approved the destination, usage charges, scoped access and retention. Private versioned R2 copying is enabled, the initial inventory is complete, and isolated generated-file recovery passed. The [checkpoint](checkpoints/media-backup-launch-2026-11-06.md) supersedes the original unapproved proposal below. The owner dashboard now reports backup health; it does not send failure emails. A complete isolated database-plus-media recovery rehearsal remains outstanding.

Daily database backups are present, including a backup at 01:18:03 UTC on 5 November. A restore was not attempted. **Database backups do not contain the actual Storage photos, videos or audio**, only their database records. An independent media backup was not established by this review. [Supabase backups](https://supabase.com/docs/guides/platform/backups)

**Implementation:** configure a restricted, encrypted, versioned media backup destination; choose retention that respects account deletion; monitor failed copies; and test restoration of a small synthetic family plus its files in an isolated environment. Verify database recovery separately. Budget for backup storage and transfer. Never run the recovery drill over the live production database.

**Original 5 November proposal, subsequently approved and implemented:** use a separate private Cloudflare R2 Standard backup bucket with daily manifests and distinct object-version keys, copying new/changed files rather than re-downloading the entire archive every day. Do not assume a plain mirror protects against accidental deletion. Use a 30-day recovery window, deletion handling consistent with the privacy policy, separate backup credentials, monitored copy failures, and a synthetic restore drill before relying on it.

Cloudflare's published Standard rates, checked 5 November 2026, include 10 GB-month free, then US$0.015 per GB-month, with separate request allowances/charges. At 50 GB of total retained backup data, storage alone would be about US$0.60/month; at 100 GB, US$1.35/month. These estimates exclude taxes, job hosting, request overages and Supabase source egress. Retained old versions count toward total backup size. Set a budget and alert threshold before activation; a low storage estimate is not a hard spending cap. [R2 pricing](https://developers.cloudflare.com/r2/pricing/)

### 7 Finish email and infrastructure readiness

Public DNS contains a DKIM record for `auth.heiro.app` and SPF/MX records at `send.auth.heiro.app`. However, `_dmarc.heiro.app` and `_dmarc.auth.heiro.app` resolve through parking CNAMEs without a DMARC policy. SPF/DKIM records alone do not establish that delivered messages pass alignment.

**Implementation:** domain verification, sending-only/domain-scoped keys, automatic suppression and the Pro quota are now confirmed. Publish a proper DMARC policy initially in monitoring mode, then strengthen it after legitimate senders pass alignment. No custom delivery-event webhook exists yet. TLS is currently opportunistic; assess enforced TLS for authentication emails with controlled delivery tests. Owner MFA, usage alerts and actual sign-up/reset/invite delivery tests remain. No test email was sent in this review.

Supabase email authentication currently permits 100 emails/hour with a 60-second interval per user. Sign-in/sign-up is limited to 30 requests per five minutes per IP. Check that these settings fit the launch forecast and the confirmed Resend allowance before increasing either.

The included **Micro** upgrade is complete after explicit approval of the restart. The infrastructure page shows 1 GB memory, project status is `ACTIVE_HEALTHY`, and database queries succeed. The US$2 guard, its retention job and denied client access were checked again after restart. No disk expansion, spend-cap removal or optional paid add-on was selected. Current inspected database/disk usage does not justify a larger paid compute tier by itself.

### 8 Harden session storage without disrupting sign-in

The Flutter initialization uses the package's default session persistence. The installed package stores the session through SharedPreferences rather than a custom Keychain/Keystore adapter. This concerns session tokens; it is not a finding that raw passwords are stored there or exposed over the internet. Device sandboxing still matters.

**Implementation:** migrate tokens to platform secure storage, preserve existing sessions during migration, and verify refresh, logout, account switching and device backup behavior. Treat this as a scoped app hardening change with a rollback plan, separate from the urgent endpoint fix.

## Protections verified in the current review

- All 12 inspected storage buckets are private, with file-size and MIME allowlists. Database triggers enforce family capacity with locks against simultaneous uploads, and visual uploads have additional photo/video limits. These are server protections, not just disabled UI buttons. MIME allowlists are not malware scanning.
- The live access audit found no client-accessible base tables without row-level security, no client-accessible views bypassing it, no client writes to derived indexes or private review relations, and no security-definer functions without a fixed search path. These checks do not override the separate privileged endpoint flaw.
- Apple verification tests reject wrong accounts, families, products, environments and invalid signatures; movement and expiry logic fails closed on uncertain Apple responses. No real purchase, cancellation or contribution move was performed.
- Audio validation measures the file duration, rejects invalid/overlong input, and does not start a second paid call for duplicate/in-flight work.
- The dashboard's owner-only data is in a private schema; its browser session is held in memory and cleared on logout. The public site and dashboard return restrictive security headers. Owner MFA enforcement is deployed and Ross confirmed successful dashboard access after verification. Recovery remains to be confirmed.
- The checked source and local Git history contained no matching usable credentials for the scanned key formats. The public Supabase anonymous key is expected; it is safe only with correct server policies. A pattern scan cannot establish that every possible secret is absent.
- Report-alert, daily business-summary and activity-retention jobs are active. Production activity collection is disabled; enabling it requires checking the release flags and privacy disclosures. Optional automatic content-screening code exists locally but is not deployed; it must not be advertised as live protection.

## Test evidence and its limits

| Check | Result | What it establishes |
| --- | --- | --- |
| Local database test suite | 447 passed; 13 concurrency cases initially skipped | Local migration and policy behavior, including some optional undeployed modules |
| Separate temporary PostgreSQL concurrency run | 77 passed, no skips | Concurrent quota, relationship, contribution and other transaction behavior in the test database |
| Flutter suite with phone purchase configuration | 441 passed | App regression checks with the intended purchase flags |
| Purchases-disabled configuration | 3 passed | The separate build configuration remains guarded |
| AI, notification and report handlers | 48 passed | Access, consent, limits and delivery guard behavior under fixtures |
| Dashboard/activity tests | 32 passed | Local dashboard and activity behavior |
| Apple, audio, consent and deletion tests | 62 passed, 1 ignored | Synthetic verification/retry/deletion behavior; optional live Apple OCSP check was not run |
| Deployed old media handler reproduction | 4 passed | Two confirmed bypass cases and two denied cases using synthetic fixtures |
| Dart dependency advisory lookup | 145 versions checked, no matches returned | No known OSV findings returned for those exact versions; not a complete native/Deno dependency audit |
| Credential-pattern scan | 623 current text files and 1,233 historical text blobs checked | No matching usable secrets in the scanned formats; binary/large-file coverage is limited |

Do not add these counts into one coverage percentage; some suites overlap. Earlier test failures caused by incompatible purchase flags or a missing local test database dependency were resolved by running the correct configurations, without changing app source.

Nine of the ten initially downloaded deployed function sources matched their local counterparts after normalizing a trailing newline. The orphan media function was the exception and is now retired. The launch-audit allowlist has been updated for the reviewed relationship/contribution and owner-security RPCs; eight optional screening RPCs remain undeployed. Blanket revocation would break valid features.

Advisor warnings about the public `vector` extension and callable privileged functions need dependency-aware review. Deny-all internal tables can legitimately have row-level security enabled with no client policies. Performance index suggestions should be validated with query plans, not applied wholesale just before launch.

The durable deployment record is [launch security checkpoint](checkpoints/launch-security-2026-11-05.md). Detailed temporary evidence remains in `/private/tmp/heiro-security-audit-20261105/`, including downloaded function sources, catalog definitions, the synthetic media reproduction, scan summaries and test logs. Do not treat temporary files as a backup. No customer media is included.

This was a code/configuration review with local adversarial tests and rolled-back live validation, not a forensic breach investigation or a guarantee against all attacks. Backup restoration, actual-device sign-in after hardening, administrator MFA and a complete native/transitive dependency audit remain validation work. Resend settings and the post-restart database health have now been checked live.

## Order of implementation and launch checks

1. **Completed:** retired endpoint, stronger password settings, owner MFA enforcement, text/index bounds, US$2 guard, Resend Pro/overage verification and included Micro upgrade. Retain the deployed-function inventory in future reviews.
2. **Owner login accepted:** Ross confirmed dashboard access after authenticator verification. Still confirm recovery, ordinary app sign-in and provider administrator MFA separately.
3. **Media copying completed 6 November:** restricted R2 copying/retention and generated-file restore are verified. Follow up with a full database plus file recovery rehearsal in an isolated environment; never overwrite production to test it.
4. **Access/privacy follow-up:** test warmed media links after blocking/leaving, decide the supported revocation window, and make any delivery-path change in a separately tested release. Migrate mobile session storage with login-preserving tests; integrate CAPTCHA before enabling its server setting.
5. **Email and operations:** DMARC monitoring, controlled signup/reset/invite delivery tests, failure/usage alerts, and a written response procedure for reports, failed backups and quota exhaustion. Revisit the conservative transcription backstop using actual launch demand.
6. **Final acceptance:** phone and production smoke checks with dedicated test accounts: unrelated-family denial, private/shared memories, blocking, invitation acceptance, photo/audio uploads, AI consent/quotas, Apple restore/move, account deletion and logout. Use synthetic data and approved test purchases only.

Deploy one bounded change at a time, read it back, run its specific checks and keep the previous deployable version available. Preserve customer data and avoid emergency blanket policy/index changes. Any previously unsafe endpoint must remain closed during a rollback. App Store submission changes should be a separate explicit step after these checks.
