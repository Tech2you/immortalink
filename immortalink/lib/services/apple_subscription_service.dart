import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apple_subscription_config.dart';

enum _PurchaseRecovery { none, recovered, expiredHistory, failed }

enum _PurchaseValidation { applied, expiredHistory, previousFamily, failed }

class ContributionMovePreview {
  final String confirmationId;
  final DateTime paidUntil;
  final int storageBytes, aiRemaining, transcriptionSecondsRemaining;
  final bool previousFamilyExists;
  ContributionMovePreview(Map data)
    : confirmationId = data['confirmation_id'] as String,
      paidUntil = DateTime.parse(data['paid_until'] as String),
      storageBytes = (data['storage_bytes'] as num).toInt(),
      aiRemaining = (data['ai_remaining'] as num).toInt(),
      transcriptionSecondsRemaining =
          (data['transcription_seconds_remaining'] as num).toInt(),
      previousFamilyExists = data['previous_family_exists'] as bool {
    if (confirmationId.isEmpty ||
        storageBytes <= 0 ||
        aiRemaining < 0 ||
        transcriptionSecondsRemaining < 0) {
      throw const FormatException('Invalid move details');
    }
  }
}

class AppleSubscriptionService extends ChangeNotifier {
  AppleSubscriptionService({
    SupabaseClient? supabase,
    InAppPurchase? iap,
    Future<List<PurchaseDetails>> Function()? unfinishedPurchases,
    Future<PurchaseDetails?> Function()? previousPurchase,
    Future<void> Function()? syncPurchases,
  }) : _supabase = supabase ?? Supabase.instance.client,
       _iap = iap ?? InAppPurchase.instance,
       _unfinishedPurchases = unfinishedPurchases ?? _readUnfinishedPurchases,
       _previousPurchase = previousPurchase ?? _readPreviousPurchase,
       _syncPurchases = syncPurchases ?? _syncApplePurchases;

  final SupabaseClient _supabase;
  final InAppPurchase _iap;
  final Future<List<PurchaseDetails>> Function() _unfinishedPurchases;
  final Future<PurchaseDetails?> Function() _previousPurchase;
  final Future<void> Function() _syncPurchases;
  String? _reservationId;
  String? _reservationUserId;
  String? _reservationFamilyId;
  String? _checkoutProductId;
  bool _needsRecovery = false;
  bool _operationBusy = false;
  final Set<String> _completedTransactions = {};
  final Set<String> _finishedExpiredTransactions = {};
  final Set<String> _finishedPreviousTransactions = {};
  // Short-lived exact-proof deduplication only. Explicit Buy/Restore clears it;
  // different receipts, accounts, families and live checkouts always reverify.
  final Map<String, ({String proof, DateTime at, _PurchaseValidation result})>
  _recentHistory = {};
  // Only deduplicate history within one explicit buy/restore operation. A later
  // attempt must recheck Apple rather than reusing stale expiry permission.
  final Set<String> _checkedExpiredHistory = {};
  final Map<String, Future<_PurchaseValidation>> _verifications = {};
  final Map<String, ({String diagnostic, bool sandbox})> _bindingRejections =
      {};
  Completer<void>? _restoreUpdatesReceived;
  bool _sandboxAccountMismatch = false;

  bool get sandboxAccountMismatch => _sandboxAccountMismatch;
  bool get purchaseAccountMismatch =>
      _error != null && _isAccountMismatch(_validationDiagnostic ?? '');

  static Future<void> _syncApplePurchases() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    // The plugin's restorePurchases only enumerates cached entitlements.
    // Sync is user-initiated because Apple may request authentication.
    await AppStore().sync();
  }

  static Future<PurchaseDetails?> _readPreviousPurchase() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    // The plugin's history API drops the JWS. Keep Apple's signed environment
    // for expired purchases as well as transactions replayed on the stream.
    const channel = MethodChannel('com.everroots.app/subscriptions');
    final tx = await channel.invokeMapMethod<String, dynamic>(
      'latestSubscriptionTransaction',
      AppleSubscriptionConfig.activeProductIds.toList(),
    );
    if (tx == null) return null;
    final productId = tx['productId'] as String;
    final receipt = tx['receiptData'] as String;
    if (!AppleSubscriptionConfig.activeProductIds.contains(productId) ||
        receipt.isEmpty) {
      throw const FormatException('Invalid Apple purchase history');
    }
    return SK2PurchaseDetails(
      productID: productId,
      purchaseID: tx['id'] as String,
      verificationData: PurchaseVerificationData(
        localVerificationData: tx['jsonRepresentation'] as String? ?? '',
        serverVerificationData: receipt,
        source: 'app_store',
      ),
      transactionDate: tx['purchaseDate'] as String,
      status: PurchaseStatus.restored,
      appAccountToken: tx['appAccountToken'] as String?,
    );
  }

  @visibleForTesting
  static SK2PurchaseDetails storeKitPurchaseDetails(
    SK2Transaction tx, {
    required PurchaseStatus status,
  }) {
    return SK2PurchaseDetails(
      productID: tx.productId,
      purchaseID: tx.id,
      verificationData: PurchaseVerificationData(
        localVerificationData: tx.jsonRepresentation ?? '',
        serverVerificationData: tx.receiptData ?? '',
        source: 'app_store',
      ),
      transactionDate: tx.purchaseDate,
      status: status,
      appAccountToken: tx.appAccountToken,
    );
  }

  static Future<List<PurchaseDetails>> _readUnfinishedPurchases() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return [];
    final transactions = await SK2Transaction.unfinishedTransactions();
    return transactions
        .map(
          (tx) => storeKitPurchaseDetails(tx, status: PurchaseStatus.purchased),
        )
        .toList();
  }

  Future<_PurchaseRecovery> _recoverUnfinished() async {
    _message = 'Checking previous Apple purchases...';
    notifyListeners();
    final purchases = await _unfinishedPurchases().timeout(
      const Duration(seconds: 12),
    );
    var recovered = false;
    var expiredHistory = false;
    final seen = <String>{};
    for (final purchase in purchases) {
      if (!AppleSubscriptionConfig.activeProductIds.contains(
        purchase.productID,
      )) {
        continue;
      }
      if (purchase.purchaseID != null &&
          !seen.add('${purchase.productID}:${purchase.purchaseID}')) {
        continue;
      }
      final result = await _validateAndComplete(purchase);
      if (result == _PurchaseValidation.failed) {
        return _PurchaseRecovery.failed;
      }
      recovered |=
          result == _PurchaseValidation.applied ||
          result == _PurchaseValidation.previousFamily;
      expiredHistory |= result == _PurchaseValidation.expiredHistory;
    }
    return recovered
        ? _PurchaseRecovery.recovered
        : expiredHistory
        ? _PurchaseRecovery.expiredHistory
        : _PurchaseRecovery.none;
  }

  Future<void> _releaseReservation() async {
    final id = _reservationId;
    if (id == null || _reservationUserId != _supabase.auth.currentUser?.id) {
      return;
    }
    final family = _reservationFamilyId;
    _reservationId = null;
    try {
      await _supabase
          .rpc(
            'release_family_sponsorship',
            params: {'p_family_id': family, 'p_reservation_id': id},
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // A lost cancellation request must expire server-side, not release another checkout.
    }
  }

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _updateQueue = Future<void>.value();
  bool _disposed = false;
  final Map<String, ProductDetails> _productsById = {};
  final Set<String> _requestedProductIds = {};
  final Set<String> _notFoundProductIds = {};

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _loading = false;
  bool _purchasePending = false;
  int _restoreAttempt = 0;
  String? _familyId;
  String? _storefrontCountryCode;
  String? _message;
  String? _error;
  String? _pricingError;
  String? _validationDiagnostic;
  bool _sponsorshipLoaded = false;
  bool _familySponsored = false;
  bool _bucketModel = false;
  bool _billingRefreshFailed = false;
  String? _ownPlan;
  DateTime? _ownPaidUntil;
  List<Map<String, dynamic>> _contributors = [];
  int _contributorCount = 0;
  num? _includedAccessBytes;
  DateTime? _includedAccessUntil;
  num? get includedAccessBytes => bucketModel ? _includedAccessBytes : null;
  DateTime? get includedAccessUntil =>
      bucketModel ? _includedAccessUntil : null;

  bool get bucketModel =>
      _bucketModel &&
      _billingUserId != null &&
      _billingUserId == _supabase.auth.currentUser?.id;
  bool get billingStatusLoaded =>
      _sponsorshipLoaded &&
      _billingUserId != null &&
      _billingUserId == _supabase.auth.currentUser?.id;
  bool get billingRefreshFailed => _billingRefreshFailed;
  String? get ownPlan => bucketModel ? _ownPlan : null;
  num? get ownStorageBytes {
    for (final person in contributors) {
      if (person['is_you'] == true && person['storage_bytes'] is num) {
        return person['storage_bytes'] as num;
      }
    }
    return null;
  }

  DateTime? get ownPaidUntil => bucketModel ? _ownPaidUntil : null;
  List<Map<String, dynamic>> get contributors =>
      bucketModel ? List.unmodifiable(_contributors) : const [];
  int get contributorCount => bucketModel ? _contributorCount : 0;
  bool _moveAvailable = false;
  String? _moveError;
  String? _moveUser, _moveFamily;
  ContributionMovePreview? _movePreview;
  bool get canMoveContribution =>
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      _moveAvailable &&
      _sponsorshipLoaded &&
      _billingUserId != null &&
      _billingUserId == _supabase.auth.currentUser?.id;
  String? get moveError =>
      _billingUserId == _supabase.auth.currentUser?.id ? _moveError : null;
  bool _isSponsor = false;
  String? _sponsorName;
  DateTime? _paidUntil;
  Map<String, dynamic>? _familyUsage;
  bool _billingRefreshing = false;
  int _billingRefresh = 0;
  String? _billingUserId;

  bool get canSponsor =>
      !canMoveContribution &&
      !_needsRecovery &&
      _sponsorshipLoaded &&
      _billingUserId != null &&
      _billingUserId == _supabase.auth.currentUser?.id &&
      (_bucketModel || !_familySponsored || _isSponsor);
  String? get sponsorName => hasActiveSponsor ? _sponsorName : null;
  bool get hasActiveSponsor =>
      _sponsorshipLoaded &&
      _familySponsored &&
      _billingUserId == _supabase.auth.currentUser?.id;
  bool get canManageFamilyPlan =>
      _sponsorshipLoaded &&
      _isSponsor &&
      _billingUserId == _supabase.auth.currentUser?.id;
  DateTime? get paidUntil => _paidUntil;
  Map<String, dynamic>? get familyUsage =>
      _billingUserId == _supabase.auth.currentUser?.id ? _familyUsage : null;
  bool get billingRefreshing => _billingRefreshing;

  Future<Map<String, dynamic>?> _readFamilyUsage(String familyId) async {
    try {
      final data = await _supabase
          .rpc(
            'get_family_entitlements_and_usage',
            params: {'p_family_id': familyId},
          )
          .timeout(const Duration(seconds: 12));
      if (data is! Map ||
          data['plan'] is! String ||
          data['limits'] is! Map ||
          data['usage'] is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshSponsorship({bool includeUsage = true}) async {
    final familyId = _familyId;
    if (familyId == null || familyId.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    if (_billingUserId != userId) {
      _sponsorshipLoaded = false;
      _familyUsage = null;
      _familySponsored = false;
      _bucketModel = false;
      _moveAvailable = false;
      _movePreview = null;
      _moveError = null;
      _ownPlan = null;
      _ownPaidUntil = null;
      _contributors = [];
      _contributorCount = 0;
      _includedAccessBytes = null;
      _includedAccessUntil = null;
      _isSponsor = false;
      _paidUntil = null;
      _billingUserId = userId;
      _billingRefreshFailed = false;
    }
    if (userId == null) {
      ++_billingRefresh;
      _sponsorshipLoaded = false;
      _billingRefreshing = false;
      notifyListeners();
      return;
    }
    final request = ++_billingRefresh;
    bool current() =>
        !_disposed &&
        request == _billingRefresh &&
        familyId == _familyId &&
        userId == _supabase.auth.currentUser?.id;
    _billingRefreshing = true;
    var refreshFailed = includeUsage ? false : _billingRefreshFailed;
    notifyListeners();
    // These reads are independent; usage must not delay the ownership check.
    final usageRequest = includeUsage ? _readFamilyUsage(familyId) : null;
    try {
      final data = await _supabase
          .rpc('get_family_sponsorship', params: {'p_family_id': familyId})
          .timeout(const Duration(seconds: 12));
      if (!current()) return;
      if (data is! Map ||
          data['active'] is! bool ||
          data['is_sponsor'] is! bool) {
        throw const FormatException('Invalid sponsorship response');
      }
      _includedAccessBytes = data['included_access_bytes'] as num?;
      _includedAccessUntil = DateTime.tryParse(
        data['included_access_until']?.toString() ?? '',
      );
      _bucketModel = data['bucket_model'] == true;
      _moveAvailable = data['can_move_contribution'] == true;
      _ownPlan = data['own_plan']?.toString();
      _ownPaidUntil = DateTime.tryParse(
        data['own_paid_until']?.toString() ?? '',
      );
      _contributors = ((data['contributors'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _contributorCount = (data['contributor_count'] as num?)?.toInt() ?? 0;
      _familySponsored = data['active'] == true;
      _isSponsor = data['is_sponsor'] == true;
      _sponsorName = data['sponsor_name']?.toString();
      _paidUntil = DateTime.tryParse(data['paid_until']?.toString() ?? '');
      _sponsorshipLoaded = true;
    } catch (_) {
      if (!current()) return;
      _sponsorshipLoaded = false;
      refreshFailed = true;
    }
    try {
      if (usageRequest == null) return;
      final usage = await usageRequest;
      if (!current()) return;
      if (usage != null) {
        _familyUsage = usage;
      } else {
        // Keep the last known layout and usage, with a visible stale-data notice.
        refreshFailed = true;
      }
    } finally {
      if (current()) {
        _billingRefreshFailed = refreshFailed;
        _billingRefreshing = false;
        notifyListeners();
      }
    }
  }

  bool get loading => _loading;
  bool get purchasePending => _purchasePending || _operationBusy;
  bool get storeAvailable => _storeAvailable;
  String? get storefrontCountryCode => _storefrontCountryCode;
  String? get message => _message;
  String? get error => _friendlyError(_error ?? _pricingError);
  List<ProductDetails> get products => _productsById.values.toList();
  List<String> get requestedProductIds => _requestedProductIds.toList()..sort();
  List<String> get foundProductIds => _productsById.keys.toList()..sort();
  List<String> get notFoundProductIds => _notFoundProductIds.toList()..sort();
  String? get rawError => _validationDiagnostic ?? _error ?? _pricingError;
  bool get hasPricingDiagnostics =>
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      (_pricingError != null ||
          (_initialized && !_loading && _productsById.isEmpty));

  ProductDetails? productFor(String productId) => _productsById[productId];

  Future<void> refreshStorefront() async {
    if (!_initialized || _loading || purchasePending) return;
    // Storefront lookup can itself be cached during an Apple account change.
    // Ask for fresh localized products even when the country appears unchanged.
    await refreshProducts();
  }

  Future<void> initialize({required String familyId}) async {
    if (_familyId != familyId.trim()) {
      _sponsorshipLoaded = false;
      _familyUsage = null;
      _paidUntil = null;
      _familySponsored = false;
      _bucketModel = false;
      _moveAvailable = false;
      _movePreview = null;
      _moveError = null;
      _ownPlan = null;
      _ownPaidUntil = null;
      _contributors = [];
      _contributorCount = 0;
      _includedAccessBytes = null;
      _includedAccessUntil = null;
      _isSponsor = false;
    }
    _familyId = familyId.trim();
    final billing = refreshSponsorship();
    if (!AppleSubscriptionConfig.purchaseFlowEnabled ||
        AppleSubscriptionConfig.activeProductIds.isEmpty) {
      await billing;
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    if (_initialized) {
      await billing;
      return;
    }
    _initialized = true;
    await Future.wait([billing, refreshProducts()]);
  }

  Future<void> refreshProducts() async {
    if (_loading || purchasePending || _disposed) return;
    if (!AppleSubscriptionConfig.purchaseFlowEnabled ||
        AppleSubscriptionConfig.activeProductIds.isEmpty) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      _requestedProductIds
        ..clear()
        ..addAll(AppleSubscriptionConfig.activeProductIds);
      _notFoundProductIds.clear();
      _storeAvailable = await _iap.isAvailable().timeout(
        const Duration(seconds: 12),
      );
      if (!_storeAvailable) {
        _pricingError = 'The App Store is not available on this device.';
        return;
      }

      // Localized prices come from ProductDetails. A slow country-code lookup
      // is diagnostic only and must not hold up price buttons or checkout.
      unawaited(_refreshCountryCode());

      _purchaseSubscription ??= _iap.purchaseStream.listen(
        (purchases) {
          final received = _restoreUpdatesReceived;
          if (received != null && !received.isCompleted) received.complete();
          _updateQueue = _updateQueue
              .then((_) async {
                if (!_disposed) await _handlePurchaseUpdates(purchases);
              })
              .catchError((Object _) {
                if (_disposed) return;
                _purchasePending = false;
                _error =
                    'Could not check Apple purchases. Tap Restore purchases to retry.';
                notifyListeners();
              });
        },
        onError: (Object error) {
          _purchasePending = false;
          _error = 'Purchase update failed: $error';
          notifyListeners();
        },
      );

      final response = await _iap
          .queryProductDetails(AppleSubscriptionConfig.activeProductIds.toSet())
          .timeout(const Duration(seconds: 15));
      _notFoundProductIds
        ..clear()
        ..addAll(response.notFoundIDs);
      _productsById
        ..clear()
        ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));

      if (response.error != null) {
        _pricingError = response.error!.message;
      } else if (_productsById.isEmpty) {
        _pricingError = 'No App Store subscription products were found.';
      } else {
        _pricingError = null;
      }
    } catch (e) {
      _pricingError = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  int _countryRequest = 0;
  Future<void> _refreshCountryCode() async {
    final request = ++_countryRequest;
    String? country;
    try {
      country = await _iap.countryCode().timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (_disposed || request != _countryRequest) return;
    _storefrontCountryCode = country;
    notifyListeners();
  }

  Future<void> buy(String productId) async {
    if (purchasePending || _loading || _needsRecovery || _disposed) return;
    final product = _productsById[productId];
    final familyId = _familyId;
    if (product == null || familyId == null || familyId.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _error = 'Sign in before purchasing a family plan.';
      notifyListeners();
      return;
    }

    _purchasePending = true;
    _operationBusy = true;
    _recentHistory.clear();
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    _sandboxAccountMismatch = false;
    _bindingRejections.clear();
    _checkedExpiredHistory.clear();
    notifyListeners();

    var checkoutInvoked = false;
    try {
      await refreshSponsorship(includeUsage: false);
      if (bucketModel && canManageFamilyPlan) {
        _message =
            'Use Manage your contribution to change your existing Apple subscription.';
        return;
      }
      if (!canSponsor) {
        _message = null;
        _error = hasActiveSponsor
            ? 'The current purchaser manages this family plan. Another member can sponsor after its paid coverage ends.'
            : 'Could not check family billing. Refresh the plan and try again.';
        return;
      }
      // Resolve an earlier Apple charge before requesting another product.
      await _updateQueue;
      final recovery = await _recoverUnfinished();
      if (recovery == _PurchaseRecovery.failed ||
          recovery == _PurchaseRecovery.recovered) {
        return;
      }
      // History is not a restore claim. The server may acknowledge a fully
      // expired chain without transferring it, then require a new purchase.
      final previous = await _previousPurchase().timeout(
        const Duration(seconds: 12),
      );
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return;
      }
      if (previous != null &&
          !_checkedExpiredHistory.contains(
            '$userId:$familyId:${previous.purchaseID}',
          )) {
        final result = await _validateAndComplete(previous, historyOnly: true);
        if (result == _PurchaseValidation.failed ||
            result == _PurchaseValidation.previousFamily) {
          return;
        }
      }
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return;
      }
      _purchasePending = true;
      _message = null;
      final reservation = await _supabase
          .rpc(
            bucketModel
                ? 'begin_family_storage_contribution'
                : 'begin_family_sponsorship',
            params: {'p_family_id': familyId},
          )
          .timeout(const Duration(seconds: 12));
      if (reservation is Map && reservation['reservation_id'] is String) {
        _reservationId = reservation['reservation_id'] as String;
        _reservationUserId = userId;
        _reservationFamilyId = familyId;
      } else {
        throw const FormatException('Invalid checkout response');
      }
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        await _releaseReservation();
        if (!_disposed) notifyListeners();
        return;
      }
      // StoreKit 2 returns this UUID in Apple's verified transaction data.
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      );
      _checkoutProductId = productId;
      _message = 'Opening Apple checkout...';
      notifyListeners();
      checkoutInvoked = true;
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
        _checkoutProductId = null;
        await _releaseReservation();
        _purchasePending = false;
        _error = 'The App Store did not start the purchase.';
        notifyListeners();
      }
    } catch (e) {
      _purchasePending = false;
      final duplicate =
          e is PlatformException &&
          e.code == 'storekit_duplicate_product_object';
      if (duplicate) _needsRecovery = true;
      // An unknown bridge failure may follow an Apple charge. Keep its hold
      // until recovery or expiry; only known unstarted attempts are released.
      if (!checkoutInvoked || duplicate) {
        _checkoutProductId = null;
        await _releaseReservation();
      } else {
        _needsRecovery = true;
      }
      final code = e is PostgrestException ? e.message : '';
      _validationDiagnostic = duplicate
          ? 'APPLE_UNFINISHED_PURCHASE'
          : e is PostgrestException
          ? 'CHECKOUT_RESERVATION_FAILED'
          : 'APPLE_CHECKOUT_NOT_STARTED';
      _error = duplicate
          ? 'An earlier Apple purchase still needs confirmation. Restore purchases before buying another plan.'
          : code == 'APP_UPDATE_REQUIRED'
          ? 'Please update Heiro before starting a new subscription.'
          : code == 'FAMILY_ALREADY_SPONSORED'
          ? 'You already have a contribution. Manage your current Apple subscription to change it.'
          : code == 'SPONSOR_PURCHASE_IN_PROGRESS'
          ? 'An earlier family checkout is awaiting confirmation. Return to the account that started it and restore purchases. Otherwise the checkout hold expires within 15 minutes.'
          : code == 'SPONSOR_ALREADY_SUPPORTS_FAMILY'
          ? 'Your subscription already supports another family. Contact support before purchasing again.'
          : code == 'SPONSOR_CHECKOUT_RATE_LIMIT'
          ? 'Please wait a minute before trying checkout again.'
          : checkoutInvoked
          ? 'Apple checkout could not be confirmed. Do not buy again. Tap Restore purchases to check its status.'
          : e is PlatformException
          ? 'Apple could not open checkout. Check your Apple account or restore an earlier purchase, then try again.'
          : 'Could not connect to family billing. Please try again.';
      if (_disposed) return;
      notifyListeners();
    } finally {
      _checkedExpiredHistory.clear();
      _operationBusy = false;
      if (!checkoutInvoked) _purchasePending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> restore() async {
    if (purchasePending || _loading || _disposed) return;
    if (!AppleSubscriptionConfig.purchaseFlowEnabled) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    _purchasePending = true;
    _operationBusy = true;
    _recentHistory.clear();
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    _sandboxAccountMismatch = false;
    // An explicit retry must recheck Apple after an account change or refund.
    _bindingRejections.clear();
    _completedTransactions.clear();
    _checkedExpiredHistory.clear();
    notifyListeners();
    final attempt = ++_restoreAttempt;
    final userId = _supabase.auth.currentUser?.id;
    final familyId = _familyId;
    bool sameAccount() =>
        !_disposed &&
        userId == _supabase.auth.currentUser?.id &&
        familyId == _familyId;
    try {
      await _updateQueue;
      if (!sameAccount()) return;
      _message = 'Checking your Apple account...';
      notifyListeners();
      await _syncPurchases().timeout(const Duration(seconds: 30));
      await _updateQueue;
      if (!sameAccount()) return;
      // A sync may replay transactions while updating the local receipt. Do not
      // let an earlier cached rejection suppress the explicitly requested retry.
      _bindingRejections.clear();
      _completedTransactions.clear();
      if (await _recoverUnfinished() != _PurchaseRecovery.none) return;
      if (!sameAccount()) return;
      final received = Completer<void>();
      _restoreUpdatesReceived = received;
      await _iap.restorePurchases().timeout(const Duration(seconds: 20));
      // StoreKit emits a batch, including an empty batch, before finishing.
      // Wait for that callback rather than holding the screen for eight seconds.
      await received.future.timeout(const Duration(seconds: 2));
      await _updateQueue;
      if (!sameAccount()) return;
      if (attempt == _restoreAttempt) {
        final previous = await _previousPurchase().timeout(
          const Duration(seconds: 12),
        );
        if (!sameAccount()) return;
        if (previous != null) {
          await _validateAndComplete(previous, historyOnly: true);
        } else {
          _purchasePending = false;
          _needsRecovery = false;
          _message =
              'No previous App Store purchase was found for this Apple account.';
          _error = null;
          notifyListeners();
        }
      }
    } catch (_) {
      if (!sameAccount()) return;
      _purchasePending = false;
      _needsRecovery = true;
      _message = null;
      _error =
          'Could not restore purchases. Check your connection and Apple account, then try again.';
      if (_disposed) return;
      notifyListeners();
    } finally {
      _checkedExpiredHistory.clear();
      _restoreUpdatesReceived = null;
      _operationBusy = false;
      _purchasePending = false;
      if (!_disposed) notifyListeners();
      if (sameAccount()) {
        await refreshSponsorship();
        await refreshProducts();
      }
    }
  }

  Future<ContributionMovePreview?> previewContributionMove() async {
    if (!canMoveContribution || _operationBusy || _purchasePending) return null;
    _movePreview = null;
    final user = _supabase.auth.currentUser?.id, family = _familyId;
    final data = await _requestContributionMove('preview_move');
    if (data == null ||
        user != _supabase.auth.currentUser?.id ||
        family != _familyId) {
      return null;
    }
    try {
      final preview = ContributionMovePreview(data);
      _movePreview = preview;
      _moveUser = _supabase.auth.currentUser?.id;
      _moveFamily = _familyId;
      return preview;
    } catch (_) {
      _moveError = 'Could not read the move details. Please try again.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> confirmContributionMove(ContributionMovePreview preview) async {
    if (!identical(preview, _movePreview) ||
        _moveUser != _supabase.auth.currentUser?.id ||
        _moveFamily != _familyId ||
        _operationBusy ||
        _purchasePending) {
      return false;
    }
    final data = await _requestContributionMove(
      'confirm_move',
      confirmationId: preview.confirmationId,
    );
    if (data == null ||
        data['moved'] != true ||
        _moveUser != _supabase.auth.currentUser?.id ||
        _moveFamily != _familyId) {
      return false;
    }
    _movePreview = null;
    _needsRecovery = false;
    _sandboxAccountMismatch = false;
    _bindingRejections.clear();
    _completedTransactions.clear();
    _error = null;
    _validationDiagnostic = null;
    _moveError = null;
    _moveAvailable = false;
    _message =
        'Your contribution now supports this family. No new payment was made.';
    notifyListeners();
    await refreshSponsorship();
    return true;
  }

  Future<Map?> _requestContributionMove(
    String purpose, {
    String? confirmationId,
  }) async {
    final user = _supabase.auth.currentUser?.id, family = _familyId;
    if (user == null || family == null) return null;
    bool current() =>
        !_disposed &&
        user == _supabase.auth.currentUser?.id &&
        family == _familyId;
    _operationBusy = true;
    _recentHistory.clear();
    _purchasePending = true;
    _moveError = null;
    notifyListeners();
    try {
      await _updateQueue;
      if (!current()) return null;
      final response = await _supabase.functions
          .invoke(
            'validate_apple_subscription',
            body: {
              'purpose': purpose,
              'family_id': family,
              if (confirmationId != null) 'confirmation_id': confirmationId,
            },
          )
          .timeout(const Duration(seconds: 40));
      await _updateQueue;
      if (!current()) return null;
      if (response.status < 200 || response.status >= 300) {
        throw FunctionException(
          status: response.status,
          details: response.data,
        );
      }
      final body = response.data;
      if (body is! Map ||
          body['ok'] != true ||
          body['move'] is! Map ||
          (purpose == 'confirm_move' && body['move']['moved'] != true)) {
        throw const FormatException('Invalid move response');
      }
      return body['move'] as Map;
    } catch (e) {
      if (!current()) return null;
      final details = e is FunctionException ? e.details : null;
      final code = details is Map ? details['code'] : null;
      _moveError = switch (code) {
        'APPLE_MOVE_RATE_LIMIT' =>
          'Please wait a minute before checking the move again.',
        'APPLE_MOVE_STALE' =>
          'The plan or its usage changed. Check the move details again before confirming.',
        'APPLE_SUBSCRIPTION_INACTIVE' =>
          'Apple has not confirmed an active paid contribution. Check its status or try Restore purchases.',
        'APPLE_MOVE_UNAVAILABLE' || 'APPLE_PURCHASER_MISMATCH' =>
          'This contribution could not be moved securely. Use the original Heiro account that paid, or contact support.',
        'FAMILY_MEMBERSHIP_REQUIRED' =>
          'Join this family before moving your contribution.',
        'SPONSOR_PURCHASE_IN_PROGRESS' =>
          'Finish or restore your earlier purchase before moving a contribution.',
        _ =>
          'Could not confirm the move. Check your connection and try again. You will not be charged again.',
      };
      return null;
    } finally {
      _operationBusy = false;
      _purchasePending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> openManageSubscriptions({bool refreshAfter = true}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await const MethodChannel(
          'com.everroots.app/subscriptions',
        ).invokeMethod<void>('manageSubscriptions');
        if (refreshAfter) {
          await refreshSponsorship();
          await refreshStorefront();
        }
        return;
      } on PlatformException {
        // Older builds or a temporarily unavailable sheet can use Apple's URL.
      } on MissingPluginException {
        // The native bridge is unavailable on older installed builds.
      }
    }
    final url = Uri.parse('https://apps.apple.com/account/subscriptions');
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      _error = 'Could not open Apple subscription settings.';
      notifyListeners();
    }
  }

  Future<void> openFamilyPlanManagement() async {
    if (purchasePending || _disposed) return;
    await refreshSponsorship();
    if (!canManageFamilyPlan) {
      _error =
          'Only the original purchaser\'s app account can manage this family subscription.';
      if (!_disposed) notifyListeners();
      return;
    }
    _error = null;
    notifyListeners();
    await openManageSubscriptions();
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (_disposed) return;
      // StoreKit can replay transactions from products outside this catalog.
      // Never validate or finish those as an Ever Roots family subscription.
      if (!AppleSubscriptionConfig.activeProductIds.contains(
        purchase.productID,
      )) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _purchasePending = true;
          _message = 'Waiting for the App Store to finish the purchase.';
          notifyListeners();
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _restoreAttempt++;
          await _validateAndComplete(
            purchase,
            historyOnly: purchase.status == PurchaseStatus.restored,
          );
          break;
        case PurchaseStatus.error:
          _restoreAttempt++;
          _purchasePending = false;
          if (_checkoutProductId == purchase.productID && !_needsRecovery) {
            await _releaseReservation();
          }
          _error = purchase.error?.message ?? 'Purchase failed.';
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          _restoreAttempt++;
          _purchasePending = false;
          if (_checkoutProductId == purchase.productID && !_needsRecovery) {
            await _releaseReservation();
          }
          _checkoutProductId = null;
          _message = 'Purchase cancelled.';
          notifyListeners();
          break;
      }
    }
  }

  Future<_PurchaseValidation> _validateAndComplete(
    PurchaseDetails purchase, {
    bool historyOnly = false,
  }) async {
    final proof =
        '${purchase.productID}:${purchase.verificationData.source}:${purchase.verificationData.localVerificationData}:${purchase.verificationData.serverVerificationData}';
    final cacheKey =
        '${_supabase.auth.currentUser?.id}:$_familyId:${purchase.purchaseID}';
    final cached = _recentHistory[cacheKey];
    if (purchase.purchaseID != null &&
        _checkoutProductId == null &&
        !_needsRecovery &&
        cached != null &&
        cached.proof == proof &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 30)) {
      _purchasePending = false;
      notifyListeners();
      return cached.result;
    }
    final key = '$cacheKey:$historyOnly:$proof';
    final existing = _verifications[key];
    if (existing != null) return existing;
    final validation = _performValidation(purchase, historyOnly: historyOnly);
    _verifications[key] = validation;
    try {
      final result = await validation;
      if (!_disposed &&
          purchase.purchaseID != null &&
          _checkoutProductId == null &&
          (result == _PurchaseValidation.expiredHistory ||
              result == _PurchaseValidation.previousFamily)) {
        if (_recentHistory.length >= 32) _recentHistory.clear();
        _recentHistory[cacheKey] = (
          proof: proof,
          at: DateTime.now(),
          result: result,
        );
      }
      return result;
    } finally {
      _verifications.remove(key);
    }
  }

  Future<_PurchaseValidation> _performValidation(
    PurchaseDetails purchase, {
    required bool historyOnly,
  }) async {
    final familyId = _familyId;
    final userId = _supabase.auth.currentUser?.id;
    if (familyId == null || familyId.isEmpty || userId == null) {
      _purchasePending = false;
      _error = 'Choose a family before purchasing.';
      notifyListeners();
      return _PurchaseValidation.failed;
    }
    final transactionKey = '$userId:$familyId:${purchase.purchaseID}';
    final rejected = _bindingRejections[transactionKey];
    if (rejected != null && !historyOnly) {
      _showValidationFailure(rejected.diagnostic, sandbox: rejected.sandbox);
      return _PurchaseValidation.failed;
    }
    if (!historyOnly &&
        purchase.purchaseID != null &&
        _completedTransactions.contains(transactionKey)) {
      _purchasePending = false;
      return _PurchaseValidation.applied;
    }

    final wasPending = _purchasePending;
    final previousMessage = _message;
    final previousError = _error;
    final previousDiagnostic = _validationDiagnostic;
    try {
      _purchasePending = true;
      _message = _operationBusy && _checkoutProductId == null
          ? 'Checking previous Apple purchases...'
          : historyOnly
          ? 'Checking your previous Apple plan...'
          : 'Verifying your purchase...';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
      final response = await _supabase.functions
          .invoke(
            'validate_apple_subscription',
            body: {
              'family_id': familyId,
              'supports_previous_contribution': true,
              'product_id': purchase.productID,
              'purchase_id': purchase.purchaseID,
              'verification_source': purchase.verificationData.source,
              'local_verification_data':
                  purchase.verificationData.localVerificationData,
              'server_verification_data':
                  purchase.verificationData.serverVerificationData,
              'status': purchase.status.name,
              if (historyOnly) 'purpose': 'history',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.status < 200 || response.status >= 300) {
        throw FunctionException(
          status: response.status,
          details: response.data,
        );
      }
      final data = response.data;
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return _PurchaseValidation.failed;
      }
      if (data is Map &&
          data['ok'] == true &&
          data['previous_contribution'] is Map) {
        final previous = data['previous_contribution'] as Map;
        final until = DateTime.tryParse(
          previous['paid_until']?.toString() ?? '',
        );
        if (previous['code'] != 'APPLE_OWNED_PREVIOUS_CONTRIBUTION' ||
            previous['status'] != 'active' ||
            previous['product_id'] != purchase.productID ||
            until == null) {
          throw const FormatException('Invalid previous contribution response');
        }
        final resolved = previous['resolved_reservation_id'];
        // A replay must never settle an unrelated checkout still in progress.
        if (_checkoutProductId != null &&
            !_operationBusy &&
            (resolved == null || resolved != _reservationId)) {
          _purchasePending = wasPending;
          _message = previousMessage;
          _error = previousError;
          _validationDiagnostic = previousDiagnostic;
          notifyListeners();
          return _PurchaseValidation.previousFamily;
        }
        if (purchase.pendingCompletePurchase &&
            !_finishedPreviousTransactions.contains(transactionKey)) {
          await _iap.completePurchase(purchase);
          if (_disposed ||
              _supabase.auth.currentUser?.id != userId ||
              _familyId != familyId) {
            return _PurchaseValidation.failed;
          }
          _finishedPreviousTransactions.add(transactionKey);
        }
        if (resolved != null && resolved == _reservationId) {
          _reservationId = null;
          _checkoutProductId = null;
        }
        _needsRecovery = false;
        _sandboxAccountMismatch = false;
        _purchasePending = false;
        _error = null;
        _moveError = null;
        _validationDiagnostic = null;
        _message =
            'Your purchase is restored to your previous family. Use Move my contribution to bring its remaining benefits here. No new payment is needed.';
        notifyListeners();
        await refreshSponsorship();
        return _PurchaseValidation.previousFamily;
      }
      if (data is Map && data['ok'] == true && data['history'] is Map) {
        final history = data['history'] as Map;
        if (history['code'] != 'APPLE_EXPIRED_HISTORY' ||
            history['status'] != 'expired' ||
            history['product_id'] != purchase.productID) {
          throw const FormatException('Invalid history response');
        }
        _bindingRejections.remove(transactionKey);
        // A replay is not confirmation of a different checkout still in flight.
        if (_checkoutProductId != null && !_operationBusy) {
          _purchasePending = wasPending;
          _message = previousMessage;
          _error = previousError;
          _validationDiagnostic = previousDiagnostic;
          notifyListeners();
          return _PurchaseValidation.expiredHistory;
        }
        // The server checked Apple's current group status: fully expired, no
        // renewal, grace period or retry. Acknowledge this old queued receipt
        // so StoreKit can open a NEW purchase. This grants/transfers no access
        // and must not release a different checkout reservation.
        if (purchase.pendingCompletePurchase &&
            !_finishedExpiredTransactions.contains(transactionKey)) {
          await _iap.completePurchase(purchase);
          if (_disposed ||
              _supabase.auth.currentUser?.id != userId ||
              _familyId != familyId) {
            return _PurchaseValidation.failed;
          }
          _finishedExpiredTransactions.add(transactionKey);
        }
        if (_operationBusy && purchase.purchaseID != null) {
          _checkedExpiredHistory.add(transactionKey);
        }
        _needsRecovery = false;
        _sandboxAccountMismatch = false;
        _purchasePending = false;
        _message =
            'The previous Apple plan has ended. A new purchase can support this family.';
        _error = null;
        _validationDiagnostic = null;
        notifyListeners();
        if (!_operationBusy) await refreshSponsorship();
        return _PurchaseValidation.expiredHistory;
      }
      if (data is! Map || data['ok'] != true || data['entitlement'] is! Map) {
        throw const FormatException('Invalid validation response');
      }
      final entitlement = data['entitlement'] as Map;
      if (entitlement['product_id'] != purchase.productID ||
          !const [
            'active',
            'expired',
            'refunded',
            'revoked',
          ].contains(entitlement['status'])) {
        throw const FormatException('Invalid entitlement response');
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      if (purchase.purchaseID != null) {
        _completedTransactions.add(transactionKey);
      }
      _needsRecovery = false;
      _sandboxAccountMismatch = false;
      _checkoutProductId = null;
      await _releaseReservation();
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return _PurchaseValidation.failed;
      }

      _purchasePending = false;
      _message = entitlement['status'] == 'active'
          ? 'Family plan updated.'
          : 'This subscription is no longer active.';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
      await refreshSponsorship();
      return _PurchaseValidation.applied;
    } catch (e) {
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return _PurchaseValidation.failed;
      }
      final diagnostic = validationDiagnostic(e);
      debugPrint('Apple subscription validation: $diagnostic');
      final details = e is FunctionException ? e.details : null;
      final sandbox = details is Map && details['environment'] == 'sandbox';
      if (purchase.purchaseID != null && _isAccountMismatch(diagnostic)) {
        if (_bindingRejections.length >= 32) _bindingRejections.clear();
        _bindingRejections[transactionKey] = (
          diagnostic: diagnostic,
          sandbox: sandbox,
        );
      }
      _showValidationFailure(diagnostic, sandbox: sandbox);
      return _PurchaseValidation.failed;
    }
  }

  static bool _isAccountMismatch(String diagnostic) =>
      diagnostic.startsWith('APPLE_PURCHASER_MISMATCH') ||
      diagnostic.startsWith('APPLE_PURCHASE_ALREADY_BOUND');

  void _showValidationFailure(String diagnostic, {required bool sandbox}) {
    _needsRecovery = true;
    _purchasePending = false;
    _message = null;
    _sandboxAccountMismatch = sandbox && _isAccountMismatch(diagnostic);
    _error = diagnostic.startsWith('APPLE_API_AUTHENTICATION_FAILED')
        ? 'Purchase verification is temporarily unavailable on our server. Your purchase has not been confirmed. Do not buy again; please try later or contact support.'
        : diagnostic.startsWith('APPLE_PLAN_IN_PREVIOUS_FAMILY')
        ? 'Your contribution still supports your previous family. You can move it here without paying again, or cancel renewal and wait until its paid period ends.'
        : _isAccountMismatch(diagnostic)
        ? 'This Apple purchase belongs to a different app account or family. '
              'Sign in to the original purchaser\'s app account to restore it. Switching app logins does not switch your Apple purchase account.'
        : diagnostic.startsWith('APPLE_PURCHASER_UNVERIFIED')
        ? 'This Apple purchase could not be linked securely. Contact support before purchasing again.'
        : diagnostic.startsWith('FAMILY_ALREADY_SPONSORED') ||
              diagnostic.startsWith('APPLE_SPONSOR_REPLACED')
        ? 'You already have a subscription linked to your account. Do not purchase again. Manage it with Apple or contact support.'
        : diagnostic.startsWith('APPLE_SUBSCRIPTION_INACTIVE')
        ? 'This previous subscription has expired or been refunded. Check its status in Apple subscription settings.'
        : diagnostic.startsWith('APPLE_PREVIOUS_PLAN_NOT_ENDED')
        ? 'Apple still has an active or renewing plan for this purchase account. Manage it with Apple before starting a plan for another Heiro account.'
        : diagnostic.startsWith('APPLE_HISTORY_CHECK_UNAVAILABLE')
        ? 'Could not confirm that your previous Apple plan has ended. Please try Restore purchases again before buying.'
        : diagnostic.startsWith('SPONSOR_PURCHASE_IN_PROGRESS')
        ? 'An earlier checkout is still awaiting confirmation. Restore that purchase first, or wait for its hold to expire within 15 minutes.'
        : 'Your Apple purchase is awaiting confirmation. Do not buy again. Tap Restore purchases to retry.';
    _validationDiagnostic = diagnostic;
    notifyListeners();
  }

  @visibleForTesting
  static String validationDiagnostic(Object error) {
    if (error is! FunctionException) {
      return error is FormatException
          ? 'VALIDATION_RESPONSE_INVALID'
          : 'VALIDATION_CONNECTION_OR_COMPLETION_FAILED';
    }
    final details = error.details;
    const purchaserCodes = {
      'APPLE_PLAN_IN_PREVIOUS_FAMILY',
      'APPLE_PURCHASER_MISMATCH',
      'APPLE_PURCHASER_UNVERIFIED',
      'APPLE_PURCHASE_ALREADY_BOUND',
      'APPLE_ENVIRONMENT_MISMATCH',
      'FAMILY_ALREADY_SPONSORED',
      'APPLE_SPONSOR_REPLACED',
      'APPLE_SUBSCRIPTION_INACTIVE',
      'FAMILY_MEMBERSHIP_REQUIRED',
      'APPLE_API_AUTHENTICATION_FAILED',
      'APPLE_HISTORY_CHECK_UNAVAILABLE',
      'APPLE_PREVIOUS_PLAN_NOT_ENDED',
      'SPONSOR_PURCHASE_IN_PROGRESS',
    };
    if (details is Map && purchaserCodes.contains(details['code'])) {
      return '${details['code']} (HTTP ${error.status})';
    }
    if (details is Map && details['code'] == 'APPLE_PRODUCT_UNSUPPORTED') {
      String safeProduct(Object? value) {
        final text = value?.toString() ?? '';
        return RegExp(r'^[a-zA-Z0-9_.-]{1,160}$').hasMatch(text)
            ? text
            : 'unknown';
      }

      return 'APPLE_PRODUCT_MISMATCH (HTTP ${error.status}); '
          'requested=${safeProduct(details['requested_product_id'])}; '
          'Apple=${safeProduct(details['apple_product_id'])}';
    }
    final message =
        (details is Map ? details['error'] ?? details['message'] ?? '' : '')
            .toString()
            .toLowerCase();
    String code = 'VALIDATION_REJECTED';
    if (error.status == 401) {
      code = 'AUTH_REJECTED';
    } else if (message.contains('missing apple app store server api secrets')) {
      code = 'APPLE_SECRETS_MISSING';
    } else if (message.contains('apple transaction lookup failed 401')) {
      code = 'APPLE_API_CREDENTIALS_REJECTED';
    } else if (message.contains('apple transaction lookup failed 404')) {
      code = 'APPLE_TRANSACTION_NOT_FOUND_CHECK_ENVIRONMENT';
    } else if (message.contains('only a family owner')) {
      code = 'FAMILY_OWNER_REQUIRED';
    } else if (message.contains('missing apple transaction id')) {
      code = 'APPLE_TRANSACTION_ID_MISSING';
    } else if (message.contains('bundle id')) {
      code = 'APPLE_BUNDLE_MISMATCH';
    } else if (message.contains('unsupported apple subscription')) {
      code = 'APPLE_PRODUCT_MISMATCH';
    }
    return '$code (HTTP ${error.status})';
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  static String? _friendlyError(String? error) {
    if (error == null || error.trim().isEmpty) return null;
    final lower = error.toLowerCase();
    if (lower.contains('failed to get response from platform') ||
        lower.contains('storekit')) {
      return 'Prices are temporarily unavailable. Open the latest TestFlight build and try again.';
    }
    return error;
  }
}
