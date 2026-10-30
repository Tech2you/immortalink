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

MRR is manually entered gross monthly recurring plan value (annual plans divided by 12), not Apple proceeds or cash receipts. Churn is lost members of the starting paid cohort divided by that starting cohort, not cancellation-intent events. Zero starting payers produces an unavailable rate. MAU and first-memory tracking are intentionally not instrumented in this version; they require a future app/privacy review.

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
