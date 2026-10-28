# Sign-out navigation fix - 26 October 2026

## Report and cause

The owner reported that leaving a family, then signing out of Frank's account,
left the app on Your Vault / No vault yet instead of returning to sign-in.

Both tree leave-family paths replaced the entire navigation stack with a bare
VaultsScreen. That removed the root AuthGate, which listens for session changes.
Sign-out then cleared the vault UI without an auth gate to show sign-in. A
regression reproduced the missing AuthGate before the fix. This is a navigation
defect, not a call to account deletion. No live audit of Frank's account was
performed, and no real account or family data was changed during this work.

## Scoped changes

- RelationshipTreeScreen and the older FamilyTreeScreen return through the named
  root route after leaving, preserving the session-driven AuthGate lifecycle.
- VaultsScreen sign-out returns through the root rather than manually displaying
  an empty vault. The older tree's sign-out also returns through the root rather
  than installing a standalone SignInScreen.
- FamilyBranchScreen retains the root when returning to the older family tree.
- Account deletion, family-leave policy, backend, billing, icons and all artwork
  are unchanged. Only four app source files differ from local build 29.

## Verification

- Expanded `test/single_family_launch_test.dart`: both top-level tests pass.
  Its shared fixture now covers current-tree leave/sign-out/sign-in, canceled
  sign-out, older-tree leave/sign-out/sign-in, and the branch-to-tree path.
  Assertions verify the same vault after sign-in, no replacement vault creation,
  no account-deletion requests, and the AuthGate's continued presence.
  Authentication and data are mocked; these are not real-account mutations.
- Full Flutter suite: 219 passed, 50 existing purchase-configuration skips.
- Separately configured billing suite: 79 passed with mocked StoreKit.
  The default-configuration test passes in the default suite, not the configured
  run, because it intentionally asserts that product IDs are absent.
- Focused analyzer: no errors; 106 existing warnings/information messages in the
  touched screen files. `git diff --check` passed.
- The current tree path was tested at phone dimensions. The older tree requires
  bounded frame pumping because of an existing geometry/rebuild loop, and its
  scenario was tested at a wider viewport because of existing narrow-layout
  overflows. Those older-screen issues remain outside this routing fix.
- Local build 1.0.0 (30) compiled successfully. Development signature, bundle ID,
  associated domains, six Apple billing defines and 124 source hashes verified.
  Bundled artwork and compiled iPhone/iPad icons are unchanged; the App Store
  archive remains build 28.

## Delivery checkpoint

Delivery is direct to the connected phone only. Before installation an independent
device query confirmed local build 29. The first build-30 install attempt failed
with CoreDevice connection error 4000 / invalidated transport. After the owner
reconnected and replied ready, the in-place installation succeeded. An independent
device query confirms Heiro `com.everroots.app`, version 1.0.0, build 30.
The subsequent launch command hit the same connection error; the owner was asked
to open the installed app manually. Device sign-out/sign-in acceptance is pending.
No uninstall, account reset, sign-out or real family operation was performed.

Evidence: `build/ios/local-30-evidence/` contains the source manifest, build and
test logs, package verification, successful installation result, installed-app
query and failed remote-launch result.

Apple/TestFlight was not accessed or changed. The last verified Apple candidate
is build 28, with manual release and an unsubmitted draft. Local branding and
this routing fix are not in that candidate. A later upload requires approval.

After installation, owner acceptance should check ordinary sign-out and sign-in
with the existing account. Leaving a family again is not needed.
