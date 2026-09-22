# AI cost controls

Deployed September 18, 2026 with owner approval to project vbzyvaylfdhwowdbodmk.
Database migration applied; vault_ai_chat version 84 is active with JWT
verification enabled. Three Node tests and rollback-only live database tests
passed. Device-level chat/transcription testing has not been repeated.

Monthly transcription allowances: Free 600 seconds (unchanged), Family 7,200
seconds, Legacy 24,000 seconds. Paid usage is pooled per family; free usage is
per user. AI allowances remain 20 / 500 / 1,500 calls. Icebreaker generation
also consumes AI allowance. Existing counters are not reset by the migration.
Users already above a new limit wait until the next usage period. Stored media
and transcripts are not deleted or changed.

The migration preserves function signatures, grants, advisory locks, membership
checks and unrelated plan benefits. It fixes Legacy falling through to the free
counter and removes the old 120-second ceiling on duration accounting.

Chat rejects questions over 2,000 characters, bounds semantic-search inputs to
30 memories of 1,200 characters each, and reserves usage before embedding calls.
Existing context and reply limits remain. Requests that fail after reservation
still consume allowance, as before.

These are not strict dollar ceilings: audio duration is stored metadata, not
independently measured by this change. Embeddings, prompts and transcripts have
variable token costs. Free-account abuse, repeated transcription, concurrency,
and video egress require ongoing monitoring; no claim of a complete abuse audit.

Validation:
- `node --test supabase/functions/_shared/ai_cost_limits_test.ts`
- Apply migration in a rollback-only transaction, then run paid_ai_usage.sql
  within that transaction (omit that file's begin/rollback wrappers when composed).
  Tests cover both plans, exact boundaries, overages, full duration accounting,
  free allowance preservation and nonmember rejection.

Billing: functions read OPENAI_API_KEY from backend secrets. The OpenAI project
owning that key pays for chat, embeddings and transcription. This is separate
from Supabase hosting and customer App Store subscription payments. Check the
correct organization/project in https://platform.openai.com/usage and its Costs
tab. No API key or billing credentials should be placed in the app or this file.

Post-deployment Security Advisor still flags authenticated SECURITY DEFINER
RPCs, the vector extension in public, and disabled leaked-password protection.
This change preserves existing grants; quota RPCs intentionally require signed-in
callers and check paid-family membership (including tested nonmember rejection).
It is not a full review of the other flagged RPCs.
References:
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
