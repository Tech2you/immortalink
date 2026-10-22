# Heiro and retention work - 25 September 2026

## Approved policy

- Account deletion removes personal vault content.
- If real members remain, preserve shared legacy content/media and transfer
  administration. A selected successor takes precedence, with an eligible
  existing owner then longest-standing member as fallback.
- If no real members remain, account deletion also removes legacy content.
- Do not change the existing Leave family flow.
- Subscription cancellation does not delete content. Existing paid access lasts
  to expiry. Over-free-limit families cannot add more content or incur new AI
  usage. Existing content remains readable; no automatic deletion timer.
- Family administration is not ownership of an Apple subscription.

## Local implementation, NOT deployed

- Owner-only Account successor dialog in the tree settings. Server RPCs validate
  ownership and current membership; direct client access to the preference table
  is revoked and RLS enabled.
- Service-only handoff helper selects and promotes an eligible successor and
  updates family/legacy creator references without changing billing ownership.
  IMPORTANT: helper is not yet connected to account deletion. It must run in the
  same transaction as membership removal, after shared-media preservation is
  prepared. Do not ship the successor setting as a completed deletion guarantee.
- New over-limit guard uses existing effective plan/limits and usage helpers.
  Migration adds it to memory/legacy/photo/voice/storage and AI/transcription
  quota enforcement points. Existing reads and deletes remain unchanged.
- This guard blocks additions and expensive usage, not every possible metadata
  edit. Disabling all relevant add controls in advance in the client remains
  pending; server errors map to a fixed friendly message.
- Existing Apple notification code keeps a non-revoked, unexpired transaction
  active; auto-renew cancellation alone is not immediate expiry.

## Verification

- Flutter suite: 97 passed, 9 skipped (purchase build defines not enabled).
- Isolated PGlite SQL tests: 5 passed. These cover selected/fallback ownership,
  forbidden nominations, internal RPC privilege, billing unchanged, expiry,
  preserved reads, blocked personal/legacy memory inserts, renewal and reduction.
- Tests use fixture schemas and source function definitions, not live deletion,
  real StoreKit purchases, full RLS integration or concurrent device actions.
- Live read-only catalog query confirmed the expected insertion markers in all
  eight target quota functions. No production function was modified.
- Targeted Flutter analysis: no errors; 45 warning/info findings in existing
  screen code, including unused old helper and deprecated withOpacity calls.
- `git diff --check` passes.

Reproduce SQL tests with an isolated @electric-sql/pglite 0.3.14 installation:

```sh
PGLITE_MODULE=/tmp/everroots-db-tests/node_modules/@electric-sql/pglite/dist/index.js node --test supabase/tests/family_account_successor.test.mjs supabase/tests/expired_family_read_only.test.mjs
```

## Remaining release blocker

Account deletion is NOT finished. The current local endpoint still removes
legacy media references under the departing user's storage prefix. Implement
and test durable shared-media preservation and last-member cleanup before
connecting the handoff helper or deploying the deletion endpoint. A failed
storage operation must resume without orphaning retained media or claiming
success. No deletion endpoint changes were made in this pass.

## Corrected name screen: HEIRO, not HERO

Exact-name searches with journal, memories, family, legacy and App Store terms
did not identify a clear same-niche competitor. This is not proof of absence,
an exhaustive English-market App Store inventory, title reservation or legal
clearance. Unrelated use exists, including the Heiro Polish retailer:
https://www.heiro.pl/Informacje-regulamin

The earlier Hero Assistant findings concern a different spelling; similarity
still needs consideration in a trademark clearance, not automatic rejection.

Public registry checks at approximately 17:27 UTC on 25 September:

| Domain | Observed registry result |
| --- | --- |
| heiro.app | Google registry RDAP HTTP 404 Not Found; no registration record found. Registrar availability/price NOT confirmed. |
| heiro.org | PIR RDAP HTTP 200, registered 2026-02-01, expiry 2027-02-01. |
| heiro.com | Verisign RDAP HTTP 200, registered 2002-05-27, expiry 2027-05-27. |

Sources:
- https://pubapi.registry.google/rdap/domain/heiro.app
- https://rdap.publicinterestregistry.org/rdap/domain/heiro.org
- https://rdap.verisign.com/com/v1/domain/heiro.com

Website fetches failed for all three. A failed website fetch is NOT domain
availability evidence. No registrant personal information was retrieved for
publication, no domain purchased, no brand or email settings changed.

Preserve the working email templates and flow after domain selection. Configure
new-domain verification records, sender/from/reply-to, support/policy links and
app-return links; test signup/reset/invites before switching. Keep old links
working during transition. Never rename bundle IDs or purchase IDs by global
replacement.
