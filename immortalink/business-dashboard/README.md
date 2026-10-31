# Heiro business dashboard

Private owner reporting, deployed on 30 October 2026 at:
https://immortal-ink-ba580-business.web.app

Uses the existing Supabase project `vbzyvaylfdhwowdbodmk` and a separate Firebase Hosting site in project `immortal-ink-ba580`. No app release or new paid analytics service is required. Usage consumes the existing providers' allowances; extra usage is not guaranteed to be free.

## Owner workflow

Sign in with the explicitly authorised existing Heiro account and its Heiro password. Owner access is separate from family membership or management. The browser retains tokens only in memory; closing or reloading the tab requires a new sign-in. Existing verified authenticator factors require verification. Sign-out revokes this browser session only.

- **Overview:** live account/family/paid-plan totals and actual uploaded file storage. Refresh fetches current aggregates. Daily history begins at installation; no history is fabricated.
- **Money & costs:** select the reporting month, add invoice expenses and bank receipts, or import an unzipped Apple financial report. Review the preview and enter the applicable exchange rate for every currency.
- **Monthly check-in:** enter MRR and contributor churn cohort counts from production reports. Leave unknown values blank. Mark costs complete only after entering all costs for the selected period.
- **Data & access:** explicitly exclude known testing accounts by email and testing families by ID. Exclusions apply to future counts, not historical snapshots or real app permissions. Test files continue to count towards billed storage.

The initial live snapshot was 8 registered accounts, 5 families, 0 verified production paying contributors, and 40,051,924 bytes across 43 stored files. These are a timestamped baseline, not current guaranteed figures. No account/family test exclusions were inferred or applied. No real finance records were created.

## Definitions and limitations

Accounts exclude deleted and anonymous accounts and explicitly excluded test accounts. A counted family must have at least one included member. Actual storage sums object size metadata across the project, including testing; it is not the sum of plan allowances and does not include database/egress/backups.

Paying contributors are distinct billing owners with an active, unexpired production family/legacy entitlement and a matching verified positive-price Apple event. Sandbox/TestFlight, expired entitlements and zero-price offers are excluded. Unknown-price plans are separately flagged. This reads the existing one-sponsor model; it does not implement the proposed multi-contributor storage buckets.

MRR is manually entered gross monthly recurring plan value (annual plans divided by 12), not Apple proceeds or cash receipts. Churn is lost members of the starting paid cohort divided by that starting cohort, not cancellation-intent events. Zero starting payers produces an unavailable rate. Activity metrics use the optional tracking described below. The production collection gate remains off until Apple privacy disclosures are updated; no past activity is reconstructed.

Apple financial reports use fiscal periods. Imports retain start/end dates and are assigned to a chosen reporting month. Compare costs for a comparable period. The dashboard result is Apple proceeds minus completed recorded costs, before income tax and accounting adjustments; it is not audited net profit. Cash payments are separate and never added to proceeds. Apple commission is already excluded from reported proceeds.

## Financial import

Sources verified during implementation:
- https://developer.apple.com/help/app-store-connect/reference/reporting/financial-report-fields/
- https://developer.apple.com/help/app-store-connect/getting-paid/download-financial-reports/
- https://developer.apple.com/help/app-store-connect/getting-paid/view-payments-and-proceeds/

Accepts uncompressed CSV/TSV/TXT up to 5 MB / 50,000 rows. Requires Start Date, End Date, Vendor Identifier, Extended Partner Share and Partner Share Currency. Recognises the four current `everroots.family.*` / `everroots.legacy.*` subscription products only. Add new SKUs to the parser when the product catalogue changes.

Extended Partner Share is already extended by quantity: do not multiply again. Negative returns remain negative. Original report files and per-row payloads are not uploaded; only per-currency totals, fiscal dates, references and a digest are saved. The report digest is canonicalised against row-order/filename changes. Database uniqueness blocks duplicate currency totals; imports are atomic. Overlapping imported/report-date proceeds are rejected to avoid regional/consolidated double counting. Manual entries without period dates cannot be automatically reconciled. Corrections remove the old dashboard records, then import their replacement.

## Isolation and access

`heiro_business` owns all new tables/functions; existing app/billing tables and policies are unchanged. Tables use RLS with no client policies and no client table grants. Public API functions are invoker wrappers around private routines that require an explicit owner row and a valid, non-revoked auth session. User metadata cannot grant access. Banned/deleted/anonymous accounts are rejected, as is a missing MFA assurance when a verified factor exists. No service-role key is shipped to the browser.

Only `rossstrauss1@gmail.com` was explicitly enrolled after user confirmation and exact verified-account lookup. No automatic family-owner-to-business-owner mapping exists. Owner enrolment/revocation is a trusted administrative operation, not available in the browser. The deployment owner grant is intentionally separate from reusable schema migrations.

CSP limits connections to the existing Supabase project; no framing, inline code, external scripts, persistent browser tokens or analytics SDKs. All imported text is rendered as text, never HTML. New functions read aggregates and billing metadata only, never memory text, photos or recordings.

`heiro-business-daily` runs `heiro_business.capture_daily()` at 00:10 UTC (02:10 South Africa). One idempotent snapshot per UTC date. The collector is not executable by app clients. Initial snapshot was taken manually; the first future scheduled execution has not yet been observed.

To disable the dashboard, revoke its owner rows and deactivate its specifically named cron job; leave unrelated app functions/jobs alone. Remove the separate Hosting site only if permanently retiring it. Existing app/public Hosting sites use different configurations.

## Validation and maintenance

- `node --test business-dashboard/tests/model.test.mjs business-dashboard/tests/database.test.mjs`
- `node business-dashboard/tests/browser.test.mjs`

The database tests use PGlite; set `PGLITE_MODULE` to its installed module if the default temporary test runtime is unavailable. Browser tests use bundled Playwright and installed Chrome; fixtures are synthetic, local and never published. Tests cover access denial, forged metadata, session revocation, MFA, production/test/expired/free-offer counting, null-vs-zero financial states, duplicate imports, negative refunds, currency separation, atomic rollback, XSS-safe display, sign-out and 320/390px mobile layouts.

Live verification: all five deployed static files matched local SHA-256 hashes and served expected CSP/cache headers; anonymous read/write/import requests were denied. Owner read/write/readback and denied non-owner/direct-table access passed in a rolled-back database transaction. The transaction used a temporary auth session with no issued credentials; it and the test financial records were rolled back. The user's actual browser password sign-in remains their acceptance check.

Existing billing/storage/ownership function hashes were identical before and after deployment. Supabase advisor warning counts were unchanged; six informational RLS-with-no-policy notices are expected for the deliberately private tables. Pre-existing project warnings (including leaked-password protection being disabled) were not modified by this dashboard task.

Deploy only this site:
`firebase deploy --only hosting --config firebase.business.json --project immortal-ink-ba580 --non-interactive`

Do not use the app or invite Hosting configuration for this dashboard.


## Optional app activity (30 October 2026)

The additive `lightweight_activity_tracking` migration introduces private `heiro_activity` tables and an independent best-effort RPC. It does not change memory saving, invites, relationships, billing, entitlements or media access. Existing owner access controls protect the reporting view and pause switch.

- DAU: distinct included accounts observed today (UTC). MAU: distinct included accounts observed across the last 30 UTC dates, including today. Returning accounts: observed on at least two dates in that window.
- First observed personal-memory saves and invitation acceptances: one first-observed date per account. These are NOT historical first-ever actions, a new-user conversion funnel, or subscription churn. About/profile scaffold records and legacy-profile contributions do not count as personal-memory activation.
- The client records only after a complete successful personal-memory save (including selected uploads) or a successful join RPC. The analytics endpoint checks ownership/recent creation for memory IDs and recent membership for joins; relationship invites are deleted by the existing join implementation, so it cannot verify a retained invite receipt. Subject IDs are validated but not retained in analytics tables.
- Data retained: account ID, UTC activity dates, first-observed action dates, test-build flag. No content, email, IP, device ID, file path, invite code, or screen recording is added to analytics tables. Infrastructure request logs remain governed by existing provider practices.
- Daily rows are pruned at 00:15 UTC to a 90-date window. Milestones remain until account deletion; account foreign keys cascade deletion. Aggregate snapshots contain totals only.
- `Settings > Usage statistics` stops future collection for that account on that device. Offline/stalled requests can be lost; this is observational coverage, not a complete audit log. Existing versions have no events. No backfill is invented.
- Client uses a 3-second timeout, maximum two attempts per action per UTC date, separate local completion state per account/build category, and no durable offline queue. Activity retries stop in background or after account change/disposal. The normal app never waits for this service.
- Build switch: `--dart-define=HEIRO_ACTIVITY_ENABLED=false`. Cable/testing builds must use `--dart-define=HEIRO_ACTIVITY_TEST_BUILD=true`; debug/profile builds are also test-marked. TestFlight release builds are NOT automatically detected: apply the flag for test-only binaries or explicitly exclude the tester accounts. Do not promote a test-flagged binary to production if production activity counts are needed; plan the final release build deliberately.
- Server pause: Data & access > Pause collection. This changes only `heiro_activity.settings.enabled`. It cannot open the separate production gate.

### Production release gate

`production_enabled=false` at deployment. Saved App Privacy notes list User ID and Other Usage Data for App Functionality, not Product Interaction for Analytics. Verify the current Apple label, add linked Product Interaction and User ID for Analytics as applicable, and publish the updated disclosures before enabling production activity. No Apple submission/draft changes are included in this task. The updated public privacy policy describes the new optional collection.

Once disclosures and release testing are complete, a trusted administrator may set `production_enabled=true, production_started_at=coalesce(production_started_at,now())` on the singleton settings row. Do not reset existing dates or turn this on just to make zero counts appear. The dashboard says “Not collecting” until production measurement actually starts. Test observations are shown separately under Data & access.

Additional checks: `node --test business-dashboard/tests/activity.test.mjs`; `flutter test test/activity_tracking_service_test.dart test/activity_memory_save_test.dart`. The full existing Flutter suite checks app behavior separately.

Rollback: pause collection, reinstall the pre-change build in place if needed, and restore the previous reporting collector/site from checkpoint `d31415cf15a69c27a765cdd110a57754e39c33ea`. Leave private analytics tables in place initially; no app data needs rollback or deletion. The previous build ignores these additive endpoints.

### Deployment and device evidence

- Migration applied as `20261030134354_lightweight_activity_tracking`; public collector wrappers are invoker functions, anonymous execution is denied, and activity tables have RLS with no client table grants.
- Dashboard and `https://heiro.app/privacy.html` published and independently byte-verified. No new analytics vendor, TestFlight upload, App Store draft edit or submission was made.
- iPhone updated in place from 1.0.0 (37) to 1.0.0 (38); `HEIRO_ACTIVITY_TEST_BUILD=true`, existing Apple purchase defines retained, code signature verified. Prior signed app retained at `/private/tmp/heiro-before-activity-build37.app` for local rollback while that temporary artifact remains available.
- Initial launch was blocked by the phone lock. After the user unlocked and opened Heiro, the live database showed exactly one test account active today, zero production rows, and `production_enabled=false`. No memory or invitation was created just for the phone check. First-save and invitation events have automated/local database proof; on-device end-to-end milestone checks remain optional user acceptance checks.
- Full Flutter run: 281 passed, 60 optional tests skipped. Additional memory-save integration checks and the 320px/200%-text opt-out screen check passed. Targeted tracking tests pass, including timeout/offline isolation, bounded retries, account-switch protection, persisted deduplication and opt-out.
- 31 business calculation/database tests passed, including 12 new activity/security tests. Dashboard browser checks and all three privacy-policy checks (including enlarged text) passed. New app files have no analyzer findings; pre-existing informational/deprecation notices in older app files were not changed.
- Live duplicate/pause/owner checks used a temporary auth-session row in a rolled-back transaction. No credentials were issued and the session and verification activity were confirmed absent afterward. The subsequent one test activity row is from the actual phone opening.
- Billing, join, leave, relationship-creation, account-deletion handoff and existing dashboard-auth function hashes were unchanged. Only the reporting collector gained activity aggregates. Security-advisor warning counts remained unchanged; three informational private-table RLS notices were added as expected. No activity-schema performance findings were reported.
- Apple classification reference checked on 30 October 2026: https://developer.apple.com/app-store/app-privacy-details/ (Product Interaction, User ID, Analytics and linked-account declarations). Verify the actual saved label before opening the production gate.
