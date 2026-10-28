# Heiro filtering: privacy, cost and coverage

Assessment date: 23 October 2026. Design comparison only, not implementation,
deployment approval, legal clearance or evidence of App Store acceptance.

## Owner decision after the comparison

The owner then said, "if theres no ai cost we can do that". The selected local
implementation direction is the free standalone OpenAI text/photo moderation
endpoint, not self-managed inference. Explained that infrastructure and operator
time still cost money; paid moderation transcription remains off. This changes
the earlier recommendation to benchmark self-managed filtering first.

Production screening stays disconnected. Separate end-user permission, bounded
work, publication enforcement, review integration and audio/video safeguards
remain required. Choosing a zero-fee endpoint does not resolve privacy or give
permission to scan archives. Deployment requires separate approval.

Local-only follow-through: migration
`20261023110215_content_screening_permission.sql` adds private, per-account,
purpose/version-specific permission, isolated from optional AI-chat consent.
Withdrawal advances a revision so later acceptance cannot revive an old claim.
Eight new tests plus the existing consent/adapter tests pass (23 focused total);
the database suite passes 112 tests with one separate concurrency suite skipped.
There is no new phone prompt, worker, queue or publication gate yet. This migration
alone does not enable screening and has NOT been deployed.

Use Apple's device-sensitive-media framework only as an optional viewer
protection, not as the source of server moderation decisions. Keep the working
report/block/review/takedown controls whatever classifier is eventually chosen.
No current option is a complete, verified launch solution.

## What the repository establishes

- `supabase/functions/_shared/content_screening.mjs` is a disabled-by-default
  OpenAI text/photo adapter. Searches found no production caller. It deliberately
  does not authorize publication. Existing mocked tests are not quality benchmarks.
- `lib/screens/create_memory_screen.dart` inserts the memory, then uploads media
  and inserts attachment references. Other upload paths exist in personal and
  legacy vaults and profile setup. A check in one composer would be incomplete.
- `lib/utils/vault_media_upload.dart` offers both Photos and Videos.
  `lib/utils/media_upload_policy.dart` permits photos, video and voice. Therefore
  a text/photo-only proposal omits two supported media types, not just voice.
- `ios/Podfile` targets iOS 15. `ios/Runner/Runner.entitlements` has no Sensitive
  Content Analysis entitlement. No corresponding native filter or local speech
  integration was found. These are new integrations, not switches to turn on.
- Current AI consent covers optional chat/transcription, not automatic safety
  screening. It must not silently become permission for a new purpose. Audio
  transcription remains optional; neither its allowances nor payments change.
- The family-feed switch is not sufficient proof of owner-only access. The
  checked media helpers authorize vault/family access independently of that
  switch. Define sharing by actual recipient access, not feed discovery. Local
  unsaved drafts must remain outside screening; saved-content visibility needs
  an explicit access matrix before promising a private/shared distinction.

This assessment read source and existing deployment records, not live family
content. It did not re-query production definitions, measure provider usage,
install a model or run inference. Subsequent permission tests used isolated local
databases; adapter tests mocked the provider. Prior phone acceptance remains
separate evidence.

## Options

| Approach | Data boundary | Incremental running cost | Main limitation / effort |
| --- | --- | --- | --- |
| Apple Sensitive Content Analysis | Detection and results stay on the device | No metered cloud inference call; development and device testing remain | iOS 17+ baseline, user-controlled availability, visual media only. Supplement, not a server moderation queue. |
| Our own bundled device model and text rules | Classifier can run without sending inputs elsewhere | No hosted inference charge; app size, battery and maintenance costs | New Flutter/native integration, model licensing, device/language tests and bypass handling. No selected model or audio/video solution. |
| Self-managed backend rules/models | Heiro controls the software; its hosting provider still processes data | CPU/RAM, transfer, queueing, monitoring and maintenance | Stronger server enforcement is possible, but heavier runtime and model validation are new work. Not automatically cheaper or legally exempt. |
| External OpenAI moderation | New shared inputs go to an external AI processor | Standalone moderation API fee is zero; infrastructure and human review are not | Simplest reuse of current adapter for text/photos, but requires an acceptable privacy design and does not directly classify audio/video. |

Apple says Sensitive Content Analysis is for viewer protection, its detection
results must not be transmitted off-device, and analysis can be disabled by user
settings or missing entitlement. Do not send its flags to Heiro's review queue
or require a positive result from it to publish.
[Apple framework documentation](https://developer.apple.com/documentation/SensitiveContentAnalysis/detecting-nudity-in-media-and-providing-intervention-options)

A self-managed model is different from that Apple framework. Candidate review
found NSFWJS provides five visual categories centered on sexual imagery, not a
general violence, consent or child-safety detector. Detoxify warns about profanity
false positives and lists seven supported test languages, excluding Afrikaans
and isiZulu. These illustrate coverage gaps, not approved model selections.
Do not use headline accuracy as Heiro accuracy; check code, weights, license and
test-set provenance separately.
[NSFWJS](https://github.com/infinitered/nsfwjs),
[Detoxify](https://github.com/unitaryai/detoxify)

Hosted Supabase Edge Functions currently allow 256 MB memory and 2 seconds CPU
per request. Lightweight rules may fit; a full text/image/speech stack cannot be
assumed to fit. A separate worker may be necessary. Using Google Cloud because
Firebase already hosts the website would still introduce a new family-content
processing flow, requiring its own disclosure, access, region and cost review.
[Supabase runtime limits](https://supabase.com/docs/guides/functions/limits)

OpenAI's moderation endpoint accepts text/images, not audio. Category support
differs by modality; an unsupported image category is not a clean finding.
Known or suspected CSAM must not be sent to it. OpenAI documents no training by
default and lists no abuse-log or application-state retention for moderation;
that is still external processing, not a promise that data never leaves Heiro.
[Moderation documentation](https://developers.openai.com/api/docs/guides/moderation),
[Data controls](https://developers.openai.com/api/docs/guides/your-data)

## Audio, video and context

- On-device speech recognition is conditional on device/language support. An
  on-device-only design must check support first and never silently fall back to
  network recognition. Transcripts also miss tone and non-speech content.
  [Apple speech support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- Reusing a transcript already created with permission can reduce duplicate
  work, but a new moderation purpose still needs a proper privacy basis. It
  cannot cover recordings whose authors declined transcription.
- Video includes moving images and potentially speech. A thumbnail check or
  sparse sampled frames alone leaves gaps. No video pipeline was evaluated.
- Models cannot reliably establish whether an intimate image was shared with
  consent. Personal grief, illness, historical violence or discussion of abuse
  must not automatically be treated as prohibited behavior.
- Broad human pre-review avoids a model vendor but exposes more family content
  to a person and creates delay and labour cost. The present console is scoped
  to reported cases, not permission to browse all new uploads.
- Unsupported inputs need an explicit product decision before launch. Do not
  silently approve them, disable existing voice/video features, or turn on paid
  transcription. Restrictions on launch scope require the owner's agreement.

## Cost comparison and margin discipline

No measured per-family cost or net-margin guarantee is available yet. Current
plan allowances are not a dollar ceiling (`docs/ai-cost-controls.md`). Apple net
proceeds, free users, storage/egress, existing AI and support all share the budget.

Illustrative workload: 10,000 screening inputs per month, not a usage forecast.

- Device model: zero hosted inference requests; development, distribution and
  user-device resources still matter.
- OpenAI standalone moderation: US$0 classifier API charge at current pricing,
  excluding storage transfer, worker invocations, retries, audio and review.
- Self-managed CPU sensitivity example, NOT a quote or a measured model:
  assume one request/input, 1 vCPU, 1 GiB, 1-5 billable seconds/input and no
  continuously warm instance. At the published Iowa request-based Cloud Run
  rates, compute plus requests would be US$0.269-1.329 before free allowances.
  At an illustrative budgeting rate of R20/US$, that component is R5.38-26.58.
  This is not a current FX quote, selected region or total budget. Excludes cold
  starts/model loading beyond assumed time, transfer, builds, storage, logs,
  retries, engineering and review. There is no evidence a chosen model fits
  this memory or time assumption; actual cost can be substantially higher.
  [Cloud Run pricing](https://cloud.google.com/run/pricing)

Human review sensitivity: if 1% of 10,000 inputs need two minutes each, review
takes 200 minutes (3 hours 20 minutes). At 5%, it takes 1,000 minutes (16 hours
40 minutes). Neither rate nor duration is measured. Operator time can outweigh
raw compute even when Ross initially performs it without a salary.

Before rollout, calculate an incremental budget from actual net receipts and
an agreed target margin, subtracting existing costs. Include free-account usage.
Enforce global and per-account work limits, bounded bytes/duration, duplicate
suppression, capped retries and an atomic work reservation before processing.
Provider billing alerts and maximum instance counts alone are not hard monthly
spend ceilings. Exhaustion must preserve saved content and show a clear pending
sharing state with recovery, not delete memories or silently publish unchecked
items. The 10-report limit is separate from any future screening-work budget.

## Acceptance requirements before rollout

1. Start locally with synthetic text and lawful, rights-cleared fixtures. Do not
   use family archives, upload samples to a vendor or obtain illegal material.
   Harmless fixtures prove resource handling, not harmful-content detection.
2. Measure bounded worker resource use, latency, formats and estimated total
   cost. Test English/Afrikaans and any other supported launch languages, benign
   sensitive stories and realistic false positives. Record provider/model version
   and coverage gaps. No real family content may be used as a benchmark.
3. Design server publication checks independently of the classifier. Tie a
   result to the exact content revision and attachment bytes. Cover edits,
   attachments added later, legacy contributions, avatars and older clients;
   prevent direct API or signed-link access bypassing a pending decision.
4. Regression-test storage/quota, account deletion/legacy retention, Hide/Restore,
   consent withdrawal, timeout/budget recovery and normal photo/voice playback.
   No deployment without separate approval and disposable-fixture verification.
5. Resolve audio/video handling and operator workload before treating filtering
   as complete. No automatic banning or deletion on a model score.

Apple requires filtering alongside reporting/blocking/contact/response; it does
not mandate a specific AI vendor. Third-party AI sharing needs explicit
disclosure and permission. Reporting alone or a keyword list is not proof of
adequate filtering. Obtain qualified privacy advice on lawful purpose,
minimization, children's/other people's data and international processing before
activation; self-hosting does not remove those obligations.
[Apple guidelines](https://developer.apple.com/app-store/review/guidelines/),
[POPIA](https://www.justice.gov.za/legislation/acts/2013-004.pdf)

The comparison, checkpoints and the isolated local permission foundation were
written. No production settings, Flutter app code, subscriptions, storage rules,
model downloads, real screening requests, public privacy statements or App Store
submission were changed.
