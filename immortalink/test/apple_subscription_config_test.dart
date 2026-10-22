import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/apple_subscription_config.dart';

void main() {
  test(
    'Apple subscription defaults are inert until App Store Connect IDs exist',
    () {
      expect(AppleSubscriptionConfig.subscriptionGroupId, isEmpty);
      expect(AppleSubscriptionConfig.activeProductIds, isEmpty);
      expect(AppleSubscriptionConfig.hasAnyConfiguredProduct, isFalse);
      expect(AppleSubscriptionConfig.purchaseFlowEnabled, isFalse);
      expect(
        AppleSubscriptionConfig.tiers.where((tier) => tier.canPurchase),
        isEmpty,
      );
    },
  );

  test('Heiro display names retain the existing purchase identifiers', () {
    expect(AppleSubscriptionConfig.appName, 'Heiro');
    expect(AppleSubscriptionConfig.bundleId, 'com.everroots.app');
    expect(AppleSubscriptionConfig.sku, 'everroots-ios');
    expect(AppleSubscriptionConfig.tiers.map((tier) => tier.title), [
      'Free Family',
      'Heiro Family',
      'Heiro Legacy',
    ]);
    expect(
      AppleSubscriptionConfig.draftSubscriptionGroupReferenceName,
      'Heiro Plans',
    );
    expect(
      AppleSubscriptionConfig.draftFamilyMonthlyProductId,
      'everroots.family.monthly',
    );
    expect(
      AppleSubscriptionConfig.draftFamilyAnnualProductId,
      'everroots.family.annual',
    );
    expect(
      AppleSubscriptionConfig.draftLegacyMonthlyProductId,
      'everroots.legacy.monthly',
    );
    expect(
      AppleSubscriptionConfig.draftLegacyAnnualProductId,
      'everroots.legacy.annual',
    );
    expect(
      AppleSubscriptionConfig.draftFamilyMonthlyProductId,
      isNot(AppleSubscriptionConfig.draftFamilyAnnualProductId),
    );
    expect(
      AppleSubscriptionConfig.draftFamilyMonthlyProductId,
      isNot(AppleSubscriptionConfig.draftLegacyMonthlyProductId),
    );
  });

  test('three launch tiers are defined with two paid tiers', () {
    expect(AppleSubscriptionConfig.tiers, hasLength(3));
    expect(AppleSubscriptionConfig.tiers.map((tier) => tier.plan), [
      'free',
      'everroot_family',
      'everroot_legacy',
    ]);
    expect(
      AppleSubscriptionConfig.tiers.where((tier) => !tier.isFree),
      hasLength(2),
    );
  });
}
