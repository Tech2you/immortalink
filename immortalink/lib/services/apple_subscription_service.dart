import 'dart:async';

import 'package:flutter/foundation.dart';
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
  final Map<String, ProductDetails> _productsById = {};
  final Set<String> _requestedProductIds = {};
  final Set<String> _notFoundProductIds = {};

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _loading = false;
  bool _purchasePending = false;
  String? _familyId;
  String? _message;
  String? _error;

  bool get loading => _loading;
  bool get purchasePending => _purchasePending;
  bool get storeAvailable => _storeAvailable;
  String? get message => _message;
  String? get error => _friendlyError(_error);
  List<ProductDetails> get products => _productsById.values.toList();
  List<String> get requestedProductIds => _requestedProductIds.toList()..sort();
  List<String> get foundProductIds => _productsById.keys.toList()..sort();
  List<String> get notFoundProductIds => _notFoundProductIds.toList()..sort();
  String? get rawError => _error;
  bool get hasPricingDiagnostics =>
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      (_error != null || (_initialized && !_loading && _productsById.isEmpty));

  ProductDetails? productFor(String productId) => _productsById[productId];

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
    _setLoading(true);

    try {
      _requestedProductIds
        ..clear()
        ..addAll(AppleSubscriptionConfig.activeProductIds);
      _notFoundProductIds.clear();
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) {
        _error = 'The App Store is not available on this device.';
        return;
      }

      _purchaseSubscription = _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error) {
          _purchasePending = false;
          _error = 'Purchase update failed: $error';
          notifyListeners();
        },
      );

      final response = await _iap.queryProductDetails(
        AppleSubscriptionConfig.activeProductIds.toSet(),
      );
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
    final product = _productsById[productId];
    final familyId = _familyId;
    if (product == null || familyId == null || familyId.isEmpty) return;

    _purchasePending = true;
    _message = null;
    _error = null;
    notifyListeners();

    final purchaseParam = PurchaseParam(productDetails: product);
    final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started) {
      _purchasePending = false;
      _error = 'The App Store did not start the purchase.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!AppleSubscriptionConfig.purchaseFlowEnabled) {
      _message = 'Purchases are not enabled for this build yet.';
      notifyListeners();
      return;
    }

    _purchasePending = true;
    _message = null;
    _error = null;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> openManageSubscriptions() async {
    final url = Uri.parse('https://apps.apple.com/account/subscriptions');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      _error = 'Could not open Apple subscription settings.';
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _purchasePending = true;
          _message = 'Waiting for the App Store to finish the purchase.';
          notifyListeners();
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _validateAndComplete(purchase);
          break;
        case PurchaseStatus.error:
          _purchasePending = false;
          _error = purchase.error?.message ?? 'Purchase failed.';
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
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
        throw Exception('Validation failed: HTTP ${response.status}');
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }

      _purchasePending = false;
      _message = 'Family plan updated.';
      _error = null;
      notifyListeners();
    } catch (e) {
      _purchasePending = false;
      _error =
          'The App Store purchase was not verified. Your family plan was not changed.';
      debugPrint('Apple subscription validation failed: $e');
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  @override
  void dispose() {
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
