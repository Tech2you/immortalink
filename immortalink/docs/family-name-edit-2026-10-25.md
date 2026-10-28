# Family-name editing - 25 October 2026

## Approved scope

The owner chose to let every current family member rename the family. The
reported build-25 behavior was the previous owner-only rule in both the app
and `rename_family`, not a failure of the new home-screen icon.

The vault family-details sheet and tree settings now expose name editing to
members. Account successor remains owner-only. No ownership promotion,
sponsorship, payment, Storage, media, admission-rule or artwork change is part
of this fix. Existing 1-100-character validation and offline restrictions remain.

## Backend evidence

Exact migration `20261025183407_allow_family_members_to_rename` is deployed to
the existing project. It replaces only `public.rename_family(uuid,text)`,
preserving the signature, empty search path and authenticated-only grant.
Membership is checked against current database rows, not editable JWT metadata.
The local migration filename matches the timestamp returned by the hosted
migration history; no other pending migrations were deployed.

`supabase/verification/family_name_edit_rollback.sql` passed against the live
function using generated family/member IDs and the authenticated database role.
It covers owner and member success, trimming, invalid names, cross-family and
outsider denial, missing identity, former-member denial and RPC grants. The
entire fixture transaction rolled back. No Auth accounts or emails were created,
and no real family name, role, media or billing record was changed.

Before/after counts and fingerprints match for all four existing families,
five memberships, all access policies and all other functions in the relevant
schemas. Security advisor counts are unchanged: 20 private-schema RLS/no-policy
information items, one public-extension warning, 36 authenticated-callable
security-definer warnings and one leaked-password-protection warning. These
are existing findings, not a clean security audit. References:
[RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[extensions](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public),
[privileged functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Local verification and build

- Full Flutter suite: 201 passed, 50 existing configured skips.
- Database regression suites: 14 passed (rename, successor, membership access).
- Release-configured plan-screen, rename and menu tests: 23 passed.
- Focused static analysis: no errors; 45 existing warnings/info in screen files.
- `git diff --check` passed.
- Built and signed 1.0.0 (26), `com.everroots.app`, iOS 15.0 minimum.
- The 120-file source manifest differs from build 25 only in the two screens
  and tree-settings menu needed for name editing. All 15 icon source PNGs and
  the compiled iPhone/iPad icons match build 25. Bundled in-app images match.
- Distribution signature, production push, associated domains, billing flags,
  beta entitlement and disabled debug/screening flags are verified.
- The existing Flutter launch-image warning remains; launch artwork was not
  changed as part of this fix.
- IPA: 33,971,960 bytes; SHA-256
  `955ef8e33f1efe21330787d92724f38a8745bc4bf0b794213c94d4f268e48e79`.
- Build 25's archive and IPA are preserved. Evidence for 26 is under
  `build/ios/release-26-evidence/`, including backend fingerprints, source
  manifest, artifact verification, tests and archive/upload logs.

## Delivery checkpoint

Xcode upload succeeded at 21:01:34 SAST on 25 October (exit 0). App Store
Connect subsequently confirmed build 26 Validated, Non-Exempt Encryption No,
and assignment to Internal Beta with one tester. The owner installed the build
and answered "Renaming works" to the tree-name/save/vault-readback check. This
is a bounded owner-confirmed iPhone check, not full regression or iPad acceptance.

Build 26 replaced build 25 in app version 1.0. Save persisted after a fresh
page reload, and manual release remains selected. Only the app item was
temporarily removed from the review draft to permit build replacement; the
four subscriptions and Heiro Plans remained staged. After the owner unlocked
Safari, the app was added back to that same draft. At 21:24 SAST Apple confirmed
six items: iOS App 1.0 / 1.0.0 (26), Subscriptions (4), and Heiro Plans.
The draft displayed the unchanged turquoise icon. The draft panel was closed;
the app status is Ready for Review. Submit for Review was never clicked.
Nothing has been submitted or released. Store copy/screenshots and other
previously outstanding launch checks remain separate from this completed fix.
