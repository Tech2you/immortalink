# Heiro screenshot candidates and reviewer fixture

Prepared 24 October 2026. Four public store draft assets and four private
subscription review image fields uploaded; nothing submitted.

## Provenance

- Genuine app UI, not generated interface mockups. Exported source commit
  `d66dcf4` (the TestFlight 23 source) to a temporary directory and built
  `1.0.0 (23)` for the iOS simulator in debug mode, with the existing Apple
  product/group defines. The debug banner is disabled by the app source.
- The dependency lockfile matches the export. The existing Firebase plist
  matches the archived build's configuration. No working-tree screening changes
  were included. This is not the uploaded IPA or final-device acceptance proof.
- Captured with Simulator's Save Screen on iOS 26.5. Original PNGs are retained.
  JPEG copies at quality 100 remove the alpha channel without resizing, cropping,
  painting over, or changing the app interface.
- iPhone 17 Pro Max: 1320 x 2868. iPad Pro 13-inch (M5): 2064 x 2752.
  Dimensions and absence of alpha were checked for all six JPEG files.
- No real family content, account passwords or private reviewer contact details
  appear in these screenshots.

## Candidates

| View | iPhone | iPad | Status |
| --- | --- | --- | --- |
| Family tree | [JPEG](iphone/01-family-tree.jpg) | [JPEG](ipad/01-family-tree.jpg) | Hold: the fixed person selector overlaps part of the top great-grandparent row at the initial framing. Keep as QA evidence, not a final store selection. |
| Legacy profile/story | [JPEG](iphone/02-legacy-memory.jpg) | [JPEG](ipad/02-legacy-memory.jpg) | Uploaded to the draft. Owner visual review and final-candidate match pending. |
| Personal photo/voice memory | [JPEG](iphone/03-photo-and-voice-memory.jpg) | [JPEG](ipad/03-photo-and-voice-memory.jpg) | Uploaded to the draft. Owner visual review and final-candidate match pending. |

The two non-tree JPEGs per device were uploaded to the English (U.S.) draft:
iPhone with Dynamic Island (large display), and iPad 13-inch. Apple shows the
iPhone medium-display slot using the existing large-display assets. The iPhone
large-display and iPad counts are both 2 of 10 after full reloads. Evidence:
`../submission-evidence-2026-10-24/iphone-images-uploaded.jpg` and
`../submission-evidence-2026-10-24/ipad-images-uploaded.jpg`.
These are editable store drafts, not owner-approved final artwork. The two tree
captures remain local only. Private subscription review images are separate,
as recorded below.

### Visual review - 25 October 2026

Read-only Apple inspection still shows the legacy and personal photo/voice
images for iPhone and iPad. Recommend photo/voice first, legacy second; this
order is proposed, not applied. Keep the overlapping tree capture out.
Owner visual approval and comparison against processed build 24 are pending;
the owner-confirmed basic build-24 phone check is not screenshot approval.

The photo/voice image still shows "Sunday picnic - sample recording", captured
before the approved demo-audio replacement. Prefer recapturing that genuine
screen with the current test-tone caption at finalization. A changed build
number alone does not require replacing otherwise accurate captures. No image
has been edited, replaced or reordered during this review.

## Private subscription review images

The owner supplied four phone paywall screenshots and then reported TestFlight
build 23 and USD in the Apple billing details. Selected images 2 and 4 show the
complete Family and Legacy tiers respectively, including monthly/annual prices.
The original 1170 x 2532 RGB PNGs have no alpha and were copied without edits:

| File | User source basename | Attached products |
| --- | --- | --- |
| [Family](subscriptions/family-review.png) | codex-clipboard-23c9cc36-0b82-41e0-bd04-5f9a1581f52e.png | Family Monthly and Annual |
| [Legacy](subscriptions/legacy-review.png) | codex-clipboard-b7016d62-a77b-495b-b955-8f5563a52bf5.png | Legacy Monthly and Annual |

SHA-256 matches the user-provided originals:

- Family: `c4e12f8be26fe32feebc0781f4bd25298105b76ef89c8de3a28b01f2ba6790c8`
- Legacy: `083f129e5ada2a6c0ba012cfee047f133537f1eec6b89e7963d84cf78f146a1d`

All four Review Information > Screenshot entries persisted after reload and
their thumbnails were visually checked. Evidence files under
`../submission-evidence-2026-10-24/` are `family-monthly-review-image.jpg`,
`family-annual-review-image.jpg`, `legacy-monthly-review-image.jpg` and
`legacy-annual-review-image.jpg`. Apple says these fields are private to review.
They show the owner's supplied test-memory background, so do not reuse them as
public marketing artwork. The synthetic-content provenance above applies only
to the simulator store images, not these phone captures.

No purchase, restore, price or payment-logic change occurred. The owner then
confirmed Storefront USA, which explains USD despite physical presence in South
Africa. This is not evidence of a pricing bug and not a new ZAF/ZAR test.
Product count and Result were not supplied; no failure was reported.
Build identity is owner-reported, not inferred from appearance.
The images show two paid tiers and four billing
options, which is the intended layout. Nothing was added for review or submitted.

## Isolated reviewer fixture

The owner approved `linebreakers+apple-review@outlook.com` after a read-only check
showed that the bare Linebreakers address already belongs to a real account.
The plus-address was unused, then created as a new email-confirmed ordinary
Heiro account. The existing Linebreakers account was not reset or changed.

- One new Morgan Family, one personal vault (Alex Morgan), and three fictional
  legacy profiles (Robin, Evelyn and James).
- Two personal sample memories, legacy About-me entries and one legacy story.
- An original generated picnic photo and a locally synthesized sample recording.
- Auth administration was used only to create/verify the new identity. Content
  creation and final data/media checks used that ordinary member's access token
  and the existing RLS policies. No schema, moderation, billing or paid-plan
  changes were made; the demo remains on the real free allowance.
- Verified: password login through the API and both simulator UIs; exactly one
  family membership; only the demo's own personal vault visible; authenticated
  photo and WAV downloads match the local bytes. Both devices render the sample
  photo and the recording control, and open the tree and legacy story.
- The original WAV was replaced on 25 October with the owner-approved original
  eight-second test tone documented below. Earlier screenshots may show the old
  attachment title. The displayed playback control is not audible-playback
  proof: listening on the actual TestFlight candidate is still pending.
- The home Family Feed is empty because the existing client excludes the
  current user's own vault. This single-login fixture does not prove invitation,
  another member's feed, member blocking, purchases or destructive deletion.
  Do not create an extra companion identity without a confirmed address/scope.
- Username, unique password and original 1,503-character walkthrough notes were saved in
  Apple's private App Review Information and checked after a full reload.
  Original notes counter: 2,497 remaining. On 25 October the notes were updated
  to explain the original test tone; reload confirmed 2,393 remaining. Manual
  release and Prepare for Submission remain set. No credential was changed in
  that notes update. No password is recorded in this repository. After a later
  owner-shared credential screenshot, the owner confirmed resetting the demo
  password on 25 October, saving the replacement directly in Apple, and signing
  into Heiro with it to see Morgan Family. This is owner-reported evidence;
  neither the replacement credential nor a new credential screenshot was read
  in that owner-only reset checkpoint. A later automated accessibility read
  during the build/store check unexpectedly included Apple's password field.
  The owner was informed and subsequent output is filtered. No credential value
  is written here; final demo-password rotation and an Apple-field update are
  pending again before submission, after metadata work is finished.
- After saved-field verification, the temporary local credential file and
  one-off setup script were removed. Future reviewer-login maintenance should use
  Apple's private App Review Information, not recreate/reset the real account.

## Sample-media provenance

`sample-media/sunday-picnic.png` was generated with the built-in image-generation
tool in new-image mode, opaque background, with no source photograph. It is
fictional illustration content inside the app, not a mock of the app UI.

Prompt: Original photorealistic landscape sample photograph for a fictional
family-memory demo: a Sunday picnic on a green lawn beside a garden, red-and-white
gingham cloth, wicker basket, fruit, two unbranded mugs, and a closed recipe
notebook with no readable text. Natural afternoon light. No people, faces,
logos, watermarks, UI or text. Sample media, not an interface mockup.

**Retired, do not reuse:** `sample-media/picnic-voice.wav` and its AIFF source
were synthesized using macOS `say`. On 25 October the macOS licence's
personal/noncommercial System Voice restriction was identified. With the owner's
specific approval, the remote synthetic object was removed and its single demo
attachment row was switched to the original test tone below. Local historical
source files are not current review assets.

**Current demo audio:** `sample-media/review-test-tone.wav` is an original
eight-second mono PCM16/16 kHz WAV, generated mathematically without speech,
music, samples or paid services. Four 440 Hz sine beeps begin at 0, 2, 4 and 6
seconds, last 0.6 seconds each, use 30 ms edge fades and amplitude 0.12. File
size is 256,044 bytes; measured duration is 8.000000 seconds.

SHA-256: `b11d0dd460e150d26552b1d2eed9c53c1900cc8336b82085e18cb9f338729fd8`.

It replaces only the isolated Morgan Family attachment, now titled "Original
demo test tone (no speech)", with no transcript. New remote bytes match the
local hash. The old remote object is absent and a fresh uncached request returns
object not found. A rollback-only authenticated-demo-role check confirms the
new note/object is visible and the old object is not. This check does not prove
audible playback on the phone. No real family media or Storage policies changed.

Source: [Apple macOS Tahoe licence](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf).

## Next bounded checks

1. Review the candidate screenshots; resolve the tree framing/overlap before
   using that view. Private subscription review images are uploaded and the
   USA/USD result is explained; finish the price-schedule check.
2. Rehearse the remaining review paths on the selected TestFlight candidate;
   keep destructive tests isolated and do not delete the main review login.
3. Owner approval of uploaded image drafts remains. Privacy, age and Content
   Rights declarations are saved; build 23's Apple export metadata is verified.
   The test-tone review note is saved and verified. Prices for all five launch
   countries are checked and recorded in the submission package.
4. The owner-authorized continuation staged build 23 with the four subscriptions
   and group; Apple shows six items ready to submit. Obtain separate submission
   authorization after the remaining checks. No Submit for Review or release
   action has been taken.
