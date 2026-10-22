import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apple_subscription_config.dart';

enum _PurchaseRecovery { none, recovered, failed }

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
  final Map<String, Future<bool>> _verifications = {};
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
    for (final purchase in purchases) {
      if (!AppleSubscriptionConfig.activeProductIds.contains(
        purchase.productID,
      )) {
        continue;
      }
      if (!await _validateAndComplete(purchase)) {
        return _PurchaseRecovery.failed;
      }
      recovered = true;
    }
    return recovered ? _PurchaseRecovery.recovered : _PurchaseRecovery.none;
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
  bool _isSponsor = false;
  String? _sponsorName;
  DateTime? _paidUntil;
  Map<String, dynamic>? _familyUsage;
  bool _billingRefreshing = false;
  int _billingRefresh = 0;
  String? _billingUserId;

  bool get canSponsor =>
      !_needsRecovery &&
      _sponsorshipLoaded &&
      _billingUserId == _supabase.auth.currentUser?.id &&
      (!_familySponsored || _isSponsor);
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

  Future<void> refreshSponsorship() async {
    final familyId = _familyId;
    if (familyId == null || familyId.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    if (_billingUserId != userId) {
      _sponsorshipLoaded = false;
      _familyUsage = null;
      _familySponsored = false;
      _isSponsor = false;
      _paidUntil = null;
      _billingUserId = userId;
    }
    final request = ++_billingRefresh;
    bool current() =>
        !_disposed &&
        request == _billingRefresh &&
        familyId == _familyId &&
        userId == _supabase.auth.currentUser?.id;
    _billingRefreshing = true;
    notifyListeners();
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
      _familySponsored = data['active'] == true;
      _isSponsor = data['is_sponsor'] == true;
      _sponsorName = data['sponsor_name']?.toString();
      _paidUntil = DateTime.tryParse(data['paid_until']?.toString() ?? '');
      _sponsorshipLoaded = true;
    } catch (_) {
      if (!current()) return;
      _sponsorshipLoaded = false;
    }
    try {
      final usage = await _supabase
          .rpc(
            'get_family_entitlements_and_usage',
            params: {'p_family_id': familyId},
          )
          .timeout(const Duration(seconds: 12));
      if (!current()) return;
      if (usage is! Map ||
          usage['plan'] is! String ||
          usage['limits'] is! Map ||
          usage['usage'] is! Map) {
        throw const FormatException('Invalid family usage response');
      }
      _familyUsage = Map<String, dynamic>.from(usage);
    } catch (_) {
      if (!current()) return;
      _familyUsage = null;
    } finally {
      if (current()) {
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
      _isSponsor = false;
    }
    _familyId = familyId.trim();
    await refreshSponsorship();
    if (!AppleSubscriptionConfig.purchaseFlowEnabled ||
        AppleSubscriptionConfig.activeProductIds.isEmpty) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    if (_initialized) return;
    _initialized = true;
    await refreshProducts();
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

      try {
        _storefrontCountryCode = await _iap.countryCode().timeout(
          const Duration(seconds: 12),
        );
      } catch (_) {
        _storefrontCountryCode = null;
      }

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
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    _sandboxAccountMismatch = false;
    _bindingRejections.clear();
    notifyListeners();

    var checkoutInvoked = false;
    try {
      await refreshSponsorship();
      if (!canSponsor) {
        _message = null;
        _error = hasActiveSponsor
            ? 'The current purchaser manages this family plan. Another member can sponsor after its paid coverage ends.'
            : 'Could not check family billing. Refresh the plan and try again.';
        return;
      }
      // Resolve an earlier Apple charge before requesting another product.
      await _updateQueue;
      if (await _recoverUnfinished() != _PurchaseRecovery.none) return;
      // Even a finished, expired Apple subscription may belong to a different
      // app account. Verify its binding before allowing a renewal or plan change.
      final previous = await _previousPurchase().timeout(
        const Duration(seconds: 12),
      );
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return;
      }
      if (previous != null && !await _validateAndComplete(previous)) return;
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return;
      }
      _purchasePending = true;
      _message = null;
      final reservation = await _supabase
          .rpc('begin_family_sponsorship', params: {'p_family_id': familyId})
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
      checkoutInvoked = true;
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
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
          : code == 'FAMILY_ALREADY_SPONSORED'
          ? 'This family already has a sponsor. Its shared plan is available to all members.'
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
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    _sandboxAccountMismatch = false;
    // An explicit retry must recheck Apple after an account change or refund.
    _bindingRejections.clear();
    _completedTransactions.clear();
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
          await _validateAndComplete(previous);
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
          await _validateAndComplete(purchase);
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

  Future<bool> _validateAndComplete(PurchaseDetails purchase) async {
    final key =
        '${_supabase.auth.currentUser?.id}:$_familyId:${purchase.purchaseID}';
    final existing = _verifications[key];
    if (existing != null) return existing;
    final validation = _performValidation(purchase);
    _verifications[key] = validation;
    try {
      return await validation;
    } finally {
      _verifications.remove(key);
    }
  }

  Future<bool> _performValidation(PurchaseDetails purchase) async {
    final familyId = _familyId;
    final userId = _supabase.auth.currentUser?.id;
    if (familyId == null || familyId.isEmpty || userId == null) {
      _purchasePending = false;
      _error = 'Choose a family before purchasing.';
      notifyListeners();
      return false;
    }
    final transactionKey = '$userId:$familyId:${purchase.purchaseID}';
    final rejected = _bindingRejections[transactionKey];
    if (rejected != null) {
      _showValidationFailure(rejected.diagnostic, sandbox: rejected.sandbox);
      return false;
    }
    if (purchase.purchaseID != null &&
        _completedTransactions.contains(transactionKey)) {
      _purchasePending = false;
      return true;
    }

    try {
      _purchasePending = true;
      _message = 'Verifying your purchase...';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
      final response = await _supabase.functions
          .invoke(
            'validate_apple_subscription',
            body: {
              'family_id': familyId,
              'product_id': purchase.productID,
              'purchase_id': purchase.purchaseID,
              'verification_source': purchase.verificationData.source,
              'local_verification_data':
                  purchase.verificationData.localVerificationData,
              'server_verification_data':
                  purchase.verificationData.serverVerificationData,
              'status': purchase.status.name,
            },
          )
          .timeout(const Duration(seconds: 20));

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
        return false;
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
      await _releaseReservation();
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return false;
      }

      _purchasePending = false;
      _message = entitlement['status'] == 'active'
          ? 'Family plan updated.'
          : 'This subscription is no longer active.';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
      await refreshSponsorship();
      return true;
    } catch (e) {
      if (_disposed ||
          _supabase.auth.currentUser?.id != userId ||
          _familyId != familyId) {
        _purchasePending = false;
        return false;
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
      return false;
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
        : _isAccountMismatch(diagnostic)
        ? 'This Apple purchase belongs to a different app account or family. '
              'Sign in to the original purchaser\'s app account to restore it. Switching app logins does not switch your Apple purchase account.'
        : diagnostic.startsWith('APPLE_PURCHASER_UNVERIFIED')
        ? 'This Apple purchase could not be linked securely. Contact support before purchasing again.'
        : diagnostic.startsWith('FAMILY_ALREADY_SPONSORED') ||
              diagnostic.startsWith('APPLE_SPONSOR_REPLACED')
        ? 'This family has another sponsor. Do not purchase again. Manage your subscription with Apple or contact support.'
        : diagnostic.startsWith('APPLE_SUBSCRIPTION_INACTIVE')
        ? 'This previous subscription has expired or been refunded. Check its status in Apple subscription settings.'
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
      'APPLE_PURCHASER_MISMATCH',
      'APPLE_PURCHASER_UNVERIFIED',
      'APPLE_PURCHASE_ALREADY_BOUND',
      'APPLE_ENVIRONMENT_MISMATCH',
      'FAMILY_ALREADY_SPONSORED',
      'APPLE_SPONSOR_REPLACED',
      'APPLE_SUBSCRIPTION_INACTIVE',
      'FAMILY_MEMBERSHIP_REQUIRED',
      'APPLE_API_AUTHENTICATION_FAILED',
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
