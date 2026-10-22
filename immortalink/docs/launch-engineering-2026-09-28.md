# Launch engineering - 28 September 2026

Later status: the reviewed sponsorship backend and matching iPhone build have now
been deployed. See [the current sponsorship handoff](family-sponsorship-2026-09-28.md)
for exact versions, live checks and device test order. The deletion blockers below
remain open. The following records the earlier local-only pass, not current
deployment status.

## This pass

- Connected iPhone 14 detected by CoreDevice (available, paired). No new build
  installed and no account deleted. User can sign into disposable test accounts;
  identify the exact test accounts before any destructive live test.
- Added signed-in app UUID to StoreKit purchase parameters. Installed StoreKit
  plugin 0.4.11+1 uses StoreKit 2 by default and maps `applicationUserName` to
  `appAccountToken`.
- Added purchaser checks to the local validation function, after retrieving the
  transaction from Apple's Server API and checking product/bundle/transaction.
  Mismatched account, existing family/billing binding, or environment is rejected.
  Older tokenless transactions require an existing matching account AND family
  association; previously unbound purchases require support, not first-claim wins.
- Added a bounded client diagnostic and original-account message for rejected
  restores. No server function deployed in this pass.

Verification: 10 Node product/purchaser tests passed; 15 purchase-enabled Flutter
service tests passed; analyzer found no issues in the changed service/test;
`git diff --check` passed. These are local checks, not live purchase evidence.

## Remaining release gates

1. Account deletion is NOT finished. The local function still deletes legacy
   references by uploader prefix and removes entire uploader storage folders.
   Current legacy screen uploads family-owned photos to `vault_photos` using
   `user/family/legacy/member/...`; those files must survive with other members.
   Preserve shared references and bytes before deleting the uploader's account.
2. Wire successor handoff into a transaction with membership removal. Include
   last-real-member family cleanup, all media buckets, and durable retry behavior.
   Do not change ordinary Leave family behavior. Family-avatar objects use the
   fixed `family/avatar` path and also need an ownership/retention decision.
3. Reconcile shared-media read policies before moving preserved files. Fresh live
   `can_read_shared_media_object` handles legacy voice references but does not
   resolve legacy photo references in `vault_photos`. Do not assume copying a
   file alone makes it readable by the surviving member.
4. Purchase changes need full handler/deployment verification, atomic binding and
   entitlement race review, production/sandbox configuration, and real two-account
   purchase/restore tests. Pure helper tests do not prove those properties.
5. Test existing join-after-purchase, expiry, refund, account switching and deletion
   on disposable accounts. No such device test has been performed in this pass.

Do not submit for paid public release on the strength of these local changes.
Name/domain/email and business-account walkthrough follows engineering completion.

References:
- https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken
- https://supabase.com/docs/guides/storage/management/copy-move-objects
