# Heiro App Store submission package

Prepared 24 October 2026. **DRAFT: do not submit or release.**

## Family-growth/loading and security - 26 October 2026

The owner approved uncapped real-member totals, legacy caps 8/100/250, hourly
invite caps 20 per sender and 50 per family, existing cooldown/pending limits,
and blocking new people when storage is full. These and startup/photo-loading
improvements are implemented and tested. The approved growth backend and two
separately approved security fixes (server-only AI index writes and guarded push
dispatch) are deployed; disposable hosted checks passed with full rollback.
The historical allowance table below is superseded by the approved growth rules.
Build 26 does not contain the loading changes. Build 27 is uploaded, Validated,
Non-Exempt Encryption No, and assigned to Internal Beta (one tester). Build 27
replaced 26 in the saved version and persisted after reload with manual release
selected. At 10:53 SAST the existing draft again contained six items: app 1.0 /
1.0.0 (27), all four subscriptions, and Heiro Plans. Ready for Review does not
mean submitted or approved. The panel was closed without submission. The icon,
in-app images and billing settings are unchanged. Phone performance/functional
acceptance and owner store-copy/screenshot approval remain outstanding.
No submission or release is authorized. See `family-growth-and-loading-2026-10-26.md`.
Security scope and residual risks: `security-check-2026-10-26.md`.

## Family-name fix delivery - 25 October 2026

The owner approved name editing for every current family member. Both app
entry points and a narrowly scoped `rename_family` migration are implemented
locally; successor controls remain owner-only. All 201 Flutter tests passed
(50 existing skips), along with 14 database regression tests. The owner then
approved deployment, rollback-only verification, build 26 and replacing build
25 in the existing draft, without submission or release. The exact migration
is deployed and its live fixture checks passed with all test data rolled back.
Build 26 is signed and uploaded. Apple confirms Validated, Non-Exempt Encryption
No, and Internal Beta assignment with one tester. The owner confirmed "Renaming
works" on the requested build-26 phone check. Icons and in-app images remain
identical to build 25, which does not include this rename fix.

Build 26 is saved on app version 1.0, independently verified after reload with
manual release still selected. The app was temporarily unstaged to replace
build 25; the four subscriptions and Heiro Plans remain in the existing draft.
After a temporary Safari lock interruption, the app was added back to the same
draft. Apple confirmed six items at 21:24 SAST: iOS App 1.0 / 1.0.0 (26), all
four subscriptions, and Heiro Plans. The turquoise icon is unchanged. The
draft panel was closed, and the app status is Ready for Review. Nothing was
submitted or released. Store-copy/screenshot approval and the other outstanding
launch checks are not cleared by this rename test.
See `family-name-edit-2026-10-25.md`.

## Subsequent icon change - 25 October 2026

At that earlier checkpoint, build 1.0.0 (25) contained the middle turquoise tree
home-screen icon and build 24's single-family change. Existing in-app images
and launch artwork remain unchanged. Catalog, signing/configuration checks and
21 focused tests passed. Apple confirms Validated, Non-Exempt Encryption No,
and Internal Beta assignment (one tester).

Build 25 replaced build 23 in app version 1.0. Save persisted on a fresh page
load; manual release remains selected and Apple's build/Included Assets icons
show the bright turquoise tree. The app was added back to the same draft,
which then contained six items: iOS App 1.0 / 1.0.0 (25), all four subscriptions
and Heiro Plans. Apple shows Ready for Review, with no submission or release.
The owner confirmed build 25's correct home-screen icon and unchanged in-app
images on their phone. Store-copy/screenshot approval and final demo-password
rotation remain separate outstanding checks; this visual pass is not full
functional or iPad acceptance.
See `heiro-home-icon-2026-10-25.md` for artifact evidence and verification limits.

## Build and store review - 25 October 2026

- Apple independently shows build 1.0.0 (24) processed, Binary State Validated,
  Non-Exempt Encryption No, and assigned to Internal Beta with one tester.
  The owner answered "yes" to installing that version and opening their family,
  tree and an existing photo/voice memory. Record only those bounded iPhone
  checks as owner-confirmed, not full candidate or iPad acceptance.
- At this earlier checkpoint, the distribution draft selected build 23, was Ready for Review and
  retains manual release. Nothing was submitted, released or changed in Apple
  during this check, including build selection and screenshot order.
- The saved 2,167-character description and 163-character promotional text
  match the copy below. The accessibility tree truncates long text nodes; its
  shortened subscription paragraph is not evidence of a truncated saved field.
- The two public images per device remain uploaded. They are genuine simulator
  captures of build 23 source, not private subscription review images. Owner
  visual approval and a final-build comparison are still pending. A new build
  number alone does not make an otherwise accurate screenshot obsolete.
- Credential handling: after the earlier successful owner-only password reset,
  an automated accessibility response unexpectedly included Apple's private
  reviewer-password field during this check. The owner was informed. No value
  is reproduced in repository files; subsequent page output excludes these
  fields. Replace only the demo password again after metadata work and update
  Apple's private field before actual submission. Do not send the value in chat.

## Resume checkpoint - 25 October 2026

- Resumed at the owner's request to continue the submission forms. Fresh Safari
  inspection confirmed build 23 / 1.0.0 attached, the saved reviewer information,
  Prepare for Submission, one draft submission, and manual release selected.
- Saved `https://heiro.app/privacy.html` in App Privacy and verified the live
  public page. Completed all 14 data categories below. After the owner's specific
  approval to publish only the privacy label, Apple confirmed "Published a few
  seconds ago by Ross Strauss". No app review submission or release occurred.
- The privacy inventory used build 23 source `d66dcf4`, its archived Firebase
  privacy manifests, the public policy, and a read-only live schema inventory.
  It does not describe the unfinished, disabled screening branch as deployed.
- Age-rating questionnaire is saved and verified after reload. Apple's current
  rating is 13+ for most territories; Australia and Vietnam are 16+, Brazil 16+
  and Korea 15+. Older OS versions have separate ratings. No age gate or parental
  controls were claimed. The owner confirmed the intended ordinary family
  content, including infrequent swearing, difficult experiences and alcohol.
- The owner confirmed supplied graphics are owned/licensed. Content Rights is
  saved and verified after reload: "Yes, this app has the necessary rights to
  its third-party content." The macOS-generated demo speech was retired after
  checking its licensing limitation and replaced with an original test tone,
  with the owner's specific approval. Private review notes now explain the
  eight-second test tone (four beeps, no speech), verified after reload with
  2,393 characters remaining. All four previously missing declarations are
  completed. In the subsequent owner-requested continuation, Add for Review
  succeeded into the existing draft: Apple shows six items ready to submit
  (app 1.0/build 23, four subscriptions, Heiro Plans). The app is now Ready for
  Review. No validation error is shown. Submit for Review was not clicked.
  Manual release remains selected. This is metadata validation, not app approval.
- Selected build 23's Apple metadata shows Binary State Validated and App Uses
  Non-Exempt Encryption No. No export answer or binary was changed. All four
  current price schedules were inspected for the five launch countries; no
  prices or availability settings changed. Exact amounts are recorded below.
- The owner completed the demo-password reset, reported saving the replacement
  in Apple's private reviewer field, and confirmed signing into Heiro with the
  new password and seeing Morgan Family on 25 October. This is owner-reported
  phone/login and Apple-save evidence; no new credential was read or recorded.
  Other final device checks and owner approval of store copy remain pending.
  No billing, app code, schema or Storage policy changed in this form work.
  Only the isolated demo audio object and its single attachment row changed,
  as documented below; no real family content changed.
- At this earlier forms checkpoint, build 24 had been uploaded with processing
  pending. The subsequent build/store checkpoint above records its processed
  state and bounded phone result; the draft still selects build 23. See
  `single-family-launch-2026-10-25.md` for remaining candidate checks. The earlier
  demo-login confirmation did not itself reconfirm its installed build number.

## Resume checkpoint - 24 October, 23:07 SAST

Evidence below is from the owner's current Safari screenshots/accessibility
snapshots, not a new agent reload. It supersedes earlier unstaged-build notes.

- The owner added all four subscriptions and Heiro Plans to one iOS draft;
  the panel shows five items. These are Ready for Review, not submitted.
- Build 23, version 1.0.0, is attached to app version 1.0. The latest screenshot
  shows the Save checkmark and the build in the page's accessibility snapshot.
- Adding the app version was blocked by four required entries: Content Rights
  Information, age-rating questions, Privacy Policy URL in App Privacy, and
  App Privacy data-practices answers. The app remains Prepare for Submission;
  it is not yet the sixth item in the draft.
- Next requested task: fill these declarations from the actual selected build,
  deployed data practices and current Apple definitions, obtaining owner
  confirmation where an answer requires their rights/content attestation.
  Intended privacy URL: https://heiro.app/privacy.html. No declarations were
  completed in this checkpoint turn.
- Preserve the saved manual-release setting and verify it when resuming.
  No Submit for Review or release authorization has been given.
- A user-shared screenshot exposed the dedicated demo password field. Do not
  reproduce or save the credential. Arrange a replacement and update the
  private Apple reviewer field before actual submission; rotation is pending.
- Saved Apple drafts can be reopened through Draft Submissions. Closing the
  browser is not submission or deletion; unsaved form edits are different.
  Owner is considering pausing to conserve usage; no automatic resume is set.

Source: [Apple's saved draft submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/).

## Owner decisions

- Name: **Heiro**, spelled H-E-I-R-O.
- Initial territories: South Africa, United Kingdom, United States, Canada and Australia. No EU distribution and no automatic addition of future territories.
- Free download with the existing optional subscriptions.
- iPhone and iPad only for this release; Apple-silicon Mac and Vision Pro availability disabled.
- Manual release. Owner reviews store copy and completes final checks before separately authorizing submission. Approval by Apple must not automatically publish the app.
- Keep the working billing, storage and account-deletion behavior unchanged.
- Copyright holder/reviewer: Ross Strauss. Apple reviewer email approved as
  rossstrauss1@gmail.com; public support remains linebreakers@outlook.com.
- Owner approved the subscription service-level correction below, preserving
  prices, durations, product IDs and backend payment logic.

## Saved in App Store Connect

- App name: Heiro.
- English (U.S.) subtitle: Family stories, kept together
- Primary category: Lifestyle. No secondary category.
- Manual version release selected and saved.
- Free app-download pricing confirmed. The base currency is USD; this does not change StoreKit subscription currency or prices.
- Exactly five territories saved, each marked Available on App Release: Australia, Canada, South Africa, United Kingdom and United States.
- Mac and Vision Pro availability disabled and read back.
- Promotional text, description, keywords, Support URL, Marketing URL and copyright saved in the version draft and verified after reload.
- Private reviewer contact saved and verified after reload: Ross Strauss and the approved reviewer email. The owner-supplied phone is saved only in Apple's private reviewer contact, not this document or public copy.
- Version 1.0 is Ready for Review in the existing six-item draft after the
  25 October validation. Nothing submitted or released.

The subtitle and following copy are editable drafts, not owner-approved final marketing copy. Saved screenshots are in `docs/submission-evidence-2026-10-24/`.

Promotional text and description below are **saved drafts**. After the owner
focused the multiline field, entry and a subsequent reload confirmed the draft
and correct 7/1,833 remaining counters. Reviewer contact was saved separately
after the owner supplied the required phone number, then verified by reload.
The separate reviewer login and walkthrough notes are now saved and verified
after reload. Login was exercised on both simulators; the complete final-device
review rehearsal is still incomplete.

## Store copy for owner review

### Proposed decisions - not yet applied

Keep the name **Heiro**, subtitle **Family stories, kept together**, promotional
text, feature sections, storage allowances, AI permission/limits and subscription
disclosures below. No fixed currency prices are promised in the public copy.

Optional opening replacement for the first two description paragraphs:

> Heiro brings your family's photos, stories and voice notes together. Build a
> family tree, invite relatives and choose which memories to share.

This is a clarity improvement, not a submission requirement. The complete text
under Description below is still the saved Apple draft, not this proposal.

Recommended screenshot order for both device sizes: personal photo/voice memory
first, legacy profile/story second. This puts the core memory experience first.
Keep the held tree image out because its selector overlaps the top row. No
new design, image generation or additional screenshot set is proposed here.

| Proposed position | iPhone | iPad |
| --- | --- | --- |
| 1. Photo and voice memory | [View image](/Users/rossstrauss/Documents/GitHub/immortalink/immortalink/docs/app-store-assets-2026-10-24/iphone/03-photo-and-voice-memory.jpg) | [View image](/Users/rossstrauss/Documents/GitHub/immortalink/immortalink/docs/app-store-assets-2026-10-24/ipad/03-photo-and-voice-memory.jpg) |
| 2. Shared legacy story | [View image](/Users/rossstrauss/Documents/GitHub/immortalink/immortalink/docs/app-store-assets-2026-10-24/iphone/02-legacy-memory.jpg) | [View image](/Users/rossstrauss/Documents/GitHub/immortalink/immortalink/docs/app-store-assets-2026-10-24/ipad/02-legacy-memory.jpg) |

The iPad captures have more whitespace but remain genuine, readable app screens.
The photo/voice capture predates the approved demo-audio replacement: its
"Sunday picnic - sample recording" caption refers to the former fixture. Prefer
a fresh genuine capture with the current test-tone caption when finalizing that
image; do not paint over the existing screenshot or use the old audio fixture.
The phone smoke confirmation alone does not verify this visual match.

Apple asks for accurate metadata and screenshots of the app in use; its product
page guidance emphasizes the opening sentence and first screenshots. These are
the basis for the proposed ordering/copy polish, not a prediction of approval.
Sources: [App Review Guidelines 2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)
and [Product page guidance](https://developer.apple.com/app-store/product-page/).

### Promotional text

Bring your family's photos, stories and voices together. Build a family tree, invite relatives and preserve memories in personal vaults and shared legacy profiles.

### Description

Your family's stories deserve a place together.

Heiro brings photos, written memories and voice notes into family spaces you can return to and add to over time.

SAVE THE DETAILS THAT MATTER
Capture everyday moments, favourite stories and familiar voices. Add photos and recordings to a memory so the story stays with the moment.

BUILD YOUR FAMILY TREE
Create a family tree and invite relatives to join. Choose which memories appear in your family feed.

REMEMBER TOGETHER
Create shared legacy profiles for loved ones. Family members can contribute their own memories, photos and recordings to the same profile.

EXPLORE MEMORIES WITH OPTIONAL AI
Ask questions about saved memories and use voice transcription with your permission. Relevant content is sent to OpenAI only after you enable AI processing. AI features have usage limits and may make mistakes. You can keep saving and reading memories without enabling them.

CHOOSE THE SPACE YOUR FAMILY NEEDS
Start with Free Family and 500 MB of shared storage. Optional Heiro Family subscriptions provide 10 GB; Heiro Legacy provides 50 GB. Monthly and annual options are available. One family member sponsors the plan, and the allowance is shared within that Heiro family.

STAY IN CONTROL
Report a specific memory or member, block a member, manage Apple subscriptions and request account deletion from the app. Contributions to shared legacy profiles remain with the family after a contributor deletes their account, as described in our Privacy Policy.

SUBSCRIPTIONS
Prices are shown in the app before purchase. Payment is charged to your Apple Account at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the current period ends. Your account is charged for renewal within 24 hours before the end of the current period. Manage or cancel your subscription in your Apple Account settings. Cancellation stops future renewal; paid access continues until the end of the current period. Deleting a Heiro account does not cancel an Apple subscription.

Privacy Policy: https://heiro.app/privacy.html
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

### Keywords

memories,tree,photos,voice,notes,legacy,heritage,archive,relatives,albums,history,journal

### URLs

- Support URL: https://heiro.app/
- Marketing URL: https://heiro.app/
- Privacy Policy URL: https://heiro.app/privacy.html
- Terms: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

The public root was fetched successfully on 24 October. It identifies Heiro and includes a working mailto contact to linebreakers@outlook.com and the privacy link. It is an existing lightweight site, not a new hosting purchase. Privacy was separately checked in the preceding audit.

### Copyright

Owner approved: `2026 Ross Strauss`. Do not infer a registered company from the app brand.

## Subscription package

Keep identifiers unchanged:

| Product ID | Saved reference and English (U.S.) display name | Saved description |
| --- | --- | --- |
| everroots.family.monthly | Heiro Family Monthly | 10 GB shared family storage, billed monthly. |
| everroots.family.annual | Heiro Family Annual | 10 GB shared family storage, billed annually. |
| everroots.legacy.monthly | Heiro Legacy Monthly | 50 GB shared family storage, billed monthly. |
| everroots.legacy.annual | Heiro Legacy Annual | 50 GB shared family storage, billed annually. |

Group reference name and English (U.S.) display name are saved as **Heiro Plans**; the group uses the app name **Heiro**. Bundle ID stays `com.everroots.app`, SKU `everroots-ios`, Apple app ID `6802720270`, subscription group ID `22339684`.

All four product reference names, localized names/descriptions and reviewer notes were saved and read back on 24 October. Notes explain family-level sponsorship, separate AI permission and limits, and Apple cancellation independent of Heiro account deletion. This sharing is not Apple Family Sharing; that Apple setting was left off.

Each product previously included Ireland. Ireland alone was removed, and all four now show **5 of 175 countries or regions selected**: Australia, Canada, South Africa, United Kingdom and United States, with future automatic territories off. Product IDs, durations and price fields were not edited. Annual products retain **1 Year Upfront**; the optional monthly-with-12-month-commitment purchase option was not enabled. This was not a complete price-schedule audit.

**Service levels saved and verified after reload.** After the owner grouped the pairs, the editor showed both Legacy products at level 1 and both Family products at level 2. Save completed, and a full page reload confirmed Legacy Annual 1, Legacy Monthly 1, Family Annual 2 and Family Monthly 2. This is the approved catalog upgrade/crossgrade correction, not a change to price amounts, durations, original purchaser binding or backend family entitlement logic. StoreKit switching behavior still needs the bounded final-candidate check; saved configuration alone is not device proof.

Evidence: `docs/submission-evidence-2026-10-24/subscription-levels-saved.jpg` shows the persisted 1/1/2/2 grouping after reload. Earlier `subscription-names.jpg` and `subscription-levels-pending.jpg` are historical pre-correction evidence, superseded for service-level status.

All four subscription review screenshot fields are now filled and verified after reload. The owner's unchanged Family screenshot is attached to Family Monthly and Annual; the unchanged Legacy screenshot is attached to Legacy Monthly and Annual. Both originals are 1170 x 2532 RGB PNGs without alpha. Apple identifies these as private App Review images, not public store artwork. The source images and provenance are in `docs/app-store-assets-2026-10-24/`; persisted-page evidence is in `docs/submission-evidence-2026-10-24/*-review-image.jpg`.

The owner reports TestFlight **build 23**, **USD** currency and subsequently **USA** Storefront in Apple billing details. This resolves the reported dollar-price concern: USD is expected for the US storefront despite physical presence in South Africa. No payment-logic fix or account change is indicated by this result. The screenshots show the expected two paid tiers with monthly/annual choices, plus Free Family; four paid products do not indicate an outdated app. The source displays Apple's returned product price, not a hard-coded dollar fallback. This is owner-reported US-storefront evidence, not a new ZAF/ZAR test or proof of every billing path. Product count and exact Result were not supplied; no failure was reported. Preserve the earlier billing lifecycle evidence.

The current price schedules were inspected on 25 October as recorded below;
the bounded USD/storefront concern is explained above. After the image-upload
pass, the owner added all four products and the group to one draft. The app was
subsequently added to the same draft, now six items **Ready for Review**. This is
staging, not submission. No prices, IDs, durations, backend payment logic or
public screenshots changed during these checks.

### Verified prices and customer allowances - 25 October 2026

Read-only App Store Connect checks used each product's View all Subscription
Pricing > Current Prices > Starting Price, not the price-conversion calculator.
Each schedule showed only Starting Price, with no other scheduled price changes.
Prices may exist for all 175 regions; that is not the sale-availability setting,
which remains the five approved territories. Annual options are paid upfront.

| Storefront/currency | Family monthly | Family annual | Legacy monthly | Legacy annual |
| --- | ---: | ---: | ---: | ---: |
| South Africa / ZAR | 119.99 | 1,199.99 | 199.99 | 1,799.99 |
| United States / USD | 5.99 | 59.99 | 9.99 | 99.99 |
| United Kingdom / GBP | 5.99 | 59.99 | 9.99 | 99.99 |
| Canada / CAD | 7.99 | 79.99 | 12.99 | 129.99 |
| Australia / AUD | 9.99 | 99.99 | 14.99 | 149.99 |

Current live `everroot_limits` definition was read without accessing family
records. These are configured family allowances, not new runtime tests of every
limit. The current monthly transcription limits supersede older migrations that
listed larger allowances.

| Allowance | Free Family | Heiro Family | Heiro Legacy |
| --- | ---: | ---: | ---: |
| Shared storage (display label) | 500 MB | 10 GB | 50 GB |
| Family accounts | 8 | 20 | 30 |
| Legacy profiles | 8 | 100 | 250 |
| Memories | 100 | 1,000 | 3,000 |
| Photos | 100 | 2,000 | 6,000 |
| Voice notes | 25 | 500 | 1,500 |
| Maximum voice-note duration | 2 min | 2 min | 5 min |
| AI responses / month | 20 | 500 | 1,500 |
| Transcription / month | 10 min | 120 min | 400 min |
| Invitations / month | 25 | 50 | 100 |
| Pending invitations | 10 | 25 | 50 |

Allowances are pooled, not multiplied by each member. Monthly and annual products
at the same tier provide the same allowances; annual billing does not make AI or
transcription unlimited. AI remains optional and requires separate permission.
The live period helper uses the calendar month, not an annual prepaid quota.

Payment path: StoreKit charges the purchaser's Apple account; Heiro's server
validates the transaction with Apple and applies the entitlement to the bound
Heiro family. One sponsor pays; other members share the allowance using their own
Heiro logins. Sponsorship does not expand private-vault access and is distinct
from Apple's Family Sharing switch. The original purchaser manages renewal;
another member can sponsor after paid coverage ends. Cancellation normally keeps
coverage to its paid end, then Free limits apply. Existing content is not purged
by plan expiry; over-quota additions are blocked until space is freed or the plan
is renewed. Account deletion does not cancel the Apple subscription.

Apple deducts applicable commissions/taxes and pays net proceeds to the registered
bank account subject to its payout requirements. The price schedule's Year 1 / 2
proceeds columns are not proof of Small Business Program enrollment or net profit.
Hosting, AI, email and other business costs remain separate.

References: [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/),
[Apple payouts](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments).

Sources: [Apple review screenshot purpose](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) and [StoreKit localized display price](https://developer.apple.com/documentation/storekit/product/displayprice).

## Reviewer instructions draft

The owner-approved `linebreakers+apple-review@outlook.com` account now exists,
with an isolated fictional Morgan Family. The bare Linebreakers address was
already a real account and was left untouched. The unique demo password is
saved only in Apple's private reviewer field, not this package. Username,
password match, original 1,503-character notes, manual release and draft status
were verified after a full reload on 24 October. On 25 October only the notes
were revised to describe the test tone; saved length is now 1,607 characters
(2,393 remaining), verified after reload. No credentials were edited in that
pass. Screenshot evidence deliberately omits credentials:
`docs/submission-evidence-2026-10-24/reviewer-draft-saved.jpg`.

Later on 25 October, a read-only Auth check confirmed the exact demo account
exists, is email-confirmed, has an email identity/password and is not disabled.
Recent failed reset requests were rejected for invalid email format, which the
client misleadingly presents as a connection error. After re-entering the exact
address, the owner reported success, saved the new password directly in Apple,
and confirmed a fresh Heiro sign-in showing Morgan Family. No password, reset
link or token was collected, and no duplicate account was created. Treat the
new Apple save and phone login as owner-confirmed, not an agent credential read.

Login, personal memories, the sample photo, tree and legacy story were inspected
on iPhone and iPad simulators built from the TestFlight 23 source. Photo/audio
bytes were separately verified through ordinary authenticated Storage access.
This is not a complete final-device rehearsal or proof of audible playback.
On 25 October, the owner authorized replacing only the synthetic demo speech
with an original eight-second test tone. One attachment row now references
`review-test-tone.wav`, titled "Original demo test tone (no speech)", with a null
transcript and duration 8. The former live synthetic object was removed. New
bytes match the local SHA-256; an uncached old-object request returns object not
found. A rollback-only authenticated-role check shows the demo can select the
new attachment/object and not the old object. This was not a fresh password-login
or audible phone-playback test. Apple review notes now explain the test tone and
how to create a spoken voice note, verified after reload. See the asset manifest
for exact provenance.
The fixture has one signed-in member, so the normal home feed excludes that
member's own vault and is empty. Multi-member and destructive review paths below
remain to be rehearsed with separately authorized disposable identities.

Three genuine screenshot candidates per device are saved in
[the asset manifest](app-store-assets-2026-10-24/README.md). The two non-tree
JPEGs per device are uploaded as editable English (U.S.) store drafts.
The tree's initial selector overlaps part of its top row; hold that candidate
for framing/layout review. The other candidates still need owner selection and
confirmation against the final candidate. No private family screenshots were used.

The following full rehearsal checklist is broader than the concise notes saved
in Apple. Do not describe every step as passed merely because the demo exists.

1. Sign in using the dedicated account supplied in App Review Information.
2. Open the demo family, its family tree and the sample shared legacy profile.
3. Create a harmless text memory, add a sample photo and short recording, preserve it and reopen it.
4. Use the per-memory menu to report the disposable sample. Member reporting/blocking are separate from hiding a specific memory.
5. Open Settings > Family plan to inspect localized subscription prices, restore purchases or open Manage Apple subscriptions. One purchaser sponsors one Heiro family; this is not Apple's Family Sharing feature.
6. AI is optional. The permission prompt identifies OpenAI and the relevant data. Declining must preserve normal non-AI saving/reading. Permission can be withdrawn in Settings > AI data permission.
7. Settings > Delete account provides immediate deletion after the confirmation steps. Deletion does not cancel an Apple subscription; management is offered separately. Personal account data is removed, while contributions to shared legacy profiles remain for the remaining family.

Do not supply Ross/Frank's real family accounts. Create a separate deletion-test identity so the main reviewer account survives review. Store passwords only in the protected App Review credentials field/approved secret store, never in this document or screenshots.

## Published privacy declaration - 25 October 2026

Saved and published in App Store Connect with the owner's explicit approval.
All categories are declared **not used for tracking**. There are no advertising
purposes selected. "Contacts" describes the family social graph, not device
address-book access. "Coarse Location" describes the optional user-entered memory
place, not GPS collection.

| Apple data type | Purpose | Linked to identity |
| --- | --- | --- |
| Name | App Functionality | Yes |
| Email Address | App Functionality | Yes |
| Coarse Location | App Functionality | Yes |
| Contacts | App Functionality | Yes |
| Photos or Videos | App Functionality | Yes |
| Audio Data | App Functionality | Yes |
| Customer Support | App Functionality | Yes |
| Other User Content | App Functionality | Yes |
| User ID | App Functionality | Yes |
| Device ID | App Functionality | Yes |
| Purchase History | App Functionality | Yes |
| Other Usage Data | App Functionality | Yes |
| Other Diagnostic Data | App Functionality; Analytics | Yes |
| Other Data Types | Analytics | No |

Evidence: build 23 explicitly stores push tokens/device IDs with `user_id` in
`user_push_tokens`; family relationships, memories, reports, entitlement and quota
records are account/family-linked. Firebase Messaging's archived manifest declares
Device ID, Other Data Types and Other Diagnostic Data; Firebase Installations
declares diagnostic analytics. The app-level linked declaration overrides the
SDK-only unlinked default where the app attaches an account. Other Data Types
covers the SDK's unlinked metadata. No Firebase Analytics/Crashlytics or advertising
dependency was found in build 23. No real family content was read for this audit.

Sources: [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)
and [Firebase Apple-platform disclosures](https://firebase.google.com/docs/ios/app-store-data-collection).

## Age rating and content rights - 25 October 2026

Age answers saved and verified after reload:

- UGC and social media: Yes. Social media disabled for under-13s: No.
- Parental controls, age assurance, unrestricted web access, person-to-person
  messaging/chat and advertising: No. Optional AI companion is not represented
  as a person-to-person chat feature.
- Profanity, horror/fear, alcohol/tobacco/drug references and mature/suggestive
  themes: Infrequent, consistent with the owner's intended family histories.
- Sexual content/nudity, graphic sexual content, all violence/weapons categories,
  medical/treatment information, simulated gambling and contests: None.
- Health/wellness topics, gambling and loot boxes: No.
- Calculated rating accepted without override or optional suitability URL.
  Current OS rating is 13+ in most territories, with Australia/Vietnam/Brazil
  16+ and Korea 15+. The older-than-26 OS rating is generally 12+ with regional
  exceptions. This declaration does not implement or prove an age gate.

Content Rights: the owner confirmed graphics are owned/licensed. The generated
picnic image has original project provenance. The prior macOS synthetic demo
speech was replaced with the owner-approved original test tone before completing
the rights declaration. Apple now records that the app contains, shows or
accesses third-party content and has the necessary rights. Both the Done step
and App Information Save completed; a full reload confirmed the saved answer.

Export-compliance metadata verified on 25 October: the selected build 23's Apple
record explicitly shows App Uses Non-Exempt Encryption No and Binary State
Validated. The source/archive's absent `ITSAppUsesNonExemptEncryption` key was
not used to infer a new answer. No declaration or binary changed in this check.

Source: [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).

## Remaining gates, kept separate

### Required submission package

- Owner review of description, subtitle, keywords, promotional text and copyright.
- Completed: selected-build export metadata, Content Rights, age rating, App
  Privacy and its policy URL. Final Add for Review validation passed and the
  app is staged with all four subscriptions and the group (six items). This
  does not establish approval or complete the owner/device checks below.
- Completed: current price-schedule check for all five launch countries. The
  reported USA/USD combination explains the phone currency. All four private
  subscription review images, rebranding, five-country availability and the
  approved 1/1/2/2 service-level correction are saved and verified.
- Dedicated reviewer login is created and previously verified on both simulators.
  On 25 October, the owner confirmed resetting the exposed demo password, saving
  its replacement directly in Apple's private reviewer field, and signing into
  Heiro with it to see Morgan Family. No credential was read in that owner-only
  login step. The later accessibility exposure above requires one final demo
  password rotation after metadata work. Other final-device/multi-member steps
  remain unverified; the installed build number was not reconfirmed in that
  login check. Contact name, email and phone are saved.
- Two genuine screenshot drafts per device are uploaded using only synthetic
  content. Owner approval, tree-framing review if that image is wanted, and
  final-build match remain pending. See the asset manifest; no private family
  screenshots were used in those public store drafts. The owner separately
  supplied phone paywall images for private subscription review; all four slots
  are filled and verified. No purchase or restore was requested.
- Build 25 is selected and saved in the App Store version and staged with all
  four subscriptions and Heiro Plans in the six-item draft. Its new icon is
  verified in Apple's Included Assets and the exported package. Build 24's
  basic iPhone smoke check is owner-confirmed; build 25's home-screen icon and
  unchanged in-app images are now also owner-confirmed on the phone. These
  bounded checks do not complete all acceptance checks below.

### Final candidate acceptance

Preserve earlier passed payment, report, Hide/Restore, media and deletion evidence. Do not redo destructive tests on established accounts.

- Record exact TestFlight build/device/OS. Test the actual candidate on iPhone and iPad.
- Fresh sign-up/confirmation/reset; invitation and join; relaunch/sign-out/account switch.
- Save/edit/open a memory with photo and short recording; correct family visibility.
- Report a disposable specific memory, receive alert, inspect it, Hide, verify new access denied, Restore.
- AI permission decline/grant/withdrawal; normal non-AI use still works.
- Localized catalog/restore and one bounded sandbox purchase path if the candidate/catalog changes; never make repeated purchases after errors.
- Deletion disclosure and Apple-management access; destructive deletion only on a disposable account, with shared legacy retention checked.
- Large text, iPad layout, network failure/retry and crash smoke check.

### Explicit unresolved product/review risk

Apple Guideline 1.2 calls for a method of filtering objectionable material, report handling, blocking and contact information. Report/block/review/takedown are deployed and user-tested. The new text/photo screening pipeline is **local-only, default-off and not deployed**. The live publication guard inspected in the audit rejects restricted accounts; it is not an active text/photo classifier.

Do not claim filtering is deployed or treat staged test totals as hosted proof. Equally, Apple does not explicitly require a paid AI system or a human to watch every upload. The earlier broad screening backlog is not automatically the minimum launch scope. Resolve and document a proportionate filtering approach before declaring the package ready; do not expand or deploy it during metadata preparation.

### Operational checks, not automatic new feature projects

Recheck alert inbox ownership, budget/usage caps, backup and recovery evidence, serious outstanding security findings and support escalation. Identify concrete missing evidence rather than reopening every historical checklist item.

### Review versus public release: 24 October verification

- Apple's rejection message identifies the issues/guidelines. We can reply with
  clarification and evidence. Metadata-only changes can reuse the build;
  build fixes require a corrected build and review. Follow the specific review
  message rather than resubmitting blindly. Approval is not exhaustive QA or a
  promise that all remaining issues are minor.
- Manual release was saved. The owner has now staged the subscriptions/group
  using Add for Review; no authorization to submit or release was given. Once separately
  authorized and approved, manual release allows a pre-publication operations
  checkpoint without putting the app on sale automatically.
- Live management API: project `vbzyvaylfdhwowdbodmk` is ACTIVE_HEALTHY;
  organization `ljyeobpepjgeksciwnbu` is on Free. A read-only aggregate of
  `storage.objects` returned 19 objects / 13,548,282 metadata bytes. This is a
  file-size snapshot, not a billing/egress report or load-test result.
- Current provider pricing lists 1 GB file storage on Free, shared across this
  app's families, not 1 GB per family. Free can pause for inactivity. Pro starts
  at USD 25/month, with 100 GB included file storage and metered overages. No
  upgrade, billing change or paid add-on was performed or authorized.
- Recommendation, not an Apple-mandated tier: an active Free project with
  adequate test headroom can support review, but approve suitable paid capacity
  and verify recovery before the public paid launch. Heiro advertises 10/50 GB
  family allowances, so deferring the Free-to-Pro decision until after paying
  users arrive is not the proposed release sequence. Further compute/capacity
  increases should follow measured demand rather than buying large tiers now.
- Pro's daily database backups do not include Storage object bytes. Database
  AND media recovery remain unverified here; upgrading alone does not prove
  recovery. Existing working payment/storage behavior was not changed.
- Optional polish can wait. Required package fields, a working reviewer path,
  final-candidate checks and the unresolved proportionate filtering decision
  above are not reclassified as post-launch tweaks.

References checked for this decision:
[Apple review replies](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages),
[review status and resubmission](https://developer.apple.com/help/app-review/after-submitting-for-review/review-status),
[manual-release status](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses),
[Supabase pricing](https://supabase.com/pricing),
[production checklist](https://supabase.com/docs/guides/deployment/going-into-prod),
[database versus media backups](https://supabase.com/docs/guides/platform/backups).

## Source links

- [Apple submission steps](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Apple user-generated content guideline](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
- [Apple subscription configuration](https://developer.apple.com/app-store/subscriptions/)
- [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple age-rating setup](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)

## Submission lock

No Add for Review, Submit for Review, public release, new build upload, production deployment, legal acceptance or payment-logic change is authorized by this package. Prepare, verify, obtain owner approval, then submit only on a later explicit instruction.

