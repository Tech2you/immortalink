import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/services/apple_subscription_config.dart';
import 'package:immortalink/services/apple_subscription_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apple_subscription_service_test.dart' show FakeStore, FakeSupabase;

void main() {
  late FakeSupabase backend;
  late FakeStore store;
  late AppleSubscriptionService service;
  setUp(() {
    backend = FakeSupabase();
    store = FakeStore();
    service = AppleSubscriptionService(supabase: backend, iap: store);
  });
  tearDown(() async {
    service.dispose();
    await store.updates.close();
  });

  void paid({required bool isSponsor, DateTime? until}) {
    backend.sponsorship = {
      'active': true,
      'is_sponsor': isSponsor,
      'sponsor_name': 'Linebreakers',
      'paid_until': (until ?? DateTime.now().add(const Duration(hours: 1)))
          .toIso8601String(),
    };
    backend.usage = {
      'plan': 'everroot_family',
      'limits': {'storage_bytes': 10 * 1024 * 1024 * 1024},
      'usage': {'storage_bytes': 13000000},
    };
  }

  Future<void> show(
    WidgetTester tester, {
    double scale = 1,
    String familyId = 'family',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: AlertDialog(
            title: const Text('Family plan'),
            content: FamilyPlanStatusContent(
              familyId: familyId,
              service: service,
            ),
            actions: [TextButton(onPressed: () {}, child: const Text('Close'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<MethodCall> recordAppleManagement(
    WidgetTester tester, {
    Completer<void>? completion,
  }) {
    const channel = MethodChannel('com.everroots.app/subscriptions');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (completion != null) await completion.future;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    return calls;
  }

  Future<void> tapAppleManagement(WidgetTester tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final button = find.text('Manage Apple subscriptions');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  }

  testWidgets('member sees Apple account access, never family management', (
    tester,
  ) async {
    paid(isSponsor: false);
    await show(tester);
    expect(find.text('Current plan: Heiro Family'), findsOneWidget);
    expect(find.text('Sponsored by Linebreakers'), findsOneWidget);
    expect(find.textContaining('Paid coverage until'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Manage Apple subscriptions'), findsOneWidget);
    expect(find.text('Change or cancel plan'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('plan and storage refresh together without reopening', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Current plan: Free Family'), findsOneWidget);
    paid(isSponsor: true);
    await service.refreshSponsorship();
    await tester.pumpAndSettle();
    expect(find.text('Current plan: Heiro Family'), findsOneWidget);
    expect(find.textContaining('10.0 GB used'), findsOneWidget);
    expect(find.text('Change or cancel plan'), findsOneWidget);
    expect(find.text('Manage Apple subscriptions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scenario in [
    'free recreated account',
    'covered non-sponsor',
    'unavailable coverage',
    'no family',
    'unavailable store',
  ]) {
    testWidgets('$scenario can open Apple without claiming a subscription', (
      tester,
    ) async {
      final calls = recordAppleManagement(tester);
      backend.auth.currentUser = User(
        id: '00000000-0000-4000-8000-000000000002',
        email: 'recreated@example.com',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      );
      if (scenario == 'covered non-sponsor') paid(isSponsor: false);
      if (scenario == 'unavailable coverage') backend.usage = null;
      if (scenario == 'unavailable store') store.available = false;
      await show(tester, familyId: scenario == 'no family' ? '' : 'family');
      final usage = service.familyUsage;
      final canSponsor = service.canSponsor;
      expect(service.canManageFamilyPlan, isFalse);
      expect(find.text('Change or cancel plan'), findsNothing);

      await tapAppleManagement(tester);

      expect(calls.map((call) => call.method), ['manageSubscriptions']);
      expect(calls.single.arguments, isNull);
      expect(service.familyUsage, usage);
      expect(service.canSponsor, canSponsor);
      expect(service.canManageFamilyPlan, isFalse);
      expect(backend.auth.currentUser!.id.endsWith('0002'), isTrue);
      expect(backend.functions.calls, 0);
      expect(backend.reservations, 0);
      expect(backend.releases, 0);
      expect(store.lastPurchase, isNull);
      expect(store.completed, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Apple management prevents duplicate sheets and permits retry', (
    tester,
  ) async {
    final completion = Completer<void>();
    final calls = recordAppleManagement(tester, completion: completion);
    await show(tester);
    await tapAppleManagement(tester);
    final button = find.widgetWithText(
      TextButton,
      'Manage Apple subscriptions',
    );
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    await tester.tap(button);
    await tester.pump();
    expect(calls, hasLength(1));
    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(service.message ?? '', isNot(contains('cancelled')));
    expect(service.message ?? '', isNot(contains('restored')));
    await tapAppleManagement(tester);
    expect(calls, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'expiry automatically refreshes free allowance and removes sponsor label',
    (tester) async {
      paid(
        isSponsor: false,
        until: DateTime.now().add(const Duration(seconds: 2)),
      );
      await show(tester);
      backend.sponsorship = {'active': false, 'is_sponsor': false};
      backend.usage = {
        'plan': 'free',
        'limits': {'storage_bytes': 500000000},
        'usage': {'storage_bytes': 13000000},
      };
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Current plan: Free Family'), findsOneWidget);
      expect(find.text('Sponsored by Linebreakers'), findsNothing);
      expect(service.canSponsor, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unknown usage does not mark Free as current', (tester) async {
    backend.usage = null;
    await show(tester);
    expect(find.text('Current'), findsNothing);
    expect(
      find.textContaining('Could not refresh the family plan'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restore and refresh appear after the last plan', (tester) async {
    await show(tester);
    final lastPlan = find.text('50 GB shared storage');
    final restore = find.text('Restore purchases');
    final refresh = find.byTooltip('Refresh plan and prices');
    expect(refresh, findsOneWidget);
    expect(find.byTooltip('Refresh plan'), findsNothing);
    expect(
      tester.getTopLeft(restore).dy,
      greaterThan(tester.getBottomLeft(lastPlan).dy),
    );
    expect(
      tester.getTopLeft(refresh).dy,
      greaterThan(tester.getBottomLeft(lastPlan).dy),
    );
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    expect(refresh.hitTestable(), findsOneWidget);
    expect(restore.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  final purchasesEnabled =
      AppleSubscriptionConfig.purchaseFlowEnabled &&
      AppleSubscriptionConfig.activeProductIds.isNotEmpty;

  testWidgets('footer refresh reloads both allowance and prices', (
    tester,
  ) async {
    await show(tester);
    final oldQueries = store.queries;
    paid(isSponsor: false);
    store.country = 'ZAF';
    final refresh = find.byTooltip('Refresh plan and prices');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text('Current plan: Heiro Family'), findsOneWidget);
    expect(find.textContaining('10.0 GB used'), findsOneWidget);
    expect(store.queries, oldQueries + 1);
    expect(find.text('R119.99 / month'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !purchasesEnabled);

  Future<void> rejectRestore(
    WidgetTester tester, {
    String code = 'APPLE_PURCHASE_ALREADY_BOUND',
  }) async {
    backend.functions.result = FunctionException(
      status: 400,
      details: {'code': code, 'environment': 'sandbox'},
    );
    await tester.runAsync(() async {
      store.updates.add([
        PurchaseDetails(
          purchaseID: 'another-account-transaction',
          productID: AppleSubscriptionConfig.activeProductIds.first,
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: '',
            source: 'app_store',
          ),
          transactionDate: '1',
          status: PurchaseStatus.restored,
        )..pendingCompletePurchase = true,
      ]);
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(backend.functions.calls, 1);
  }

  for (final code in [
    'APPLE_PURCHASE_ALREADY_BOUND',
    'APPLE_PURCHASER_MISMATCH',
  ]) {
    testWidgets(
      'covered member gets a neutral $code without bypassing ownership',
      (tester) async {
        paid(isSponsor: false);
        await show(tester);
        await rejectRestore(tester, code: code);
        final notice = find.textContaining(
          'Your family plan is already available',
        );
        expect(notice, findsOneWidget);
        expect(
          tester.widget<Text>(notice).style?.color,
          Theme.of(tester.element(notice)).colorScheme.onSurfaceVariant,
        );
        expect(find.textContaining('For sandbox testing'), findsNothing);
        expect(find.text('Restore purchases'), findsOneWidget);
        expect(find.text('Manage Apple subscriptions'), findsOneWidget);
        expect(find.text('Change or cancel plan'), findsNothing);
        expect(service.purchaseAccountMismatch, true);
        expect(service.canSponsor, false);
        expect(store.completed, 0);
        expect(backend.reservations, 0);
        expect(find.textContaining('10.0 GB used'), findsOneWidget);
        final calls = recordAppleManagement(tester);
        await tapAppleManagement(tester);
        expect(calls.map((call) => call.method), ['manageSubscriptions']);
        expect(backend.functions.calls, 1);
        expect(service.purchaseAccountMismatch, isTrue);
        expect(service.canSponsor, isFalse);
        expect(service.canManageFamilyPlan, isFalse);
        await service.buy(AppleSubscriptionConfig.activeProductIds.first);
        expect(store.lastPurchase, isNull);

        backend.sponsorship = {'active': false, 'is_sponsor': false};
        backend.usage = {
          'plan': 'free',
          'limits': {'storage_bytes': 500000000},
          'usage': {'storage_bytes': 13000000},
        };
        await service.refreshSponsorship();
        await tester.pumpAndSettle();
        expect(notice, findsNothing);
        final error = find.textContaining("original purchaser's app account");
        expect(error, findsOneWidget);
        expect(
          tester.widget<Text>(error).style?.color,
          Theme.of(tester.element(error)).colorScheme.error,
        );
        expect(service.canSponsor, false);
        expect(store.completed, 0);
        await tester.pumpWidget(const SizedBox());
      },
      skip: !purchasesEnabled,
    );
  }

  testWidgets('purchaser mismatch remains an actionable error', (tester) async {
    paid(isSponsor: true);
    await show(tester);
    await rejectRestore(tester);
    expect(
      find.textContaining('Your family plan is already available'),
      findsNothing,
    );
    final error = find.textContaining("original purchaser's app account");
    expect(error, findsOneWidget);
    expect(
      tester.widget<Text>(error).style?.color,
      Theme.of(tester.element(error)).colorScheme.error,
    );
    expect(service.canSponsor, false);
    expect(store.completed, 0);
    await tester.pumpWidget(const SizedBox());
  }, skip: !purchasesEnabled);

  testWidgets('unknown coverage never softens a purchase mismatch', (
    tester,
  ) async {
    paid(isSponsor: false);
    backend.usage = null;
    await show(tester);
    await rejectRestore(tester);
    expect(
      find.textContaining('Your family plan is already available'),
      findsNothing,
    );
    final error = find.textContaining("original purchaser's app account");
    expect(error, findsOneWidget);
    expect(
      tester.widget<Text>(error).style?.color,
      Theme.of(tester.element(error)).colorScheme.error,
    );
    expect(service.canSponsor, false);
    expect(store.completed, 0);
    await tester.pumpWidget(const SizedBox());
  }, skip: !purchasesEnabled);

  testWidgets(
    'unconfirmed purchase is not softened just because family is covered',
    (tester) async {
      paid(isSponsor: false);
      await show(tester);
      await rejectRestore(tester, code: 'APPLE_VALIDATION_FAILED');
      expect(service.purchaseAccountMismatch, false);
      final error = find.textContaining(
        'Your Apple purchase is awaiting confirmation',
      );
      expect(error, findsOneWidget);
      expect(
        tester.widget<Text>(error).style?.color,
        Theme.of(tester.element(error)).colorScheme.error,
      );
      expect(service.canSponsor, false);
      expect(store.completed, 0);
      final calls = recordAppleManagement(tester);
      await tapAppleManagement(tester);
      expect(calls.map((call) => call.method), ['manageSubscriptions']);
      expect(backend.functions.calls, 1);
      expect(backend.reservations, 0);
      expect(service.canSponsor, isFalse);
      expect(error, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !purchasesEnabled,
  );

  testWidgets('large text fits the phone dialog and plan buttons', (
    tester,
  ) async {
    paid(isSponsor: false);
    await show(tester, scale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('Restore purchases').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Manage Apple subscriptions'));
    await tester.pumpAndSettle();
    expect(
      find.text('Manage Apple subscriptions').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('management guard rejects non-purchaser without opening Apple', (
    tester,
  ) async {
    const channel = MethodChannel('com.everroots.app/subscriptions');
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      calls++;
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      paid(isSponsor: false);
      await service.initialize(familyId: 'family');
      await service.openFamilyPlanManagement();
      expect(calls, 0);
      expect(service.error, contains("original purchaser's app account"));
      paid(isSponsor: true);
      await service.openFamilyPlanManagement();
      expect(calls, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });
}
