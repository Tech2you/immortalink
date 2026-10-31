# Apple payment recovery — build 42

## Request and scope

Diagnose the 30 October 23:40 phone recording: slow contribution controls and failed Restore purchases. Fix and install locally. No TestFlight upload, App Store draft change, real purchase, account switching or movement of real contributions was performed.

## Confirmed cause

The live event sequence showed a new Apple purchase following an expired plan, made for a new family. Apple's notification arrived before client validation and attached the transaction to the payer's previous family. The client's checkout reservation remained unresolved. Restore rejected the previous-family binding, while the contribution-move preview refused to proceed with an outstanding checkout. These checks created a dead end.

The native history lookup also enumerated all transactions. Repeated identical expired/previous-family receipts could cause repeated verification and visible loading.

## Implemented

- Defer an out-of-order same-payer repurchase notification when a verified expired-plan check and matching checkout establish a pending new-family purchase. Client verification remains responsible for applying the new purchase. Renewals, refunds and duplicate events retain their safeguards.
- Recognize an Apple-verified, active contribution owned by this payer in their previous family. Restore acknowledges its existing service without granting or moving benefits.
- Clear only a checkout proven fulfilled by the recorded purchase in its exact reservation window. Other payers' and newer reservations remain protected.
- Moving still requires the existing explicit review and confirmation, and preserves consumed allowances.
- Advertise the new restore response only to clients supporting it; previous app versions retain their existing response contract.
- Look up the latest transaction for each of the four configured Apple products rather than scanning the whole history.
- Deduplicate identical successful historical checks for 30 seconds, scoped to account, family and signed proof. Explicit buy, restore and move operations force fresh checks; failed checks are not cached.

## Verification

- Full Flutter run with purchases enabled: 364 passed. Default-only configuration tested separately without purchase flags: 3 passed. The first full run's sole failure was the deliberately inert-default test being run with purchase flags; separating its configuration resolved it.
- Focused billing and UI suite: 108 passed (included in full regression coverage).
- Local pooled storage / contribution move / recovery database suite: 37 passed.
- Additional database concurrency run: 6 passed, including actual Postgres notification/client ordering, simultaneous contributions, duplicate moves, usage and refunds.
- Apple verification and status-request helper tests: 19 passed. Edge type check and Flutter analyzer passed.
- Live disposable-data test passed: notification ordering, existing stuck checkout recovery, no movement during restore/preview, explicit confirmed move, protected service-only function. Entire transaction rolled back; zero test bindings remained.
- Readback confirmed migration `20261030220413_recover_previous_family_checkout`, server-only acknowledgement permissions, and active validator version 23. All 13 deployed function files exactly matched the prepared source. JWT protection remains enabled; an anonymous HTTP request returned 401.
- iOS release build 42 compiled and passed code-sign verification. Installed in place on the connected iPhone; device inventory reports Heiro 1.0.0 (42), and launch succeeded.

## Post-install status check

The phone made several successful validator calls after installation (approximately 1.2–4.5 seconds at the server). One call returned `APPLE_HISTORY_CHECK_UNAVAILABLE` at 22:09:01 UTC, followed by successful calls. The old log did not distinguish Apple HTTP failure from inconsistent status payload, so its exact transient cause is unconfirmed. Validator version 23 adds a single retry only for read-only network/429/5xx status lookups, within the original 15-second deadline. Signature/identity failures and malformed status never bypass verification. Fixed-category diagnostics now distinguish HTTP/network/payload/transaction-field failure and request type without logging credentials or receipts. Three new tests cover transient recovery, bounded persistent failure and invalid response rejection.

## Device acceptance

The user confirmed on build 42: **“Restored; Move my contribution is available.”** This supplies actual phone acceptance for Restore and move-option availability. No real move or purchase was performed by the assistant. Move confirmation remains the payer's explicit action; its behavior was verified locally and with rolled-back live disposable data. The current sandbox contribution had remaining paid time and belonged to the previous family at the post-deploy read; test renewals/expiry may change this. A fully expired plan has no remaining contribution to move.

Build 41 app and changed-source backups are retained in `/private/tmp/heiro-build41-before-payment-recovery.app` and `/private/tmp/heiro-before-build42/`. Logs, device receipts and test output use `/private/tmp/heiro42-*`. Keep automated/local/live disposable proof distinct from the user's confirmed Restore acceptance and any future real contribution move.
