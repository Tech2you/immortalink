# Targeted security and deletion review - 22 September 2026

Scope: local Flutter account deletion, Apple purchase validation/notifications,
Supabase production deletion function, billing grants, storage configuration and
security advisors. This is not a penetration test, legal opinion, or certification.
No real account was deleted, subscription cancelled, or production configuration
changed during this review. Production project: vbzyvaylfdhwowdbodmk.

## High-priority findings / release blockers

1. **Account deletion does not cancel Apple billing.** Confirmed in current
   code and Apple's documentation. Neither deleting Supabase users nor removing
   entitlements cancels an App Store auto-renewal. Added a prominent warning and
   Manage Apple subscription action before deletion. Opening that sheet is not
   treated as evidence of cancellation. Immediate deletion remains available.
   A sandbox cancel -> delete -> renewal-window test is still required.
   https://developer.apple.com/support/offering-account-deletion-in-your-app/

2. **Production deletion v9 differs materially from the checkout.** Its owner
   path deletes shared family relationships and legacy profiles, then family
   groups. It can affect other family members, not only the departing account.
   The checkout no longer has that family-wide deletion. Do not deploy either
   implementation blindly: define ownership transfer/last-owner behavior and
   test with two disposable family accounts first. Existing members' data must
   not disappear merely because the original owner deletes an account.

3. **Storage cleanup is incomplete and non-transactional.** Production v9 only
   scans four named buckets, omitting vault_voice and the legacy buckets. Its
   walker reads only 1,000 entries per folder and ignores list/remove errors.
   The local helper now paginates and fails explicitly on storage errors, with
   tests, but is NOT deployed. Even the local bucket list is not a full ownership
   inventory. Family-prefixed paths and legacy media require a deliberate
   retain/transfer/delete policy. SQL rows are removed before storage/Auth, so
   interrupted deletion can leave a partially deleted account. A durable,
   retryable deletion workflow is required for launch-quality guarantees.

4. **Purchase ownership binding needs hardening.** Production validation v7
   verifies the supplied Apple transaction and that the caller owns the selected
   family, but does not bind the transaction's appAccountToken to that caller.
   The Flutter purchase request does not supply an account token either. A live
   unique index prevents one original transaction being assigned to two family
   rows simultaneously; that is useful but is not purchaser-identity proof for
   an unclaimed transaction. Add account binding plus an explicit legacy restore
   policy and verify cross-account replay rejection in sandbox before launch.

5. **Reauthentication is client-side only.** The deletion dialog signs in again
   with the password, but the deployed endpoint itself accepts any current valid
   session verified by getUser. It does not enforce recent reauthentication.
   Enforce this server-side before describing password confirmation as a server
   security control. Password whitespace is now preserved by the client.

## Live checks that passed (limited scope)

- No public-schema base tables without RLS were returned by the catalog check.
- family_entitlements and apple_subscription_events grant authenticated clients
  SELECT only; their RLS policies limit reads to family members/owners.
- All 12 inspected storage buckets are private and enforce size/MIME limits.
- Deletion verifies the session through getUser and derives the target user ID
  from it, rather than accepting an arbitrary deletion target from the request.
- Billing owner and event user foreign keys use ON DELETE SET NULL. That means
  account removal does not itself cancel or necessarily remove billing records.

These checks do not prove every RLS policy/RPC is correct. Existing access tokens
can remain valid until expiry after Auth deletion; sensitive operations need
session/existence checks, not just trust in an unexpired JWT.
https://supabase.com/docs/guides/auth/managing-user-data

## Live advisor warnings still open

- Leaked-password protection disabled:
  https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- vector extension in public:
  https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public
- 23 authenticated-callable SECURITY DEFINER functions need individual review.
  Some are intentional RLS helpers; the warning alone is not proof of a flaw.
  Do not revoke all of them and break normal family access:
  https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

## WhatsApp voice notes

The app currently imports supported audio through Files. There is no incoming
iOS Share Extension target/handler. Direct WhatsApp -> Ever Roots is possible
through a share extension, with explicit destination/privacy confirmation,
bounded temporary files, existing upload quotas and cleanup on sign-out/cancel.
No share extension was implemented in this task.

Current audio picker: M4A, MP3, WAV, AAC, OGG, WebM; 25 MiB limit. WhatsApp voice
messages can be .opus, which the picker/MIME mapping does not currently support.
Saving to Files alone does not convert the audio. Validate decoding/transcription
or transcode to a supported format before promising universal WhatsApp import.
View-once messages must not be bypassed. Obtain permission before sharing another
person's recording with a family or submitting it for AI transcription.
https://faq.whatsapp.com/453914586839706/
https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html

## Follow-through

Pull-to-refresh is added to personal/shared/legacy vaults and the home family
feed; the tree's pan/zoom behavior is unchanged. Test on a real phone. Security
findings above remain open until separately remediated and verified; professional
privacy/legal review is appropriate before public launch.
