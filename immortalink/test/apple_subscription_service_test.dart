import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/services/apple_subscription_config.dart';
import 'package:immortalink/services/apple_subscription_service.dart';

class FakeFunctions implements FunctionsClient {
  Object result = FunctionResponse(status: 200, data: {'ok': false});
  int calls = 0;
  Object? lastBody;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      calls++;
      lastBody = invocation.namedArguments[#body];
      final value = result;
      if (value is Future<FunctionResponse>) return value;
      return value is FunctionResponse
          ? Future<FunctionResponse>.value(value)
          : Future<FunctionResponse>.error(value);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeAuth implements GoTrueClient {
  @override
  User? currentUser = User(
    id: '00000000-0000-4000-8000-000000000001',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  FakeRpc(this.result);
  final Object? result;
  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) =>
      then<dynamic>((value) => value).timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic) onValue, {
    Function? onError,
  }) {
    final future = result is Exception
        ? Future<dynamic>.error(result!)
        : Future<dynamic>.value(result);
    return future.then(onValue, onError: onError);
  }
}

class FakeSupabase implements SupabaseClient {
  Object? reservationError;
  int reservations = 0;
  int releases = 0;
  Map<String, dynamic> sponsorship = {'active': false, 'is_sponsor': false};
  Object? usage = {
    'plan': 'free',
    'limits': {'storage_bytes': 500000000},
    'usage': {'storage_bytes': 13000000},
  };
  @override
  final FakeAuth auth = FakeAuth();
  @override
  final FakeFunctions functions = FakeFunctions();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #rpc) {
      if (invocation.positionalArguments.first == 'begin_family_sponsorship') {
        reservations++;
        return FakeRpc(reservationError ?? {'reservation_id': 'checkout-id'});
      }
      if (invocation.positionalArguments.first ==
          'release_family_sponsorship') {
        releases++;
        return FakeRpc(null);
      }
      if (invocation.positionalArguments.first ==
          'get_family_entitlements_and_usage') {
        return FakeRpc(usage);
      }
      return FakeRpc(sponsorship);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeStore implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  String country = 'USA';
  int completed = 0;
  int queries = 0;
  bool available = true;
  bool empty = false;
  PurchaseParam? lastPurchase;
  Object? purchaseError;
  bool started = true;
  int countryLookups = 0;
  Future<String>? countryResponse;
  Future<void> Function()? onRestore;
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastPurchase = purchaseParam;
    if (purchaseError != null) throw purchaseError!;
    return started;
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String> countryCode() async {
    countryLookups++;
    return countryResponse ?? country;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    return ProductDetailsResponse(
      productDetails: (empty ? <String>{} : ids)
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
  Future<void> restorePurchases({String? applicationUserName}) async {
    if (onRestore != null) return onRestore!();
    updates.add([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('history and unfinished recovery preserve the signed Apple receipt', () {
    final transaction = SK2Transaction(
      id: '123',
      originalId: '100',
      productId: 'everroots.family.monthly',
      purchaseDate: '1700000000000',
      appAccountToken: 'purchaser-token',
      receiptData: 'apple.signed.receipt',
      jsonRepresentation: '{"environment":"Sandbox"}',
    );
    for (final status in [PurchaseStatus.restored, PurchaseStatus.purchased]) {
      final purchase = AppleSubscriptionService.storeKitPurchaseDetails(
        transaction,
        status: status,
      );
      expect(purchase.purchaseID, '123');
      expect(purchase.productID, transaction.productId);
      expect(purchase.appAccountToken, 'purchaser-token');
      expect(purchase.status, status);
      expect(
        purchase.verificationData.serverVerificationData,
        'apple.signed.receipt',
      );
      expect(
        purchase.verificationData.localVerificationData,
        transaction.jsonRepresentation,
      );
    }
  });

  test(
    'server Apple authentication failure has a distinct safe diagnostic',
    () {
      expect(
        AppleSubscriptionService.validationDiagnostic(
          FunctionException(
            status: 502,
            details: {'code': 'APPLE_API_AUTHENTICATION_FAILED'},
          ),
        ),
        'APPLE_API_AUTHENTICATION_FAILED (HTTP 502)',
      );
    },
  );

  testWidgets('opens the native Apple management sheet on iPhone', (
    tester,
  ) async {
    const channel = MethodChannel('com.everroots.app/subscriptions');
    String? method;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      method = call.method;
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final store = FakeStore();
    final service = AppleSubscriptionService(
      supabase: FakeSupabase(),
      iap: store,
    );
    try {
      await service.openManageSubscriptions();
      expect(method, 'manageSubscriptions');
      expect(service.error, isNull);
    } finally {
      service.dispose();
      await store.updates.close();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });

  test('product diagnostics expose only bounded product identifiers', () {
    final result = AppleSubscriptionService.validationDiagnostic(
      FunctionException(
        status: 400,
        details: {
          'code': 'APPLE_PRODUCT_UNSUPPORTED',
          'requested_product_id': 'everroots.legacy.monthly',
          'apple_product_id': 'old.product',
          'receipt': 'private-receipt',
        },
      ),
    );
    expect(
      result,
      contains('requested=everroots.legacy.monthly; Apple=old.product'),
    );
    expect(result, isNot(contains('private-receipt')));
  });

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
      testWidgets(
        'expired history bridge submits its signed receipt for verification',
        (tester) async {
          const channel = MethodChannel('com.everroots.app/subscriptions');
          final product = AppleSubscriptionConfig.activeProductIds.first;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async {
              expect(call.method, 'latestSubscriptionTransaction');
              expect(call.arguments, contains(product));
              return {
                'id': 'history-tx',
                'productId': product,
                'purchaseDate': '1700000000000',
                'receiptData': 'signed.expired.transaction',
                'jsonRepresentation': '{}',
                'appAccountToken': null,
              };
            },
          );
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          final store = FakeStore();
          final backend = FakeSupabase();
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {'product_id': product, 'status': 'expired'},
            },
          );
          final service = AppleSubscriptionService(
            supabase: backend,
            iap: store,
            unfinishedPurchases: () async => [],
            syncPurchases: () async {},
          );
          try {
            await service.initialize(familyId: 'test-family');
            await service.restore();
            expect(
              backend.functions.lastBody,
              containsPair(
                'server_verification_data',
                'signed.expired.transaction',
              ),
            );
            expect(
              backend.functions.lastBody,
              containsPair('purchase_id', 'history-tx'),
            );
            expect(service.error, isNull);
            expect(service.message, 'This subscription is no longer active.');
            expect(store.lastPurchase, isNull);
          } finally {
            service.dispose();
            await store.updates.close();
            debugDefaultTargetPlatformOverride = null;
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              null,
            );
          }
        },
      );

      late FakeStore store;
      late FakeSupabase backend;
      late AppleSubscriptionService service;
      late String productId;
      late List<PurchaseDetails> unfinished;
      PurchaseDetails? previous;
      Future<void> Function()? onSync;
      int syncCalls = 0;
      setUp(() async {
        store = FakeStore();
        backend = FakeSupabase();
        unfinished = [];
        previous = null;
        onSync = null;
        syncCalls = 0;
        service = AppleSubscriptionService(
          supabase: backend,
          iap: store,
          unfinishedPurchases: () async => unfinished,
          previousPurchase: () async => previous,
          syncPurchases: () async {
            syncCalls++;
            await onSync?.call();
          },
        );
        productId = AppleSubscriptionConfig.activeProductIds.first;
        await service.initialize(familyId: 'test-family');
      });
      tearDown(() async {
        service.dispose();
        await store.updates.close();
      });

      PurchaseDetails savedPurchase() => PurchaseDetails(
        productID: productId,
        purchaseID: 'unfinished-tx',
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'app_store',
        ),
        transactionDate: null,
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;

      void verified() {
        backend.functions.result = FunctionResponse(
          status: 200,
          data: {
            'ok': true,
            'entitlement': {'product_id': productId, 'status': 'active'},
          },
        );
      }

      test(
        'Apple server outage keeps the purchase unfinished without suggesting an immediate restore loop',
        () async {
          unfinished = [savedPurchase()];
          backend.functions.result = FunctionException(
            status: 502,
            details: {'code': 'APPLE_API_AUTHENTICATION_FAILED'},
          );
          await service.restore();
          expect(store.completed, 0);
          expect(store.lastPurchase, isNull);
          expect(service.error, contains('on our server'));
          expect(
            service.error,
            isNot(contains('Tap Restore purchases to retry')),
          );
          expect(service.canSponsor, isFalse);
        },
      );

      test(
        'finished history belonging to another account blocks Apple checkout',
        () async {
          previous = savedPurchase()..pendingCompletePurchase = false;
          backend.functions.result = FunctionException(
            status: 400,
            details: {'code': 'APPLE_PURCHASE_ALREADY_BOUND'},
          );
          await service.buy(productId);
          expect(store.lastPurchase, isNull);
          expect(backend.reservations, 0);
          expect(store.completed, 0);
          expect(service.error, contains("original purchaser's app account"));
        },
      );

      test(
        'rightful account can renew after verifying its expired history',
        () async {
          previous = savedPurchase()..pendingCompletePurchase = false;
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {'product_id': productId, 'status': 'expired'},
            },
          );
          await service.buy(productId);
          expect(backend.functions.calls, 1);
          expect(backend.reservations, 1);
          expect(store.lastPurchase, isNotNull);
          expect(store.completed, 0);
        },
      );

      test(
        'unfinished purchase is verified without opening another checkout',
        () async {
          unfinished.add(savedPurchase());
          verified();
          await service.buy(productId);
          expect(store.lastPurchase, isNull);
          expect(backend.reservations, 0);
          expect(store.completed, 1);
          expect(service.message, 'Family plan updated.');
          expect(service.purchasePending, false);
        },
      );

      test(
        'restore clears a cached mismatch after the server acknowledges owned retired history',
        () async {
          previous = savedPurchase()..pendingCompletePurchase = false;
          backend.functions.result = FunctionException(
            status: 400,
            details: {
              'code': 'APPLE_PURCHASER_MISMATCH',
              'environment': 'sandbox',
            },
          );
          await service.restore();
          expect(service.canSponsor, false);
          expect(service.purchaseAccountMismatch, true);
          expect(store.lastPurchase, isNull);
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {
                'applied': true,
                'code': 'APPLE_RETIRED_HISTORY',
                'plan': 'free',
                'product_id': productId,
                'status': 'expired',
              },
            },
          );
          await service.restore();
          expect(service.error, isNull);
          expect(service.purchaseAccountMismatch, false);
          expect(service.canSponsor, true);
          expect(service.message, 'This subscription is no longer active.');
          expect(backend.reservations, 0);
          expect(store.completed, 0);
          expect(store.lastPurchase, isNull);
          await service.buy(productId);
          expect(backend.reservations, 1);
          expect(
            store.lastPurchase?.applicationUserName,
            backend.auth.currentUser!.id,
          );
        },
      );

      test(
        'restore recovers unfinished purchases and deduplicates replay',
        () async {
          unfinished.add(savedPurchase());
          verified();
          await service.restore();
          store.updates.add([savedPurchase()]);
          await pumpEventQueue();
          expect(store.completed, 1);
          expect(backend.functions.calls, 1);
        },
      );

      test(
        'double tap during unfinished recovery cannot start another charge',
        () async {
          unfinished.add(savedPurchase());
          final response = Completer<FunctionResponse>();
          backend.functions.result = response.future;
          final first = service.buy(productId);
          await pumpEventQueue();
          await service.buy(productId);
          expect(service.purchasePending, true);
          expect(backend.functions.calls, 1);
          verified();
          response.complete(backend.functions.result as FunctionResponse);
          await first;
          expect(store.completed, 1);
          expect(store.lastPurchase, isNull);
        },
      );

      test(
        'a rejected unfinished purchase blocks new checkout and stays unfinished',
        () async {
          unfinished.add(savedPurchase());
          await service.buy(productId);
          await service.buy(productId);
          expect(service.canSponsor, false);
          expect(store.lastPurchase, isNull);
          expect(store.completed, 0);
          expect(service.error, contains('Do not buy again'));
        },
      );

      test(
        'unstarted or cancelled checkout releases its reservation',
        () async {
          store.started = false;
          await service.buy(productId);
          expect(backend.releases, 1);
          store.started = true;
          await service.buy(productId);
          store.updates.add([
            savedPurchase()..status = PurchaseStatus.canceled,
          ]);
          await pumpEventQueue();
          expect(backend.releases, 2);
          expect(service.purchasePending, false);
        },
      );

      test(
        'StoreKit duplicate is a recovery error, not a connection failure',
        () async {
          store.purchaseError = PlatformException(
            code: 'storekit_duplicate_product_object',
          );
          await service.buy(productId);
          expect(backend.releases, 1);
          expect(service.error, contains('earlier Apple purchase'));
          expect(service.canSponsor, false);
        },
      );

      test(
        'uncertain StoreKit error retains the hold and blocks another charge',
        () async {
          store.purchaseError = PlatformException(code: 'bridge_failed');
          await service.buy(productId);
          expect(backend.releases, 0);
          expect(service.canSponsor, false);
          expect(service.error, contains('Do not buy again'));
        },
      );

      test(
        'account switch during verification never finishes for the new account',
        () async {
          unfinished.add(savedPurchase());
          final response = Completer<FunctionResponse>();
          backend.functions.result = response.future;
          final restoring = service.restore();
          await pumpEventQueue();
          backend.auth.currentUser = User(
            id: 'another-account',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '',
          );
          verified();
          response.complete(backend.functions.result as FunctionResponse);
          await restoring;
          expect(store.completed, 0);
          expect(backend.releases, 0);
          expect(service.purchasePending, false);
        },
      );

      test('passes the signed-in app account UUID to StoreKit', () async {
        await service.buy(productId);
        expect(backend.reservations, 1);
        expect(
          store.lastPurchase?.applicationUserName,
          backend.auth.currentUser!.id,
        );
      });

      test(
        'another sponsor reservation prevents opening Apple purchase sheet',
        () async {
          backend.reservationError = const PostgrestException(
            message: 'SPONSOR_PURCHASE_IN_PROGRESS',
          );
          await service.buy(productId);
          expect(store.lastPurchase, isNull);
          expect(service.error, contains('checkout is awaiting confirmation'));
        },
      );

      test('active sponsor disables purchase for other members', () async {
        backend.sponsorship = {
          'active': true,
          'is_sponsor': false,
          'sponsor_name': 'Ross',
        };
        await service.refreshSponsorship();
        expect(service.canSponsor, isFalse);
        expect(service.sponsorName, 'Ross');
        await service.buy(productId);
        expect(store.lastPurchase, isNull);
        expect(backend.reservations, 0);
        expect(service.purchasePending, isFalse);
        expect(service.error, contains('paid coverage ends'));
      });

      test('refresh replaces paid usage with free usage at expiry', () async {
        backend.sponsorship = {
          'active': true,
          'is_sponsor': false,
          'sponsor_name': 'Sponsor',
          'paid_until': '2026-09-29T10:51:56Z',
        };
        backend.usage = {
          'plan': 'everroot_family',
          'limits': {'storage_bytes': 10000000000},
          'usage': {'storage_bytes': 13000000},
        };
        await service.refreshSponsorship();
        expect(service.familyUsage?['plan'], 'everroot_family');
        expect(service.paidUntil, DateTime.utc(2026, 9, 29, 10, 51, 56));
        backend.sponsorship = {'active': false, 'is_sponsor': false};
        backend.usage = {
          'plan': 'free',
          'limits': {'storage_bytes': 500000000},
          'usage': {'storage_bytes': 13000000},
        };
        await service.refreshSponsorship();
        expect(service.familyUsage?['plan'], 'free');
        expect(service.sponsorName, isNull);
        expect(service.canSponsor, isTrue);
      });

      test('failed usage refresh never fabricates a free plan', () async {
        backend.usage = const PostgrestException(
          message: 'network unavailable',
        );
        await service.refreshSponsorship();
        expect(service.familyUsage, isNull);
        expect(service.billingRefreshing, isFalse);
      });

      test(
        'switching app accounts invalidates cached billing controls',
        () async {
          backend.sponsorship = {'active': true, 'is_sponsor': true};
          await service.refreshSponsorship();
          expect(service.canManageFamilyPlan, isTrue);
          backend.auth.currentUser = User(
            id: 'other-user',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '',
          );
          expect(service.canManageFamilyPlan, isFalse);
          expect(service.canSponsor, isFalse);
          expect(service.familyUsage, isNull);
        },
      );

      test('does not start an unbound purchase after sign-out', () async {
        backend.auth.currentUser = null;
        await service.buy(productId);
        expect(store.lastPurchase, isNull);
        expect(service.purchasePending, isFalse);
      });

      test(
        'retries an unavailable store without a storefront change',
        () async {
          store.available = false;
          await service.refreshProducts();
          expect(service.storeAvailable, isFalse);
          store.available = true;
          final before = store.queries;
          await service.refreshStorefront();
          expect(store.queries, before + 1);
          expect(service.error, isNull);
        },
      );

      test('retries an empty catalog without a storefront change', () async {
        store.empty = true;
        await service.refreshProducts();
        expect(service.products, isEmpty);
        store.empty = false;
        await service.refreshStorefront();
        expect(service.products, isNotEmpty);
        expect(service.error, isNull);
      });

      Future<void> purchase({bool waitForError = true}) async {
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

      test(
        'queues overlapping updates and clears a transient rejection only after verification',
        () async {
          final first = Completer<FunctionResponse>();
          backend.functions.result = first.future;
          await purchase(waitForError: false);
          await purchase(waitForError: false);
          expect(backend.functions.calls, 1);
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {'product_id': productId, 'status': 'active'},
            },
          );
          first.completeError(
            FunctionException(
              status: 400,
              details: {'error': 'Unsupported Apple subscription product'},
            ),
          );
          await pumpEventQueue();
          expect(backend.functions.calls, 2);
          expect(store.completed, 1);
          expect(service.error, isNull);
          expect(service.message, 'Family plan updated.');
          expect(service.purchasePending, false);
        },
      );

      test('unresolved product rejection still fails closed', () async {
        backend.functions.result = FunctionException(
          status: 400,
          details: {'error': 'Unsupported Apple subscription product'},
        );
        await purchase();
        expect(store.completed, 0);
        expect(service.rawError, 'APPLE_PRODUCT_MISMATCH (HTTP 400)');
        expect(service.error, contains('Restore purchases'));
      });

      test('verification never waits for a storefront lookup', () async {
        final stalled = Completer<String>();
        store.countryResponse = stalled.future;
        final before = store.countryLookups;
        verified();
        await purchase();
        expect(store.completed, 1);
        expect(store.countryLookups, before);
        stalled.complete('ZAF');
      });

      test(
        'restore finishes when verification finishes, without a fixed wait',
        () async {
          verified();
          store.onRestore = () async {
            store.updates.add([
              savedPurchase()..status = PurchaseStatus.restored,
            ]);
          };
          var finished = false;
          final restoring = service.restore().then((_) => finished = true);
          await pumpEventQueue();
          expect(finished, true);
          expect(service.purchasePending, false);
          expect(service.message, 'Family plan updated.');
          await restoring;
        },
      );

      test(
        'empty restore finishes promptly and checks expired history',
        () async {
          previous = savedPurchase()..pendingCompletePurchase = false;
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {'product_id': productId, 'status': 'expired'},
            },
          );
          var finished = false;
          final restoring = service.restore().then((_) => finished = true);
          await pumpEventQueue();
          expect(finished, true);
          expect(service.message, 'This subscription is no longer active.');
          expect(service.purchasePending, false);
          await restoring;
        },
      );

      test(
        'account mismatch is immediate, deduplicated and separate from pricing',
        () async {
          backend.functions.result = FunctionException(
            status: 400,
            details: {
              'code': 'APPLE_PURCHASE_ALREADY_BOUND',
              'environment': 'sandbox',
            },
          );
          await purchase();
          expect(service.purchasePending, false);
          expect(service.error, contains('Switching app logins'));
          expect(service.sandboxAccountMismatch, true);
          expect(service.hasPricingDiagnostics, false);
          expect(service.canSponsor, false);
          final before = store.queries;
          await purchase();
          expect(backend.functions.calls, 1);
          expect(store.completed, 0);
          expect(store.queries, before);
          await service.refreshProducts();
          expect(service.error, contains("original purchaser's app account"));
          expect(service.canSponsor, false);
        },
      );

      test('explicit restore rechecks a previous rejection', () async {
        unfinished.add(savedPurchase());
        backend.functions.result = FunctionException(
          status: 400,
          details: {
            'code': 'APPLE_PURCHASE_ALREADY_BOUND',
            'environment': 'sandbox',
          },
        );
        await service.restore();
        expect(service.canSponsor, false);
        verified();
        await service.restore();
        expect(backend.functions.calls, 2);
        expect(store.completed, 1);
        expect(service.error, isNull);
        expect(service.sandboxAccountMismatch, false);
      });

      test('sync clears stale history before unfinished recovery', () async {
        unfinished.add(savedPurchase());
        previous = savedPurchase();
        backend.functions.result = FunctionException(
          status: 400,
          details: {'code': 'APPLE_PURCHASE_ALREADY_BOUND'},
        );
        await service.buy(productId);
        expect(service.canSponsor, false);
        onSync = () async {
          unfinished.clear();
          previous = null;
          store.country = 'ZAF';
        };
        await service.restore();
        expect(syncCalls, 1);
        expect(backend.functions.calls, 1);
        expect(service.canSponsor, true);
        expect(service.error, isNull);
        expect(service.productFor(productId)!.currencyCode, 'ZAR');
        expect(store.lastPurchase, isNull);
        expect(store.completed, 0);
      });

      test(
        'failed sync does not clear ownership recovery or start checkout',
        () async {
          onSync = () async => throw PlatformException(code: 'SYNC_FAILED');
          await service.restore();
          expect(syncCalls, 1);
          expect(service.canSponsor, false);
          expect(service.purchasePending, false);
          expect(backend.functions.calls, 0);
          expect(store.lastPurchase, isNull);
        },
      );

      test('switching app accounts during sync discards its result', () async {
        onSync = () async {
          backend.auth.currentUser = null;
        };
        await service.restore();
        expect(backend.functions.calls, 0);
        expect(service.purchasePending, false);
        expect(service.canSponsor, false);
      });

      test('checkout does not prompt for an unsolicited Apple sync', () async {
        await service.buy(productId);
        expect(syncCalls, 0);
        expect(store.lastPurchase, isNotNull);
      });

      test(
        'foreground refresh reloads prices with a cached storefront',
        () async {
          final before = store.queries;
          await service.refreshStorefront();
          expect(store.queries, before + 1);
        },
      );

      test(
        'fresh Apple account clears the block only after empty history is checked',
        () async {
          unfinished.add(savedPurchase());
          backend.functions.result = FunctionException(
            status: 400,
            details: {
              'code': 'APPLE_PURCHASE_ALREADY_BOUND',
              'environment': 'sandbox',
            },
          );
          await service.restore();
          expect(service.canSponsor, false);
          unfinished.clear();
          await service.restore();
          expect(service.canSponsor, true);
          expect(service.purchasePending, false);
          expect(service.error, isNull);
          expect(service.message, contains('No previous App Store purchase'));
          expect(store.completed, 0);
          expect(backend.reservations, 0);
        },
      );

      test(
        'explicit restore revalidates an already completed transaction',
        () async {
          unfinished.add(savedPurchase());
          verified();
          await service.restore();
          unfinished.clear();
          previous = savedPurchase()..pendingCompletePurchase = false;
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'entitlement': {'product_id': productId, 'status': 'refunded'},
            },
          );
          await service.restore();
          expect(backend.functions.calls, 2);
          expect(service.message, 'This subscription is no longer active.');
          expect(store.completed, 1);
        },
      );

      test(
        'production mismatch does not display sandbox instructions',
        () async {
          backend.functions.result = FunctionException(
            status: 400,
            details: {
              'code': 'APPLE_PURCHASE_ALREADY_BOUND',
              'environment': 'production',
            },
          );
          await purchase();
          expect(service.error, contains("original purchaser's app account"));
          expect(service.sandboxAccountMismatch, false);
          expect(store.completed, 0);
        },
      );

      test(
        'missing restore callback fails closed within a bounded wait',
        () async {
          store.onRestore = () async {};
          await service.restore();
          expect(service.purchasePending, false);
          expect(service.canSponsor, false);
          expect(service.error, contains('Could not restore'));
          expect(service.message, isNull);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );

      test(
        'account mismatch stays unfinished and explains original account',
        () async {
          backend.functions.result = FunctionException(
            status: 403,
            details: {'code': 'APPLE_PURCHASER_MISMATCH'},
          );
          await purchase();
          expect(store.completed, 0);
          expect(service.error, contains("original purchaser's app account"));
          expect(service.rawError, 'APPLE_PURCHASER_MISMATCH (HTTP 403)');
        },
      );

      test(
        'ignores unrelated StoreKit products without completing them',
        () async {
          productId = 'unrelated.product';
          await purchase(waitForError: false);
          expect(backend.functions.calls, 0);
          expect(store.completed, 0);
        },
      );

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
