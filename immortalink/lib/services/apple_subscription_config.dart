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

  static const everRootsLegacyMonthlyProductId = String.fromEnvironment(
    'APPLE_EVER_ROOTS_LEGACY_MONTHLY_PRODUCT_ID',
  );

  static const everRootsLegacyAnnualProductId = String.fromEnvironment(
    'APPLE_EVER_ROOTS_LEGACY_ANNUAL_PRODUCT_ID',
  );

  static const appName = 'Ever Roots';
  static const bundleId = 'com.everroots.app';
  static const sku = 'everroots-ios';
  static const draftSubscriptionGroupReferenceName = 'Ever Roots Plans';
  static const draftFamilyMonthlyProductId = 'everroots.family.monthly';
  static const draftFamilyAnnualProductId = 'everroots.family.annual';
  static const draftLegacyMonthlyProductId = 'everroots.legacy.monthly';
  static const draftLegacyAnnualProductId = 'everroots.legacy.annual';

  static const purchaseFlowEnabled = bool.fromEnvironment(
    'APPLE_PURCHASE_FLOW_ENABLED',
  );

  static const tiers = [
    AppleSubscriptionTier(
      plan: 'free',
      title: 'Free Family',
      subtitle: 'Start the family tree and invite close relatives.',
      storageLabel: '500 MB shared storage',
      included:
          '8 family accounts, 25 monthly invites, 100 memories, 100 photos, '
          '25 voice notes, 20 AI replies, and 10 minutes of transcription.',
    ),
    AppleSubscriptionTier(
      plan: 'everroot_family',
      title: 'Ever Roots Family',
      subtitle: 'For families preserving photos, stories, and voice notes.',
      storageLabel: '10 GB shared storage',
      included:
          '20 family accounts, 50 monthly invites, 1,000 memories, 2,000 '
          'photos, 500 voice notes, 500 AI replies, and 10 hours of '
          'transcription.',
      monthlyProductId: everRootsFamilyMonthlyProductId,
      annualProductId: everRootsFamilyAnnualProductId,
      draftMonthlyProductId: draftFamilyMonthlyProductId,
      draftAnnualProductId: draftFamilyAnnualProductId,
    ),
    AppleSubscriptionTier(
      plan: 'everroot_legacy',
      title: 'Ever Roots Legacy',
      subtitle: 'For larger families and heavier archive building.',
      storageLabel: '50 GB shared storage',
      included:
          '30 family accounts, 100 monthly invites, 3,000 memories, 6,000 '
          'photos, 1,500 voice notes, 1,500 AI replies, and premium '
          'transcription capacity.',
      monthlyProductId: everRootsLegacyMonthlyProductId,
      annualProductId: everRootsLegacyAnnualProductId,
      draftMonthlyProductId: draftLegacyMonthlyProductId,
      draftAnnualProductId: draftLegacyAnnualProductId,
    ),
  ];

  static const configuredProductIds = [
    everRootsFamilyMonthlyProductId,
    everRootsFamilyAnnualProductId,
    everRootsLegacyMonthlyProductId,
    everRootsLegacyAnnualProductId,
  ];

  static List<String> get activeProductIds =>
      configuredProductIds.where((id) => id.trim().isNotEmpty).toList();

  static bool get hasAnyConfiguredProduct => activeProductIds.isNotEmpty;
}

class AppleSubscriptionTier {
  final String plan;
  final String title;
  final String subtitle;
  final String storageLabel;
  final String included;
  final String monthlyProductId;
  final String annualProductId;
  final String draftMonthlyProductId;
  final String draftAnnualProductId;

  const AppleSubscriptionTier({
    required this.plan,
    required this.title,
    required this.subtitle,
    required this.storageLabel,
    required this.included,
    this.monthlyProductId = '',
    this.annualProductId = '',
    this.draftMonthlyProductId = '',
    this.draftAnnualProductId = '',
  });

  bool get isFree => plan == 'free';

  bool get hasConfiguredProductIds =>
      isFree ||
      (monthlyProductId.trim().isNotEmpty && annualProductId.trim().isNotEmpty);

  bool get canPurchase =>
      !isFree &&
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      hasConfiguredProductIds;

  String get setupStatus {
    if (isFree) return 'Included';
    if (!hasConfiguredProductIds) return 'Product IDs needed';
    if (!AppleSubscriptionConfig.purchaseFlowEnabled) {
      return 'Purchase code pending';
    }
    return 'Available';
  }
}
