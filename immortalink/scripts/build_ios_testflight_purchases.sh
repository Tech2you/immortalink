#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter build ipa \
  --release \
  --dart-define=APPLE_PURCHASE_FLOW_ENABLED=true \
  --dart-define=APPLE_SUBSCRIPTION_GROUP_ID=22339684 \
  --dart-define=APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID=everroots.family.monthly \
  --dart-define=APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID=everroots.family.annual \
  --dart-define=APPLE_EVER_ROOTS_LEGACY_MONTHLY_PRODUCT_ID=everroots.legacy.monthly \
  --dart-define=APPLE_EVER_ROOTS_LEGACY_ANNUAL_PRODUCT_ID=everroots.legacy.annual \
  "$@"
