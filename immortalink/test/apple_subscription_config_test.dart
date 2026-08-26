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

  test('draft App Store Connect names are stable and non-empty', () {
    expect(
      AppleSubscriptionConfig.draftSubscriptionGroupReferenceName,
      'Ever Roots Plans',
    );
    expect(AppleSubscriptionConfig.draftFamilyMonthlyProductId, isNotEmpty);
    expect(AppleSubscriptionConfig.draftFamilyAnnualProductId, isNotEmpty);
    expect(AppleSubscriptionConfig.draftLegacyMonthlyProductId, isNotEmpty);
    expect(AppleSubscriptionConfig.draftLegacyAnnualProductId, isNotEmpty);
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
