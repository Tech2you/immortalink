# Apple Subscriptions Launch Checklist

This file tracks the paid Apple subscription work without changing live billing
behavior. App Store Connect is still the source for final product IDs, prices,
review metadata, tax, banking, and agreement status.

## Current App Status

- Implemented: Supabase has a family entitlement/quota foundation for `free`
  and `everroot_family`.
- Implemented: entitlement tables are server-write only after the hardening
  migration.
- Implemented: the Flutter app has a subscription settings placeholder.
- Missing: Flutter does not yet include a StoreKit or in-app-purchase package.
- Missing: no Apple transaction validation Edge Function exists yet.
- Missing: App Store Server Notifications V2 endpoint is not implemented yet.
- Unverified: App Store Connect product IDs, subscription group, paid apps
  agreement, tax, banking, and sandbox tester setup.

## App Store Connect Setup

Create these items in App Store Connect before purchase code is enabled:

- App name: `Ever Roots`.
- Bundle ID: `com.everroots.app`.
- SKU: `everroots-ios`.
- Subscription group reference name: `Ever Roots Family`.
- Monthly product ID: `everroots.family.monthly`.
- Annual product ID: `everroots.family.annual`.
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
   - Reference name: `Ever Roots Family`
   - Display name: `Ever Roots Family`
5. Create two auto-renewable subscriptions in that group.
   - Monthly reference name: `Ever Roots Family Monthly`
   - Monthly product ID: `everroots.family.monthly`
   - Monthly duration: 1 Month
   - Annual reference name: `Ever Roots Family Annual`
   - Annual product ID: `everroots.family.annual`
   - Annual duration: 1 Year
6. Add subscription prices, availability, review information, and localizations.
7. Add sandbox testers before we enable Flutter purchase code.

The actual identifiers must be copied back into build-time configuration:

```bash
--dart-define=APPLE_SUBSCRIPTION_GROUP_ID=...
--dart-define=APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID=...
--dart-define=APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID=...
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
   `provider_subscription_id`, `provider_entitlement_id`, billing owner,
   status, and expiry.
5. App Store Server Notifications V2 keeps renewals, cancellations, refunds,
   billing retry, and expirations current.

## Do Not Ship Until Verified

- Restore purchases works for a signed-in user.
- Manage subscription opens Apple subscription management on iOS.
- Sandbox monthly and annual purchase paths update Supabase entitlements.
- Cancellation, renewal, expiration, billing retry, and refund notifications
  update Supabase entitlements correctly.
- Free limits still apply when no active Apple entitlement exists.
- Existing family tree, invite, media upload, voice-note, legacy-vault, and
  account deletion flows still pass after billing code is enabled.
