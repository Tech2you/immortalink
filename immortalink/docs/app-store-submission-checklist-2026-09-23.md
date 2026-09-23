# App Store submission checklist

Prepared 22 September 2026. Target submission: 23 September 2026.

## Decision today

**NO-GO on current evidence.** Resolve the deletion and purchase-validation
findings below, settle the new brand, and complete release-candidate testing
before submitting. Apple reviews the finished app; it does not repair the app,
certify its security, or clear its trademark rights. Submission is not release.
Choose manual release so approval does not automatically publish the app.

This document is a checklist, not a completed penetration test or legal opinion.
No provider upgrade, new domain purchase, production deployment, rebrand, or
submission was performed while preparing it. Actual billing-account plans and
the final App Store configuration still need checking.

Evidence labels:
- **Known blocker:** recorded in the 22 September targeted review.
- **Unverified:** requires inspection or a recorded test; not necessarily broken.
- **Implemented locally:** not proof of production deployment or device behavior.
- **Must wait:** depends on the brand, legal advice, external processing, or fixes.

Prior validation: 96 Flutter tests passed, 9 skipped, and 3 storage-cleanup tests
passed in the preceding work. These are not an all-features/security sign-off.
See [targeted review](security-review-2026-09-22.md). Re-run after final changes.

## 1. Fix release blockers first

- [ ] **Known blocker: production account deletion.** Reconcile deployed v9 with
  the checkout. It must not erase other members' family relationships and legacy
  profiles merely because the original owner leaves. Define ownership transfer,
  last-owner behavior, and which shared contributions remain.
- [ ] **Known blocker: complete, retryable deletion.** Inventory every owned
  bucket/path, including voice and legacy content; remove required database,
  storage and Auth data. Handle more than 1,000 objects, interrupted jobs and
  retries. The local pagination/error fix is not deployed and is not sufficient
  by itself. Record failures for safe retry without logging private contents.
- [ ] **Known blocker: recent authentication.** Enforce it at the deletion
  endpoint, not just in the Flutter dialog. Verify a deleted/revoked account
  cannot use a still-unexpired token on sensitive endpoints.
- [ ] **Known blocker: Apple purchaser binding.** Bind verified transactions to
  the purchasing app account, with a deliberate restore/migration policy for
  older purchases. Reject cross-account transaction replay. A unique transaction
  index alone does not prove purchaser identity.
- [ ] **Billing/deletion test.** Warn prominently that deleting the account does
  not cancel Apple renewal. Offer subscription management but retain immediate
  deletion. Never claim that opening Apple's sheet proves cancellation. Test
  cancellation, account deletion and the later renewal/expiry state separately.
  [Apple account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [ ] **Unverified: production parity.** Record deployed function versions,
  migrations, release flags and notification endpoints after fixes. Do not infer
  deployed correctness from a local build or old launch notes.

## 2. Brand and domain migration

- [ ] Choose a new name and launch countries. Obtain an IP professional's
  clearance/risk opinion for relevant markets. Search similar names and related
  products, not just exact spellings. Domain and App Store availability do not
  establish trademark clearance. Start with [CIPC](https://iponline.cipc.co.za/).
- [ ] Buy the approved domain; enable registrar MFA, renewal and recovery access.
  Establish working support/privacy email addresses with monitored inboxes.
- [ ] Update display name, icon/wordmark, onboarding, emails, paywall text,
  subscription display names, screenshots, store description and public pages.
  Search source/configuration for both Ever Roots and ImmortaLink remnants.
- [ ] Preserve existing bundle/product identifiers unless an explicit migration
  is justified. A display-name change should not accidentally create a different
  app or strand purchases. Review any legal concern about old identifiers.
- [ ] Update website hosting/DNS/TLS, Supabase Auth site URL and exact permitted
  redirects, confirmation/reset templates, invite-link generation and validators.
  Avoid broad wildcard redirect permissions.
- [ ] Update iOS Associated Domains and serve the correct Apple association file
  on the new domain. Verify its app identifier matches the signed app.
- [ ] Keep control of the old domain during a defined transition. Test old and
  new invites and email links; an HTTP redirect alone is not universal-link proof.
- [ ] Test confirmation/reset/invites with the app closed, open, installed and
  absent. Confirmation should return to the installed app correctly, without
  losing the invite. Never expose tokens in analytics or logs.

## 3. Provider plans and spending protection

Suggested lean production baseline, not purchases already made:

| Service | Recommendation | Budget implication |
| --- | --- | --- |
| Supabase | Pro, starting at USD 25/month; confirm the org's project inventory | Includes compute credit; additional projects/compute/add-ons can add costs |
| Resend | Transactional Pro at USD 20/month for 50,000 emails if launch volume needs it | Free has a 100/day limit; a paid upgrade is not itself an Apple requirement |
| AI provider | Verify the API project/key, payment source, usage and enforced limits | Separate variable expense; do not assume it is included in hosting |
| Other | Domain, Apple membership, website hosting, monitoring and media backups | Include annual renewals, tax and exchange-rate exposure |

Supabase + Resend Pro starts around **USD 45/month**, before taxes, extras and AI.
It is a baseline, not a maximum bill or profitability claim. Verify checkout
prices and existing subscriptions before paying.
[Supabase pricing](https://supabase.com/pricing),
[Resend pricing](https://resend.com/pricing),
[Resend Pro/overage example](https://resend.com/changelog/pay-as-you-go-pricing).

- [ ] Pick a monthly operating budget and emergency stop threshold in your
  preferred currency. Assign an alert recipient and a person able to act.
- [ ] Keep Supabase Spend Cap enabled. It covers selected metered services, not
  compute or every add-on, and hitting limits can restrict service. Inspect the
  upcoming invoice and avoid unnecessary projects, replicas and paid add-ons.
  [Spend Cap scope](https://supabase.com/docs/guides/platform/cost-control)
- [ ] Check Resend Transactional Overages. Leave off unless deliberately budgeted;
  enabling it permits automatic extra charges. Add signup/reset/invite cooldowns
  and abuse controls, while keeping legitimate account recovery usable.
- [ ] Authenticate the new sender domain with Resend's required DNS records;
  check SPF, DKIM and DMARC alignment without creating duplicate SPF records.
  Test confirmation, resend, reset and invitation delivery to several providers.
  Disable click tracking on authentication links and verify link expiry/reuse.
- [ ] Enforce storage, upload size, audio duration, AI input/output and usage
  quotas on the server. Verify duration independently of client metadata.
- [ ] Test concurrent requests at the quota boundary, retry idempotency,
  repeated transcription and free-account abuse. Per-family paid quotas must
  not multiply simply by inviting more members.
- [ ] Add bounded concurrency and global daily usage/cost protection for costly
  operations, plus an emergency switch that stops new costly requests without
  blocking access to existing memories. Do not assume a budget alert is a cap.
- [ ] Measure video downloads/egress, image transformations, retries and orphan
  uploads, not just stored GB. Avoid unrestricted prefetch/download loops.
- [ ] Calculate margin using actual App Store proceeds after commission/taxes,
  annual discounts, AI/audio, egress, storage, support and free-user costs.
  Test heavy-use scenarios; the current tier prices alone do not prove profit.

## 4. Security verification

- [ ] Test with two unrelated users, two families, an invited member, former
  member and unauthenticated caller. Alter IDs in direct requests: no reading,
  changing, signing URLs for, or deleting another family's private resources.
- [ ] Review RLS policies, views, storage rules and every exposed privileged RPC.
  RLS being enabled is not proof that its predicates are correct. Individually
  review the 23 authenticated-callable SECURITY DEFINER functions flagged in the
  earlier audit; do not blindly revoke required helpers.
- [ ] Resolve or explicitly justify advisor findings: leaked-password protection
  currently disabled and vector extension in public. Retest after changes.
- [ ] Scan code, built assets and logs for private/service-role/API keys and
  personal data; rotate any exposed secret. Enable MFA for Apple, Supabase,
  email, registrar, repository and AI provider administrators.
- [ ] Verify authorization inside every privileged Edge Function, not merely
  gateway JWT acceptance. Validate resource ownership and request bounds.
- [ ] Verify Apple notification authenticity, duplicate/out-of-order handling,
  refunds, revocations and entitlement expiry. Client flags cannot grant plans.
- [ ] Check invite expiry/reuse/revocation, rate limiting and that guessing an
  invite or asset URL cannot expose a family. Use appropriately short signed URLs.
- [ ] Inspect upload validation, malformed files, MIME/extension mismatches and
  size limits. Render user text safely; do not execute or trust file metadata.
- [ ] Check AI retrieval permissions and prompt-injection attempts. Retrieved
  memory text must not override access controls or expose another vault.
- [ ] Verify offline files are account-scoped, read-only, bounded and cleared on
  logout/account switch/deletion. Check expiry without internet and documented
  revocation limits: a disconnected device cannot instantly learn new permissions.
- [ ] Run dependency/secret scans and triage findings. Use authorized disposable
  data for abuse tests, with bounded traffic; no destructive production load test.
- [ ] Arrange independent security review when feasible. No audit can establish
  that nobody can ever hack the app.

## 5. Privacy, trust and legal readiness

- [ ] Replace early-beta wording and old branding in the actual hosted policy,
  not just the repository copy. Match the app, website and App Store URLs.
- [ ] Inventory real processing: accounts, family/non-user relatives, children's
  data, media/voice, AI/transcription, payments, diagnostics, push tokens and
  short-lived offline copies. Verify each provider, including Resend and any
  Firebase services actually used, rather than copying a generic template.
- [ ] Explain operator/contact, purpose, recipients, cross-border processing,
  retention/backups, deletion, access/correction requests and complaints. Have a
  qualified adviser review POPIA obligations, children's information, Information
  Officer requirements and any additional launch-country laws.
  [Information Regulator POPIA resources](https://inforegulator.org.za/popia/)
- [ ] Audit explicit permission BEFORE sending personal data to third-party AI,
  including background embeddings/transcription. A policy link alone is not a
  substitute. Explain recipient/data and let users decline without losing core
  non-AI functionality. Review consent for other people's recordings/data.
  [Apple privacy/AI rule](https://developer.apple.com/app-store/review/guidelines/#privacy)
- [ ] Align App Privacy labels and privacy manifests/required-reason API entries
  with the actual app and SDK behavior. Request tracking permission only if actual
  tracking requires it; do not invent data collection or protection claims.
- [ ] Publish suitable terms/EULA: subscription renewal/cancellation, shared
  content rights, acceptable use, AI limitations and complaint handling. Legal
  disclaimers cannot remove statutory duties or guarantee immunity from claims.
- [ ] Review family-shared content against Apple's user-generated-content rules:
  reporting, blocking/removal, moderation response and accessible contact.
  [App Review guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [ ] Confirm rights/licenses for branding, art, fonts, dependencies and bundled
  sample media. Do not promise end-to-end encryption, indefinite preservation,
  guaranteed AI accuracy or permanent access unless actually delivered.

## 6. Execute the release-candidate test matrix

Every row below is **unverified for the final candidate**. Record build number,
device/OS, environment, result and evidence. Use disposable accounts and synthetic
family data. Run on the minimum supported OS and a current iPhone; test iPad if
offered. Both a fresh install and upgrade from the existing build matter.

| Area | Required scenarios |
| --- | --- |
| Authentication | New signup, email verification, duplicate signup, password reset, expired/reused links, sign-out/in, denied/slow connection |
| Onboarding | First account only; create vault/photo/memory; back/skip; restart midway; invited user retains destination |
| Vault/profile | Create/edit/delete; avatar; long names and Unicode; personal/shared/legacy permissions; empty and large lists |
| Tree/invites | Every relationship; duplicate/cyclic invalid links; pan/zoom/recenter; family name/photo; join/leave; owner transfer and expired invite |
| Memories/feed | Private vs shared; create/edit/delete; media attachments; cross-family isolation; ordering and refresh without duplicates |
| Pull-to-refresh | Home/feed/personal/shared/legacy, short lists, failures and concurrent refresh; tree gestures unchanged |
| Media/voice | Supported formats, oversized/corrupt files, upload interruption/retry, microphone permission, playback/background audio, transcription limits |
| WhatsApp import | Test actual exported voice format through Files; do not advertise direct sharing or universal .opus support without implementation |
| AI | Consent declined/granted; permitted context only; response errors/timeouts; quota exhaustion and simultaneous requests |
| Offline | Online to airplane mode; cold reopen; cached profile/media/tree; read-only actions; missing/expired cache; six-hour expiry; no duplicates; reconnect |
| Cache privacy | Account switch, sign-out, access removal, deletion and device storage pressure; no previous user's content displayed |
| Purchases | All four products/local prices; buy/cancel/pending/fail; restore; renewal/expiry/refund; upgrade/downgrade; cross-account replay |
| Apple environments | TestFlight sandbox and production routing verified; reviewer sandbox supported; server credentials/notification endpoints correct |
| Deletion | Owner/member/last owner; shared data survives correctly; all required files removed; partial failure/retry; old session rejection; Apple warning |
| Network/lifecycle | Slow/lost/recovered network during each operation; background/foreground and killed app; no raw errors, lost work or false success |
| Notifications | Permission denied/granted; correct recipient; tap destination; no private content leaked on lock screen; signed-out behavior |
| Accessibility | VoiceOver, large text, contrast, keyboard/safe areas, narrow screens, landscape as supported, no clipped controls |
| Performance | Representative large family/vault, scrolling/media memory, repeated refresh; no runaway requests or crashes |
| Recovery | Restore database AND media in isolation; verify access policies and no accidental resurrection of deleted users/content |

Run the complete automated suite and release build after fixes. Investigate the
nine skipped tests; document why each is irrelevant or run its missing coverage.
Never mark all-features testing complete solely because unit tests pass.

## 7. Operations and Apple submission

- [ ] Establish database AND uploaded-media backup/recovery with retention,
  access restrictions and a tested restore. Supabase's database backups do not
  contain Storage file contents. Do not present a Pro upgrade as full media backup.
  [Backup scope](https://supabase.com/docs/guides/platform/backups)
- [ ] Set privacy-safe crash/error monitoring, availability/email failure alerts,
  cost review, incident contact and a tested rollback plan. Document what happens
  if a quota cap stops uploads/email/AI. Keep the backend available during review.
- [ ] Confirm Apple membership, legal entity, Paid Apps Agreement, tax and banking,
  product availability and applicable regional trader requirements are complete.
- [ ] Build with the currently required toolchain. Apple's published minimum
  since 28 April 2026 is Xcode 26 with iOS 26 SDK or later; verify again at upload.
  [SDK requirement](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)
- [ ] Validate release signing, bundle ID, version/build number, production
  configuration, push/deep-link entitlements and absence of development secrets.
- [ ] Complete new-brand screenshots, description, support/privacy URLs, age
  rating, App Privacy questionnaire, content rights and export-compliance answers.
- [ ] Attach required subscription review information and products to the app
  submission as applicable. Match price/period/benefits, renewal disclosure,
  restore and management links to the actual purchase flow.
- [ ] Give reviewers a stable demonstration account with synthetic content and
  clear steps for family features, AI and IAP. Do not make review depend on your
  personal inbox, payment or private family information. Disclose required setup.
- [ ] Select manual release. Archive the exact reviewed build and backend version
  evidence. Freeze unrelated features, deploy verified fixes and re-run smoke tests.

## Final go/no-go and immediate order

1. Decide new name/domain, initial countries and monthly operating budget.
2. Resolve deletion and purchase binding; verify production parity safely.
3. Configure provider billing protections and sender/domain migration.
4. Complete privacy/consent, brand clearance and Apple metadata.
5. Execute the final candidate matrix and recovery/security checks.
6. Submit only with no unresolved high-severity issues, valid reviewer access and
   documented evidence. If these gates are not met tomorrow, continue private
   TestFlight instead of rushing a public submission.

Defer new direct WhatsApp sharing, additional AI features and broad redesigns
until after this release gate. Do not use a launch deadline to waive security,
data-loss or consent defects. Professional legal advice is needed for liability
and trademark questions; this engineering checklist does not provide legal cover.
