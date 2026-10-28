# Loading stability - 26 October 2026

## Evidence and cause

The owner's screen recording shows two separate presentation problems:

- Opening a visited vault briefly displays a compact Offline page before the
  normal Your Vault page, even when the connection succeeds.
- Returning home or refreshing blanks avatars/photos before showing them again.

The cached vault flag selected a different page layout, rather than only a data
source/read-only state. Refresh also reset media/loading state, and renewed
signed URLs cleared already-decoded image bytes. This explains visible layout
changes; the recording does not establish GPU frame timings or network latency.

## Scoped fix

- Cached and live vault contents use the same page, header and sections. A
  cached snapshot alone no longer labels the page Offline. Edits remain disabled
  until access/data validation succeeds; genuine offline access stays read-only.
- Refresh retains current cards, media and scroll position. Only first-load
  content uses placeholders. Duplicate page refreshes are suppressed.
- Photo revalidation keeps an already-visible image for the same canonical
  media URL and cache/account generation. Identical returned bytes reuse the
  image provider; first appearance uses a brief fade respecting reduced motion.
- Family/feed avatars use the same stable photo component.
- Denied photo access removes the image. Account/cache changes clear displayed
  content immediately, and pending requests cannot repopulate the old account.
- Memory actions retain their layout while temporarily disabled. Narrow-screen
  footer actions wrap, and the fixed-size highlight action uses a shorter label.

Only three app source files differ from local build 30: vault_home_screen.dart,
vaults_screen.dart and recent_photo.dart. No backend, permissions, subscription
rules or artwork were changed. Earlier local branding and sign-out fixes remain.

## Verification

- Full Flutter suite: 225 passed, 50 existing configuration-dependent skips.
- Configured billing suite: 79 passed with mocked StoreKit, no purchases.
- Focused loading/offline/photo tests: 17 passed. Final photo/visual retest after
  test-only analyzer cleanup: 11 passed.
- New tests cover renewed-link image retention, different-image clearing,
  rejected access, pending refresh during account switching, and header/scroll
  stability on phone, tablet and 320-pixel large-text layouts.
- Six cached/live render captures were generated, with phone/tablet/large-text
  layouts checked. They are synthetic test fixtures, not real customer content.
- Focused analyzer: zero errors; 112 existing screen warnings/information
  messages remain. No findings in the changed photo widget or test files.
  `git diff --check` passed.
- Local build 1.0.0 (31) compiled successfully. Development signature, bundle ID,
  associated domains, all six Apple billing defines and 124 source hashes
  verified. Bundled images and compiled launcher icons are unchanged. The
  preserved App Store archive is still build 28.

## Delivery checkpoint

In-place installation on the connected iPhone succeeded. An independent device
query confirms Heiro, bundle com.everroots.app, version 1.0.0, build 31.
The remote launch command also succeeded.
No uninstall, sign-out, account reset, family operation or purchase was performed.
Owner subsequently confirmed that the revised transitions feel smooth. No physical
device frame-timing trace has been captured; a fixed frame-rate claim is not made.

Evidence: `build/ios/local-31-evidence/`; render captures:
`build/loading-31-qa/`. The recording and extracted review frames are temporary
local inspection material, not repository assets.

TestFlight and App Store Connect were not accessed or changed. The last verified
Apple candidate is build 28, unsubmitted with manual release. Local builds 29-31
are not in that draft. A later TestFlight upload/draft update needs approval.
