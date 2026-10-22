# Launch follow-up - 25 September 2026

Read-only verification before implementation. Checkout remains `25eb867`.
No app-code changes, production writes, purchases, deletion tests, domain
purchases or email changes performed. Earlier test results remain dated
23 September; they were not rerun today.

## Fresh backend reconciliation

- Retrieved deployed `delete_account` v9 and `validate_apple_subscription` v7
  again. The specific deletion and purchaser-binding gaps in the September 23
  reconciliation remain present; these are not assumptions from chat.
- Deployed owner deletion still explicitly deletes family-wide legacy/tree
  records. Local deletion removed those broad deletes and added paginated
  storage cleanup, but still deletes legacy media references under the departing
  user's path. Preserving legacy profiles alone does not preserve their media.
- Local deletion has no explicit successor assignment or durable retry job.
  Decide personal-versus-family-owned retention before deployment. Proposed
  policy: delete personal vault/content, retain family-owned legacy records and
  media for remaining members, transfer administration but NOT Apple billing
  ownership. Last-member deletion requires an explicit retention decision.
- Live foreign-key inspection: legacy profiles cascade when their family group
  is deleted; billing-owner references become NULL when Auth user is deleted.
  No family-group-to-Auth foreign key was returned. Neither fact proves safe
  ownership transfer.
- Existing `cleanup_empty_family_group` stops if members remain OR meaningful
  tree data exists. It is a real protection, but does not prevent explicit broad
  deletes in the deployed edge function. Inspected membership triggers have no
  automatic successor assignment.
- Existing membership insert trigger calls the capacity guard. Do not describe
  the legacy invite path as a proven capacity bypass based only on its body.
- Freshly retrieved relationship-invite and entitlement RPC definitions confirm
  current members use family-level limits, with no purchase-date membership
  restriction. Join-after-purchase is implemented logic needing device evidence,
  not a feature to rebuild.
- Genuine Apple transaction validation exists, but caller-to-original-purchaser
  binding remains absent in inspected client/server flow. Keep existing checks;
  add identity binding and a deliberate policy for older unbound purchases.

## Hero name screening

Recommendation: do not migrate to plain Hero on the assumption it has no
competition. This is a preliminary commercial screen, not trademark clearance
or an App Store Connect title-reservation test.

Hero Assistant by MagicX explicitly advertises AI journaling, notes, voice memos
and shared notes. This is adjacent feature overlap, not a conclusion of legal
infringement or proof that it is an identical family-memory archive.

Regional listing pages retrieved successfully:

| Storefront | Existing Hero Assistant listing |
| --- | --- |
| United States | https://apps.apple.com/us/app/hero-assistant-run-your-day/id6443412722 |
| United Kingdom | https://apps.apple.com/gb/app/hero-assistant-run-your-day/id6443412722 |
| South Africa | https://apps.apple.com/za/app/hero-assistant-run-your-day/id6443412722 |
| Canada | https://apps.apple.com/ca/app/hero-assistant-run-your-day/id6443412722 |
| New Zealand | https://apps.apple.com/nz/app/hero-assistant-run-your-day/id6443412722 |
| Ireland | https://apps.apple.com/ie/app/hero-assistant-run-your-day/id6443412722 |
| Australia | Retrieval failed twice; unverified, NOT evidence of absence |

Public listing evidence is not a completed on-device download test. Other
English-speaking territories were not exhaustively checked. Existing website:
https://tryhero.app/

A creator also advertises a product called Hero Journal here:
https://www.reddit.com/r/IMadeThis/comments/1rmklfj/i_built_a_daily_journaling_app_with_an_ai_coach/
Treat this as a research lead, not independently verified availability or rights.

No national trademark-register clearance, global clearance, domain availability
or exclusive right to the name has been established. A lawyer's relevant-market
clearance is separate from domain and App Store title availability. Official
guidance on the broader search required:
https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks

## Preserve the working email flow

Reuse the existing working template structure and auth/invite behavior after a
name is approved. Export the actual live configuration first; do not treat an old
setup document as the live source of truth.

1. Select and verify ownership of the new domain; no domain purchased today.
2. Add the new sending domain in Resend and configure its issued DNS records,
   plus DMARC. Do not blindly copy the old domain's authentication values.
3. Update visible sender name, from/reply-to addresses, template branding,
   support/privacy links and public policies.
4. Update auth redirects, universal links and associated-domain hosting as
   required. Preserve bundle ID and purchase IDs; avoid global text replacement.
5. Test confirmation, reset, invite and app return on a phone; retain working old
   links/domain during transition and switch only after verification.

Resend domain verification documentation:
https://resend.com/docs/dashboard/domains/introduction

## Narrow next acceptance tests

- Owner deletion with another member: surviving member retains family tree,
  legacy media and administration; departing personal data is removed.
- Last-member deletion, failed storage operation and retry: no silent orphaning,
  false success or unintended shared-data loss.
- Apple purchase on account A, restore attempt on B: no entitlement theft;
  legitimate A restore remains possible, including older transactions.
- Purchase then join with B: B receives shared limits, not a second subscription;
  leaving, expiry and switching families refresh the correct entitlement.

These tests remain unexecuted against real accounts/devices in this pass.
