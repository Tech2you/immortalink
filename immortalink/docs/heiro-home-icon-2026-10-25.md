# Heiro home-screen icon - 25 October 2026

## Scope

The owner selected the middle turquoise tree in the supplied three-icon image
and explicitly requested that all artwork inside the app remain unchanged.
Only the 15 PNG files in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` were
replaced. The existing manifest, icon name, app code, launch screen, bundled
in-app images and other platforms were not changed by this task.

The built-in image-generation tool adapted the selected middle design into an
opaque, full-bleed square, removing the white surround and mockup tile outline.
This is an image-tool adaptation, not a claim of a pixel-identical crop.
macOS `sips` produced the catalog's sizes from that output. The workspace's
1024-pixel master is:

`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`

## Verification

- All 19 catalog entries resolve to the correct dimensions across 15 PNG files.
- All icons are opaque (no alpha), including the 1024 x 1024 marketing icon.
- Xcode `actool` successfully compiled the catalog for iPhone and iPad targeting
  iOS 15.0. Its sole notice concerns the existing legacy iPad 76-point 1x slot.
- Inspected compiled 120-pixel iPhone and 152-pixel iPad icon images.
- SHA-256 readback confirms all three bundled in-app images, all three launch
  images, and all five Android launcher images are unchanged from task start.
- No live backend, family media, subscriptions or App Store settings changed.
- At the icon-only checkpoint, no full build or upload had been performed.
  The owner subsequently authorized build 25 delivery and replacing build 23
  in the saved submission draft, but not submission or release. See below.

## Build 25 delivery

- Archived/exported Heiro 1.0.0 (25), bundle ID `com.everroots.app`, with the
  existing six Apple billing flags and unchanged dependencies/app code. The
  120-file build-24 source manifest differs only in the 15 approved icon PNGs.
- Distribution signature, production push, associated domains,
  `beta-reports-active=true` and `get-task-allow=false` verified. The unfinished
  screening controls remain compile-time disabled. The new icon was inspected
  in the exported package; bundled in-app images match their original hashes.
- 21 focused plan-screen/single-family tests passed with the release billing
  flags. This asset-only change did not require new payment or data-deletion
  tests on real accounts; previous device evidence is retained, not relabelled.
- IPA size: 33,971,419 bytes. SHA-256:
  `3cf259da3143a4833f63cd5898f7657a0db592d3803f11516c1b66aacfa924e0`.
- Xcode upload succeeded at 14:25:45 SAST on 25 October 2026, exit 0. Subsequent
  Apple verification confirms 1.0.0 (25) processed, Binary State Validated,
  App Uses Non-Exempt Encryption No, and assignment to Internal Beta (one tester).
- Replaced build 23 with 25 in app version 1.0 and saved. A fresh page load
  confirms 1.0.0 (25) and manual release. Apple's build row and Included Assets
  show the new bright turquoise icon; the exported package was also inspected.
- On the authorized continuation, added the app back to the existing draft.
  Apple shows Ready for Review and six items: iOS App 1.0 / 1.0.0 (25), four
  subscriptions and Heiro Plans. No Submit for Review or release action was taken.
- Evidence: `build/ios/release-25-evidence/` contains the source manifest/patch,
  archive log, IPA, signing/configuration verification, test log and upload log.
  The prior archive is preserved in `build/ios/release-24-evidence/Runner.xcarchive`.
- The owner confirmed TestFlight 1.0.0 (25), the correct bright turquoise
  home-screen icon and unchanged in-app images on their phone. This is bounded
  owner-reported visual acceptance, not a new full functional or iPad test.
  The earlier build-24 phone pass is not relabelled as build-25 evidence.

## Asset-generation prompt

Built-in tool, edit mode, opaque background. Input: the owner's attached
`codex-clipboard-926324be-16e8-42fe-93a3-fc3dcaa18da2.png`.

> Use case: precise-object-edit. Asset type: production iPhone/iPad home-screen app icon, square 1024 x 1024 opaque image. Input image is a triptych of three tree icons. Extract ONLY the MIDDLE, bright turquoise tree icon. Preserve that exact middle tree, canopy silhouette, trunk, exposed roots, hanging lights, glow, colors and composition as closely as possible; do not redesign or invent a different tree. Remove the neighboring icons, white canvas outside the middle icon, mockup bevel and pre-rounded tile outline. Output its artwork full-bleed as a flat square icon, extending only the turquoise background into the corners so the operating system can apply the rounded mask itself. Entire canopy and roots must remain visible with the same relative placement and breathing room as the original middle image. No border, no white margins, no external drop shadow, no text, no letters, no watermark, no transparency. This is a faithful extraction/adaptation of the selected middle design, not a new logo concept.
