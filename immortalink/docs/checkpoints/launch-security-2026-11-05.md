# Launch security implementation checkpoint — 5 November 2026

**6 November addendum:** private R2 media backup is now enabled, the initial 50-file
inventory is verified, and isolated generated-file recovery passed. The
[separate backup checkpoint](media-backup-launch-2026-11-06.md) records the scoped
deployment, cost guards and limitations. The entries below otherwise record the
original 5 November batch.

## Scope

Ross authorized the launch security batch, chose a US$2 daily AI ceiling and separately approved the included Micro upgrade and brief restart. Ross personally upgraded Resend to Pro. Existing uncommitted Flutter work was preserved. This batch changed backend handlers, three database migrations and the private business dashboard. It did not submit or edit the App Store draft, upload TestFlight, reinstall Heiro, change Apple billing products, move contributions, retrieve customer memory contents or send test emails.

## Live deployments

Project: `vbzyvaylfdhwowdbodmk`.

| Local migration | Remote version | Name |
| --- | --- | --- |
| `20261105141230_launch_text_and_index_bounds.sql` | `20261105155632` | `launch_text_and_index_bounds` |
| `20261105142822_launch_global_ai_budget.sql` | `20261105155656` | `launch_global_ai_budget` |
| `20261105150605_business_owner_mfa_required.sql` | `20261105155757` | `business_owner_mfa_required` |

Remote versions differ because the MCP migration tool assigns deployment timestamps. Do not blindly push these files again as pending migrations; reconcile history before any future CLI push.

| Function | Live version | Supabase deployment bundle hash (`ezbr_sha256`) |
| --- | --- | --- |
| `vault_view_bundle` | 11 | `19bd81ef509d874404162197cbc5d63ef9e64784dc82e13d2b130a426b9f479a` |
| `index_memory` | 33 | `b9d041267f0436fcf73af69bb87aa532ce93fe31591b85e8780937d6c1659b69` |
| `index_voice_note` | 27 | `023ecbbaaaf1684a73faa6e63fb94753ca755caa5abb05e02999dfc54ac0f213` |
| `vault_ai_chat` | 90 | `13c1b45fe9b5018b46335a01a96c0be3d372cd76096871b9dc96859a2dbd6e2e` |

All retain JWT protection. Deployed source files matched the prepared files. `index_voice_note` uses explicit import-map path `index_voice_note/deno.json`. An initial deployment attempt failed on an old inferred import-map path; the corrected deployment succeeded and was independently read back.

The private dashboard was published to <https://immortal-ink-ba580-business.web.app>. Independently downloaded HTML and JavaScript matched the tested local source. No-store caching and restrictive response security headers were verified. On 5 November 2026, Ross confirmed: **“Dashboard opens after verification.”** This completes user-reported live owner enrollment/login acceptance alongside the existing database enforcement tests. No setup key or verification code was requested or recorded. Recovery has not been verified.

## Infrastructure and email

- Micro upgrade reviewed at US$0 additional/month, applied after explicit restart approval. Safari showed Micro selected with 1 GB memory after restart.
- Management API returned `ACTIVE_HEALTHY`. SQL at `2026-11-05 16:23:59 UTC` succeeded and showed Postgres 17.6, restarted at `16:16:22 UTC`.
- A subsequent independent SQL read confirmed enabled US$2 guard, zero remaining synthetic reservations, active retention job, and denial of direct budget reservation/ledger reads to ordinary clients.
- Supabase Spend Cap remains enabled; no disk expansion or optional paid add-on selected.
- Resend dashboard confirmed Transactional Pro, US$20/month, 50,000 emails and no daily limit. Transactional, automation and inbox overages and the domains add-on were off.
- Current Heiro SMTP/safety keys are sending-only and restricted to verified `auth.heiro.app`. Automatic bounce/complaint suppression is enabled. Existing legacy keys were not revoked without a dependency review.
- At this 5 November checkpoint, no media backup destination existed. This gap is now addressed by the 6 November backup deployment linked above. Database backups alone do not contain actual uploaded files.

## Verification

- 453 local database checks passed; 14 concurrency cases were skipped in that invocation. The new real-Postgres budget/index concurrency suite passed separately: 25 simultaneous US$0.10 reservations admit exactly 20, duplicate settlement refunds only once, and identical concurrent indexing builds once.
- 13 budget/indexing/transcription orchestration checks passed; 33 chat/grounding handler checks passed. All three changed handlers passed Deno checking.
- Owner MFA database checks and browser enrollment/challenge/cancel/logout checks passed, including narrow phone widths.
- Nine updated access-audit tests passed. Live catalog audit found no unexpected privileged client grants, unprotected client tables/views, public buckets or client-writable indexes. Eight intentionally undeployed optional screening functions remain missing; this is not a claim that screening is live.
- A live transaction exercised normal/oversized text, exact-cap/over-cap reservations, duplicate settlement and access gates, then rolled back. Separate reads confirmed no test reservations/spend remained. No paid AI call or real family mutation was needed.
- Retired endpoint HTTP probes returned 401 with no authorization and 410/no-store with only the public client token.
- Existing 441-test Flutter baseline was run during the audit. No app/native source was changed by this batch. Actual phone acceptance against the hardened backend is still pending.

## Operating and recovery notes

- US$2 is a conservative application guard, not a cap on every charge in the OpenAI account. It covers the deployed chat, embedding and transcription routes; unknown usage retains the full reservation. It resets at 00:00 UTC / 02:00 South Africa. A pricing mismatch disables new paid calls until investigated.
- If requests pause, inspect the owner budget panel and provider usage first. Do not reset the daily ledger or raise the limit to hide a bug. The existing independent limit of 60 new transcription jobs per day also remains.
- A request blocked by the global guard can currently consume one family chat answer because family usage is checked earlier. Follow up with a tested usage reservation/refund change; it is not a spending-cap bypass.
- Indexing failure must preserve saved memories and the previous index. Diagnose/retry the bounded rebuild; do not delete source memories or remove RLS to resolve an index problem.
- Never restore `vault_view_bundle` v10. Keep the retirement response during any rollback. Prefer a scoped forward fix for the new guard paths; returning to pre-guard Edge handlers would remove the approved cost protection.
- MFA failure must not be worked around by making owner reports public or granting family managers owner access. Use verified owner recovery and retain private data gates.
- Do not restore a production database to test backups. Use an isolated recovery environment and synthetic media. Temporary audit files are not a backup strategy.
- Treat provider outages and quota exhaustion separately from authorization failures. Keep ordinary read access available where its existing policies allow it; never globally weaken access controls for availability.

## Remaining launch gates

1. Owner recovery confirmation and provider administrator MFA checks. Owner dashboard enrollment/login acceptance is complete, reported by Ross on 5 November 2026.
2. Versioned media backup and generated-file restore completed 6 November. A full isolated database-plus-media recovery rehearsal remains a separate follow-up.
3. Synthetic warmed-link revocation test and an explicit delivery/revocation policy.
4. DMARC monitoring, approved signup/reset/invite delivery tests and actionable delivery/budget/backup alerts.
5. Scoped mobile secure-session migration and CAPTCHA integration with working login/recovery regression checks.
6. Final dedicated-account phone acceptance: login, family access/blocking, photos/audio, AI, Apple restore/move, logout and deletion. Any real purchase or destructive account operation needs its own appropriate authorization.

See [full audit and remaining implementation plan](../security-review-2026-11-05.md). No assertion of complete exploit immunity or proof of no historical breach is made.
