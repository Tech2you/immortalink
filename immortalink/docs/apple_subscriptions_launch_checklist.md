# Apple Subscriptions Launch Checklist

This file tracks the paid Apple subscription work without changing live billing
behavior. App Store Connect is still the source for final product IDs, prices,
review metadata, tax, banking, and agreement status.

## Current App Status

- Implemented: Supabase has a family entitlement/quota foundation for `free`,
  `everroot_family`, and the local `everroot_legacy` launch model.
- Implemented: entitlement tables are server-write only after the hardening
  migration.
- Implemented: the Flutter app has a family-plan/paywall shell with storage
  usage, StoreKit product lookup, monthly/annual purchase actions, restore, and
  Apple subscription management.
- Implemented: Flutter purchase activation is gated by
  `APPLE_PURCHASE_FLOW_ENABLED`; default builds still cannot charge users.
- Implemented: `validate_apple_subscription` Edge Function validates a
  transaction with Apple before updating family entitlements.
- Implemented: `apple_subscription_notifications` Edge Function re-checks Apple
  transaction data before renewal, expiration, cancellation, or refund updates.
- Implemented: `apple_subscription_events` stores server-side billing audit
  events with RLS and service-role-only writes.
- Unverified: App Store Connect product IDs, subscription group, paid apps
  agreement, tax, banking, founding-family offers, and sandbox tester setup.
- Must wait: Apple App Store Server API secrets are not configured in Supabase
  yet, so real purchase validation will reject until those secrets are added.

## App Store Connect Setup

Create these items in App Store Connect before purchase code is enabled:

- App name: `Ever Roots`.
- Bundle ID: `com.everroots.app`.
- SKU: `everroots-ios`.
- Subscription group reference name: `Ever Roots Plans`.
- Family monthly product ID: `everroots.family.monthly`.
- Family annual product ID: `everroots.family.annual`.
- Legacy monthly product ID: `everroots.legacy.monthly`.
- Legacy annual product ID: `everroots.legacy.annual`.
- App Store Server Notifications V2 URLs:
  - Sandbox: Supabase Edge Function URL for the Apple notification handler.
  - Production: the same handler after it is tested and deployed.

### Apple-Side Order Of Operations

1. In Apple Developer, register an explicit App ID.
   - Description: `Ever Roots`
   - Bundle ID: `com.everroots.app`
   - In-App Purchase: enabled by default for explicit App IDs
2. In App Store Connect, confirm the Account Holder has accepted the latest
   agreements in Business.
3. In App Store Connect, create the app record.
   - Platform: iOS
   - Name: `Ever Roots`
   - Primary language: English
   - Bundle ID: the explicit App ID created above
   - SKU: `everroots-ios`
   - User access: Full Access unless the account has multiple teams/apps
4. In the app record, create one subscription group.
   - Reference name: `Ever Roots Plans`
   - Display name: `Ever Roots Plans`
5. Create four auto-renewable subscriptions in that group.
   - Monthly reference name: `Ever Roots Family Monthly`
   - Monthly product ID: `everroots.family.monthly`
   - Monthly duration: 1 Month
   - Annual reference name: `Ever Roots Family Annual`
   - Annual product ID: `everroots.family.annual`
   - Annual duration: 1 Year
   - Monthly reference name: `Ever Roots Legacy Monthly`
   - Monthly product ID: `everroots.legacy.monthly`
   - Monthly duration: 1 Month
   - Annual reference name: `Ever Roots Legacy Annual`
   - Annual product ID: `everroots.legacy.annual`
   - Annual duration: 1 Year
6. Add subscription prices, availability, review information, and localizations.
7. Create founding-family support with Apple offer codes or introductory offers
   inside App Store Connect.
8. Add sandbox testers before we enable Flutter purchase code.

The actual identifiers must be copied back into build-time configuration:

```bash
--dart-define=APPLE_SUBSCRIPTION_GROUP_ID=...
--dart-define=APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID=...
--dart-define=APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID=...
--dart-define=APPLE_EVER_ROOTS_LEGACY_MONTHLY_PRODUCT_ID=...
--dart-define=APPLE_EVER_ROOTS_LEGACY_ANNUAL_PRODUCT_ID=...
--dart-define=APPLE_PURCHASE_FLOW_ENABLED=true
```

Supabase Edge Function secrets required before sandbox purchase testing:

```bash
APPLE_BUNDLE_ID=com.everroots.app
APPLE_IAP_ENVIRONMENT=sandbox
APPLE_IAP_ISSUER_ID=...
APPLE_IAP_KEY_ID=...
APPLE_IAP_PRIVATE_KEY=...
APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID=everroots.family.monthly
APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID=everroots.family.annual
APPLE_EVER_ROOTS_LEGACY_MONTHLY_PRODUCT_ID=everroots.legacy.monthly
APPLE_EVER_ROOTS_LEGACY_ANNUAL_PRODUCT_ID=everroots.legacy.annual
```

## Server-Side Purchase Flow

The first paid implementation should use Apple-signed transaction data, not the
deprecated receipt verification endpoint.

1. Flutter starts a StoreKit purchase for one configured product ID.
2. Flutter sends the verified transaction identifiers or signed transaction data
   to a Supabase Edge Function.
3. The Edge Function validates with Apple App Store Server API or Apple-signed
   JWS data.
4. Supabase updates `family_entitlements` with `provider = 'apple'`,
   Apple transaction identifiers, `apple_product_id`, `apple_environment`,
   `provider_subscription_id`, `provider_entitlement_id`, billing owner,
   offer metadata, status, and expiry.
5. App Store Server Notifications V2 keeps renewals, cancellations, refunds,
   billing retry, and expirations current.

## Do Not Ship Until Verified

- Restore purchases works for a signed-in family owner.
- Manage subscription opens Apple subscription management on iOS.
- Sandbox monthly and annual purchase paths update Supabase entitlements.
- Cancellation, renewal, expiration, billing retry, and refund notifications
  update Supabase entitlements correctly.
- Free limits still apply when no active Apple entitlement exists.
- Existing family tree, invite, media upload, voice-note, legacy-vault, and
  account deletion flows still pass after billing code is enabled.
