import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/services/apple_subscription_config.dart';
import 'package:immortalink/services/apple_subscription_service.dart';

class FakeFunctions implements FunctionsClient {
  Object result = FunctionResponse(status: 200, data: {'ok': false});

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      final value = result;
      return value is FunctionResponse
          ? Future<FunctionResponse>.value(value)
          : Future<FunctionResponse>.error(value);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeSupabase implements SupabaseClient {
  @override
  final FakeFunctions functions = FakeFunctions();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStore implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  String country = 'USA';
  int completed = 0;
  int queries = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String> countryCode() async => country;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    return ProductDetailsResponse(
      productDetails: ids
          .map(
            (id) => ProductDetails(
              id: id,
              title: 'Family',
              description: 'Family plan',
              price: country == 'USA' ? '\$5.99' : 'R119.99',
              rawPrice: country == 'USA' ? 5.99 : 119.99,
              currencyCode: country == 'USA' ? 'USD' : 'ZAR',
            ),
          )
          .toList(),
      notFoundIDs: [],
    );
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'classifies server rejection without exposing payload or credentials',
    () {
      final error = FunctionException(
        status: 400,
        details: {
          'error': 'Apple transaction lookup failed 401: secret-content',
        },
      );
      expect(
        AppleSubscriptionService.validationDiagnostic(error),
        'APPLE_API_CREDENTIALS_REJECTED (HTTP 400)',
      );
      expect(
        AppleSubscriptionService.validationDiagnostic(
          FunctionException(status: 401, details: {'message': 'Invalid JWT'}),
        ),
        'AUTH_REJECTED (HTTP 401)',
      );
    },
  );

  group(
    'purchase lifecycle',
    () {
      late FakeStore store;
      late FakeSupabase backend;
      late AppleSubscriptionService service;
      late String productId;
      setUp(() async {
        store = FakeStore();
        backend = FakeSupabase();
        service = AppleSubscriptionService(supabase: backend, iap: store);
        productId = AppleSubscriptionConfig.activeProductIds.first;
        await service.initialize(familyId: 'test-family');
      });
      tearDown(() async {
        service.dispose();
        await store.updates.close();
      });

      Future<void> purchase() async {
        store.updates.add([
          PurchaseDetails(
            productID: productId,
            purchaseID: 'test-transaction',
            verificationData: PurchaseVerificationData(
              localVerificationData: '',
              serverVerificationData: '',
              source: 'app_store',
            ),
            transactionDate: null,
            status: PurchaseStatus.purchased,
          )..pendingCompletePurchase = true,
        ]);
        await pumpEventQueue();
      }

      test('refreshes localized catalog after storefront changes', () async {
        expect(service.productFor(productId)!.currencyCode, 'USD');
        store.country = 'ZAF';
        await service.refreshStorefront();
        expect(service.productFor(productId)!.price, 'R119.99');
        expect(service.storefrontCountryCode, 'ZAF');
        expect(store.queries, 2);
      });
      test(
        'does not finish a purchase on an invalid success response',
        () async {
          await purchase();
          expect(store.completed, 0);
          expect(service.rawError, 'VALIDATION_RESPONSE_INVALID');
          expect(service.purchasePending, false);
        },
      );
      test(
        'keeps rejected purchase unfinished and exposes safe reason',
        () async {
          backend.functions.result = FunctionException(
            status: 401,
            details: {'message': 'Invalid JWT'},
          );
          await purchase();
          expect(store.completed, 0);
          expect(service.rawError, 'AUTH_REJECTED (HTTP 401)');
        },
      );
      test('finishes only after a matching verified entitlement', () async {
        backend.functions.result = FunctionResponse(
          status: 200,
          data: {
            'ok': true,
            'entitlement': {'product_id': productId, 'status': 'active'},
          },
        );
        await purchase();
        expect(store.completed, 1);
        expect(service.message, 'Family plan updated.');
        expect(service.error, isNull);
      });
    },
    skip:
        !AppleSubscriptionConfig.purchaseFlowEnabled ||
            AppleSubscriptionConfig.activeProductIds.isEmpty
        ? 'Run with the local purchase build defines.'
        : false,
  );
}
