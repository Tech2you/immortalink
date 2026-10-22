# Launch reconciliation - 23 September 2026

Checkout: `25eb867`, clean before this documentation update. Build 1.0.0 (12)
delivered via Transporter earlier today; last observed Apple state: processing.
Live project inspected again: `vbzyvaylfdhwowdbodmk`.

Scope: read-only deployed function/source and database catalog inspection, local
code inspection, Flutter tests and local storage-cleanup tests. No production
writes, deletion, purchases, invitation acceptance or account changes performed.
No claim of a complete penetration test, legal clearance or phone lifecycle test.

## How to read the status

- **Already implemented:** code is present; not necessarily deployed or proven
  end-to-end.
- **Deployed and verified (inspection):** freshly retrieved live implementation
  or configuration confirms the stated property, not the entire feature lifecycle.
- **Needs testing:** evidence is insufficient; this does NOT mean missing.
- **Genuinely missing:** a specific required control or deployment is absent in
  inspected code/configuration. Existing surrounding functionality may work.

## Corrected feature status

| Item | Status | Current evidence / remaining work |
| --- | --- | --- |
| Account deletion UI and endpoint | Already implemented + deployed | UI invokes deletion; live `delete_account` v9 exists and verifies the user through Auth. Do not describe deletion itself as missing. |
| Apple cancellation warning | Already implemented | `lib/widgets/account_deletion_billing_notice.dart`, wired in `vaults_screen.dart:2650`. Warns deletion does not cancel; provides Manage Apple subscription and Settings fallback. Included in build 12. Phone acceptance test remains. |
| Preserve remaining family's shared data | Genuinely missing in deployed owner-delete path | Live v9 deletes family-wide relationship and legacy rows for owner families, then attempts family-group deletion. Current checkout removed those broad deletes. Requires deliberate owner-transfer/retention policy and testing before deployment. |
| Paginated storage deletion | Already implemented locally; deployment missing | Local `storage_cleanup.ts` passes 3 tests; live v9 lists only 1,000 per folder and ignores storage errors. Local index includes `vault_voice`; live list does not. |
| Complete/retryable deletion | Genuinely missing in inspected implementation | Local and live deletion are sequential, without a durable job/resume mechanism. Local five-bucket prefix cleanup still needs an ownership inventory for legacy/family paths. Do not blanket-delete shared media. |
| Server-enforced fresh reauthentication | Genuinely missing | UI password check exists, but live endpoint only verifies an existing session with `getUser`; no recent-auth proof enforced there. |
| Apple purchase validation | Deployed and verified (inspection) | Live v7 authenticates user, checks family ownership, fetches transaction from Apple, checks bundle/transaction/product, then writes entitlement server-side. |
| One subscription assigned to two families | Deployed and verified (index inspection) | Unique index on non-null `apple_original_transaction_id`. Useful duplicate-assignment protection, not initial purchaser proof. |
| Purchaser-to-app-account binding | Genuinely missing in inspected flow | Client `PurchaseParam(productDetails: product)` at service line 165 supplies no account binding. Live v7 has no `appAccountToken` or equivalent caller-binding check. Different issue from verifying that a transaction is genuine. Legacy restore needs an explicit policy. |
| Apple server notification signatures | Deployed and verified (inspection) | Live notifications v6 uses Apple's SignedDataVerifier, pinned Apple root, signed notification/transaction verification and authenticated Apple refetch before database access. This hardening is already done. |
| Refund/renewal/restore lifecycle | Needs testing | Code exists. No current end-to-end purchase, restore, cancellation, refund or out-of-order notification test conducted here. Handler updates rows without a visible event-order guard; replay/ordering deserves targeted tests. |
| Sandbox and production routing | Needs testing / implementation review | Both live Apple functions choose one environment from configuration. Concurrent review-sandbox and production support is not demonstrated. No secret values fetched. |
| Join family after subscription purchase | Deployed and verified (logic inspection); needs phone test | Live join RPC adds membership; entitlement RPC checks current membership and reads the family's plan, not a purchase per member. No purchase-date restriction on members. Test UI refresh, secondary-family selection and pooled limits. |
| Main relationship invite acceptance | Deployed and verified (inspection) | Live `join_family_by_relationship_invite` locks the unused/unexpired invite, checks member limit, preserves owner role and handles membership/relationships atomically. No real invite consumed. |
| Old invite compatibility path | Needs testing/security review | Older `join_family_by_invite` also exists, but differs from primary path (including role upsert and no explicit member-limit call in its body). Check execute grants and table triggers before concluding it is an exploitable bypass. |
| Family-wide AI and transcription limits | Deployed and verified (definition inspection) | Live limits: Free 20 AI / 600 transcription seconds; Family 500 / 7,200; Legacy 1,500 / 24,000. Family usage aggregation is shared. Enforcement under concurrent requests remains a separate test. |
| Storage allowances | Deployed and verified (definition inspection) | Free 500 MiB; Family 10 GiB; Legacy 50 GiB. These are product quotas, not provider dollar caps or profit guarantees. |
| Client entitlement editing blocked | Deployed and verified (grant inspection) | Authenticated has SELECT only on entitlement/event tables; no anon grant returned. Full RLS predicate audit remains. |
| Private storage and RLS presence | Deployed and verified (catalog inspection) | All 12 buckets private with size limits; no public-schema base table without RLS returned. This does not prove every access policy is correct. |
| Pull-to-refresh | Already implemented | Home/feed, personal/shared/legacy vault RefreshIndicators present. Final device checks needed. Tree gesture behavior not changed by this audit. |
| Six-hour offline cache | Already implemented + automated coverage | `RecentCache` defaults to 6 hours / 250 MiB, scopes disk index by account and clears on user changes. Automated offline/cache tests passed. Airplane-mode, expiry and permission-revocation device checks remain. |
| First-account setup and tree settings | Already implemented + automated coverage | Relevant onboarding, invite, settings, offline tree and vault tests passed. Full feature matrix remains manual/device work. |
| AI accuracy disclaimer | Already implemented | `vault_companion_screen.dart` presents an acceptance checkbox and reminder. Do not list all AI warnings as missing. |
| Third-party AI disclosure/permission | Needs targeted completion review | Inspected chat disclaimer discusses accuracy/identity, not third-party recipient/data transfer. Searches found no explicit provider-consent UI. Audit chat, icebreakers, embeddings and transcription together before declaring compliance. |
| Rebrand/domain/email migration | Genuinely not done; awaiting name/domain | Preserve existing email behavior. Change sender/domain authentication, links, branding and public policy only after the new identity is chosen; regression-test old/new links. |
| Supabase paid plan | Genuinely not upgraded | Fresh organization response: `free`, `tier_free`. Upgrade is a business/configuration decision, not a missing app feature. No purchase made. |
| Resend plan, delivery and DNS | Needs verification | Not checked in Resend this pass; user reports current email flow works. Do not call it broken or change it during this audit. |
| Global spending safeguards | Needs verification | Tier quotas exist, but provider budgets, overages, independent duration checks and global stop thresholds are not certified by this pass. |
| Privacy policy/terms and legal clearance | Needs updating/verification | Existing policy remains old-brand/early-beta. Must align processing disclosures as well as name. No legal sign-off inferred. |
| Media backups, restore, incident response | Needs verification | Not executed or inspected in this pass. Do not assume database backups prove media recovery. |
| Apple agreements/metadata/reviewer access | Needs verification | Upload success does not prove tax/banking, production product availability, privacy labels, reviewer account or public release readiness. |
| Remaining feature/security matrix | Needs testing | Every other unchecked row in the submission checklist retains this status; no blanket claim that those controls are absent. |

## Fresh advisor results

- Leaked-password protection remains disabled:
  [Supabase password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- Vector extension remains in public:
  [Extension warning](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public).
- 23 authenticated-callable privileged functions flagged:
  [SECURITY DEFINER guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  This count is not 23 proven vulnerabilities. Review authorization individually;
  do not disable required membership helpers indiscriminately.

Apple requires disclosure and explicit permission for sharing personal data with
third-party AI. The existing accuracy acknowledgement addresses a different issue.
[Apple privacy requirements](https://developer.apple.com/app-store/review/guidelines/#privacy)

## Verification performed today

- `flutter test --no-pub`: 96 passed, 9 skipped, no failures.
- Repeated full suite with build 12's six purchase defines: 104 passed, 1 failed,
  none skipped. All nine previously skipped billing lifecycle tests passed.
  The one failure is `apple_subscription_config_test.dart:8`, which deliberately
  asserts the group ID is empty and purchases are disabled. It is incompatible
  with the enabled flags; the same test passed in the default run. Record the
  configuration split rather than claiming the flagged suite fully passed.
  These billing tests use mocks, not real StoreKit transactions.
- `node --test supabase/functions/delete_account/storage_cleanup.test.mjs`:
  3 passed, no failures. These cover local cleanup, not deployed v9.
- Retrieved live deletion v9, purchase validation v7 and notifications v6 source.
- Read live membership/entitlement/join/limits definitions, billing grants/indexes,
  bucket configuration, RLS presence, organization plan and security advisors.
- Did not execute payment/deletion flows, mutate production, inspect every RPC,
  prove all provider limits, or run the whole manual feature matrix.

## Recommended next work, narrowly scoped

1. Decide what happens when a family owner deletes their account: retain/transfer
   family-owned profiles, remove their personal vault, and explain billing clearly.
   Implement/test the deletion flow and deploy only that reviewed change.
2. Add purchaser binding with an existing-purchase restore policy; test with two
   app accounts and two family contexts. Do not replace functioning billing code.
3. Test subscriber -> new member joins -> member sees shared plan; then leave,
   expiry and multiple-family selection. This is verification of existing logic.
4. Review AI data-transfer consent and narrow remaining access/cost gaps.
5. Rebrand and reproduce the working email setup after name/domain selection.

Conclusion: substantial implementation and deployed hardening already exist.
The remaining deletion and purchaser-binding findings are concrete, not inferred
from old chat. Public-release readiness still needs those fixes plus lifecycle
tests; this report is not authorization for production changes.
