import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/apple_subscription_config.dart';

void main() {
  test(
    'Apple subscription defaults are inert until App Store Connect IDs exist',
    () {
      expect(AppleSubscriptionConfig.subscriptionGroupId, isEmpty);
      expect(AppleSubscriptionConfig.activeProductIds, isEmpty);
      expect(AppleSubscriptionConfig.hasAnyConfiguredProduct, isFalse);
    },
  );

  test('draft App Store Connect names are stable and non-empty', () {
    expect(
      AppleSubscriptionConfig.draftSubscriptionGroupReferenceName,
      'Ever Roots Family',
    );
    expect(AppleSubscriptionConfig.draftMonthlyProductId, isNotEmpty);
    expect(AppleSubscriptionConfig.draftAnnualProductId, isNotEmpty);
    expect(
      AppleSubscriptionConfig.draftMonthlyProductId,
      isNot(AppleSubscriptionConfig.draftAnnualProductId),
    );
  });
}
