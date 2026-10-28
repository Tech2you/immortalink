# Heiro local branding preview - 26 October 2026

## Scope and delivery

The owner accepted build 28's loading/offline behavior, then requested two image
changes and direct phone installation only. No TestFlight upload, App Store
draft update, review submission, release or backend change was authorized here.

- Startup uses `assets/images/immortalink_logo.png`, exactly the existing
  unlettered in-app background tree. Its 180-point presentation is unchanged.
- Sign-in and create-account share `assets/images/sign_in_logo_heiro.png`, now
  a transparent adaptation of the bright turquoise app-icon tree with HEIRO
  across its roots. The previous transform was removed so the fuller artwork
  stays within its allocated space. This is generated artwork based on the
  icon, not a pixel-identical crop.
- The actual home-screen icon, background image and other app imagery remain
  unchanged. Authentication, payments, offline behavior and server rules remain
  unchanged.

## Verification

- Focused startup/auth tests: 11 passed. Full Flutter suite: 219 passed,
  50 existing purchase-configuration skips. No real purchase was attempted.
- Focused analyzer: no issues. `git diff --check`: passed.
- Phone, tablet and 320-point/2x-text image/layout checks passed; decoded images
  are asserted and screenshots saved in `build/branding-29-qa/`. Some existing
  button labels use the test renderer's block fallback font; screenshots verify
  artwork/layout, not exact device typography.
- 124 source hashes checked against build 28. Only the auth image,
  `lib/screens/sign_in_screen.dart` and `lib/widgets/startup_screen.dart` changed.
- Build 29's development signature, bundle/version, associated domains, all six
  Apple purchase defines and bundled image hashes passed verification. Compiled
  iPhone/iPad icons match build 28. The App Store archive remains build 28.
- The connected iPhone reported build 28 before installation. In-place install
  succeeded without uninstalling the app. An independent post-install query
  confirms `com.everroots.app`, version 1.0.0, build 29, builtByDeveloper=true.
  CoreDevice successfully launched it. No sign-out or real family-data mutation
  was performed. The owner's visual acceptance of this new artwork is pending.

Evidence: `build/ios/local-29-evidence/` contains source and package verification,
build log, install result, installed-app query and launch result.

Apple/TestFlight was not accessed in this step. Its last verified candidate is
build 28, still a draft with manual release. These branding changes are local
only and would need a separately approved upload/draft update for launch.

## Image provenance

Mode: built-in image generation/editing tool, transparent background enabled.
Final project asset: `assets/images/sign_in_logo_heiro.png` (1254 x 1254 PNG).
Generated source:
`/Users/rossstrauss/.codex/generated_images/01a03d2b-4556-7b22-8f49-09eb2da4d97e/exec-52847559-a106-4f26-82da-850cac33df72.png`.

Final prompt:

> Use case: precise-object-edit / logo-brand. Create the replacement sign-in and
> create-account image for the Heiro iPhone app. Image 1 is the EDIT TARGET: the
> current bright turquoise app-icon tree; preserve its identifiable umbrella
> canopy, trunk, spreading roots, cyan/teal lighting and hanging luminous
> strands as closely as possible. Image 2 is a SUPPORTING REFERENCE ONLY for the
> transparent cutout format and the placement of the word at the roots, NOT for
> the tree design. Produce ONE square transparent PNG asset. Extract the tree
> from image 1 as a polished cutout with soft turquoise glow close to the tree,
> removing the opaque square sky/background. Keep the complete canopy, hanging
> lights and roots visible, with a small transparent margin. Integrate exactly
> the word 'HEIRO' (H-E-I-R-O) in clean white uppercase lettering across the lower
> root area, similar to image 2, readable but not hiding the main trunk. Keep
> roots visible around and behind the word, with enough local dark contrast for
> legibility on a pale app background. No other text, no rounded-square icon
> border, no mockup, no added symbols. Do not substitute the older tree from
> image 2. Transparent outside the tree/glow; preserve transparency. The actual
> app icon and in-app background will not be modified; this output is only the
> auth-screen asset.
