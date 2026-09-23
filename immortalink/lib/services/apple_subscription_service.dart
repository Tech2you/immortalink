import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'apple_subscription_config.dart';

class AppleSubscriptionService extends ChangeNotifier {
  AppleSubscriptionService({SupabaseClient? supabase, InAppPurchase? iap})
    : _supabase = supabase ?? Supabase.instance.client,
      _iap = iap ?? InAppPurchase.instance;

  final SupabaseClient _supabase;
  final InAppPurchase _iap;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _updateQueue = Future<void>.value();
  Timer? _validationErrorTimer;
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
  String? _validationDiagnostic;

  bool get loading => _loading;
  bool get purchasePending => _purchasePending;
  bool get storeAvailable => _storeAvailable;
  String? get storefrontCountryCode => _storefrontCountryCode;
  String? get message => _message;
  String? get error => _friendlyError(_error);
  List<ProductDetails> get products => _productsById.values.toList();
  List<String> get requestedProductIds => _requestedProductIds.toList()..sort();
  List<String> get foundProductIds => _productsById.keys.toList()..sort();
  List<String> get notFoundProductIds => _notFoundProductIds.toList()..sort();
  String? get rawError => _validationDiagnostic ?? _error;
  bool get hasPricingDiagnostics =>
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      (_error != null || (_initialized && !_loading && _productsById.isEmpty));

  ProductDetails? productFor(String productId) => _productsById[productId];

  Future<void> refreshStorefront() async {
    if (!_initialized || _loading) return;
    if (!_storeAvailable || _productsById.isEmpty || _error != null) {
      await refreshProducts();
      return;
    }
    try {
      final country = await _iap.countryCode();
      if (country != _storefrontCountryCode) await refreshProducts();
    } catch (_) {
      // A temporary storefront lookup failure must not interrupt verification.
    }
  }

  Future<void> initialize({required String familyId}) async {
    _familyId = familyId.trim();
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
    if (_loading || _disposed) return;
    if (!AppleSubscriptionConfig.purchaseFlowEnabled ||
        AppleSubscriptionConfig.activeProductIds.isEmpty) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    _setLoading(true);
    _message = null;
    try {
      _requestedProductIds
        ..clear()
        ..addAll(AppleSubscriptionConfig.activeProductIds);
      _notFoundProductIds.clear();
      _storeAvailable = await _iap.isAvailable().timeout(
        const Duration(seconds: 12),
      );
      if (!_storeAvailable) {
        _error = 'The App Store is not available on this device.';
        return;
      }

      try {
        _storefrontCountryCode = await _iap.countryCode().timeout(
          const Duration(seconds: 12),
        );
      } catch (e) {
        _storefrontCountryCode = 'Unavailable: $e';
      }

      _purchaseSubscription ??= _iap.purchaseStream.listen(
        (purchases) {
          _updateQueue = _updateQueue.then((_) async {
            if (!_disposed) await _handlePurchaseUpdates(purchases);
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
        _error = response.error!.message;
      } else if (_productsById.isEmpty) {
        _error = 'No App Store subscription products were found.';
      } else {
        _error = null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> buy(String productId) async {
    if (_purchasePending || _loading) return;
    final product = _productsById[productId];
    final familyId = _familyId;
    if (product == null || familyId == null || familyId.isEmpty) return;

    _purchasePending = true;
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    notifyListeners();

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
        _purchasePending = false;
        _error = 'The App Store did not start the purchase.';
        notifyListeners();
      }
    } catch (_) {
      _purchasePending = false;
      _error = 'The App Store did not start the purchase.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (_purchasePending || _loading) return;
    if (!AppleSubscriptionConfig.purchaseFlowEnabled) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    _purchasePending = true;
    _message = null;
    _error = null;
    _validationDiagnostic = null;
    notifyListeners();
    final attempt = ++_restoreAttempt;
    try {
      await _iap.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 8));
      if (attempt == _restoreAttempt && _purchasePending) {
        _purchasePending = false;
        _message = 'No previous App Store purchase was found.';
        notifyListeners();
      }
    } catch (e) {
      _purchasePending = false;
      _error = 'Restore failed: $e';
      notifyListeners();
    }
  }

  Future<void> openManageSubscriptions({bool refreshAfter = true}) async {
    _error = null;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await const MethodChannel(
          'com.everroots.app/subscriptions',
        ).invokeMethod<void>('manageSubscriptions');
        if (refreshAfter) await refreshStorefront();
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

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    await refreshStorefront();
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
          _validationErrorTimer?.cancel();
          _restoreAttempt++;
          _purchasePending = false;
          _error = purchase.error?.message ?? 'Purchase failed.';
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          _validationErrorTimer?.cancel();
          _restoreAttempt++;
          _purchasePending = false;
          _message = 'Purchase cancelled.';
          notifyListeners();
          break;
      }
    }
  }

  Future<void> _validateAndComplete(PurchaseDetails purchase) async {
    final familyId = _familyId;
    if (familyId == null || familyId.isEmpty) {
      _purchasePending = false;
      _error = 'Choose a family before purchasing.';
      notifyListeners();
      return;
    }

    try {
      _validationErrorTimer?.cancel();
      _purchasePending = true;
      _message = 'Verifying your purchase...';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
      final response = await _supabase.functions.invoke(
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
      );

      if (response.status < 200 || response.status >= 300) {
        throw FunctionException(
          status: response.status,
          details: response.data,
        );
      }
      final data = response.data;
      if (_disposed) return;
      if (data is! Map || data['ok'] != true || data['entitlement'] is! Map) {
        throw const FormatException('Invalid validation response');
      }
      final entitlement = data['entitlement'] as Map;
      if (entitlement['product_id'] != purchase.productID ||
          !const [
            'active',
            'expired',
            'refunded',
          ].contains(entitlement['status'])) {
        throw const FormatException('Invalid entitlement response');
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }

      _purchasePending = false;
      _message = entitlement['status'] == 'active'
          ? 'Family plan updated.'
          : 'This subscription is no longer active.';
      _error = null;
      _validationDiagnostic = null;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      final diagnostic = validationDiagnostic(e);
      debugPrint('Apple subscription validation: $diagnostic');
      // A restore may immediately deliver another transaction. Keep the
      // checking state briefly, but surface unresolved failures without
      // completing the rejected transaction or granting access locally.
      _validationErrorTimer?.cancel();
      _validationErrorTimer = Timer(const Duration(seconds: 2), () {
        if (_disposed) return;
        _purchasePending = false;
        _message = null;
        _error =
            'We could not confirm this purchase. Tap Restore purchases to retry.';
        _validationDiagnostic = diagnostic;
        notifyListeners();
      });
    }
  }

  @visibleForTesting
  static String validationDiagnostic(Object error) {
    if (error is! FunctionException) {
      return error is FormatException
          ? 'VALIDATION_RESPONSE_INVALID'
          : 'VALIDATION_CONNECTION_OR_COMPLETION_FAILED';
    }
    final details = error.details;
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
    _validationErrorTimer?.cancel();
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
