/// Apple subscription identifiers used by the Ever Roots billing bridge.
///
/// Keep these values aligned with App Store Connect. The empty default values
/// are intentional so local builds do not accidentally look for draft products.
class AppleSubscriptionConfig {
  const AppleSubscriptionConfig._();

  static const subscriptionGroupId = String.fromEnvironment(
    'APPLE_SUBSCRIPTION_GROUP_ID',
  );

  static const everRootsFamilyMonthlyProductId = String.fromEnvironment(
    'APPLE_EVER_ROOTS_FAMILY_MONTHLY_PRODUCT_ID',
  );

  static const everRootsFamilyAnnualProductId = String.fromEnvironment(
    'APPLE_EVER_ROOTS_FAMILY_ANNUAL_PRODUCT_ID',
  );

  static const appName = 'Ever Roots';
  static const bundleId = 'com.everroots.app';
  static const sku = 'everroots-ios';
  static const draftSubscriptionGroupReferenceName = 'Ever Roots Family';
  static const draftMonthlyProductId = 'everroots.family.monthly';
  static const draftAnnualProductId = 'everroots.family.annual';

  static const configuredProductIds = [
    everRootsFamilyMonthlyProductId,
    everRootsFamilyAnnualProductId,
  ];

  static List<String> get activeProductIds =>
      configuredProductIds.where((id) => id.trim().isNotEmpty).toList();

  static bool get hasAnyConfiguredProduct => activeProductIds.isNotEmpty;
}
