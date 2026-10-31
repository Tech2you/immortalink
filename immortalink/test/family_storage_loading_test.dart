import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/services/apple_subscription_service.dart';
import 'package:immortalink/widgets/brand_loading.dart';
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
  Future<void> show(
    WidgetTester tester,
    Future<String?> Function() loader, {
    String hint = '',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Family storage')),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: FamilyPlanStatusContent(
              familyId: hint,
              loadFamilyId: loader,
              service: service,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'first open waits for membership and loads the plan without reopening',
    (tester) async {
      final family = Completer<String?>();
      await show(tester, () => family.future);
      expect(find.text('Loading your family...'), findsOneWidget);
      expect(find.byType(BrandLoading), findsOneWidget);
      expect(find.textContaining('Join or create'), findsNothing);
      expect(backend.sponsorshipReads, 0);
      expect(store.queries, 0);
      family.complete('current-family');
      await tester.pumpAndSettle();
      expect(find.text('Current plan: Free Family'), findsOneWidget);
      expect(find.textContaining('Join or create'), findsNothing);
      expect(backend.sponsorshipReads, 1);
      expect(backend.reservations, 0);
      expect(store.lastPurchase, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'one brief read failure recovers automatically without a false empty state',
    (tester) async {
      var calls = 0;
      await show(tester, () async {
        if (calls++ == 0) throw StateError('offline');
        return 'family';
      });
      expect(find.textContaining('Join or create'), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Current plan: Free Family'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'membership recovery exposes an existing contribution on first open',
    (tester) async {
      backend.sponsorship = {
        'bucket_model': true,
        'can_move_contribution': true,
        'active': false,
        'is_sponsor': false,
      };
      await show(tester, () async => 'current-family');
      await tester.pumpAndSettle();
      expect(find.text('Move my contribution'), findsOneWidget);
      expect(backend.sponsorshipReads, 1);
      expect(backend.reservations, 0);
      expect(backend.functions.calls, 0);
      expect(store.lastPurchase, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a stalled lookup times out with a bounded retry', (
    tester,
  ) async {
    var calls = 0;
    final stalled = Completer<String?>();
    await show(tester, () {
      calls++;
      return stalled.future;
    });
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(calls, 2);
    expect(find.textContaining('Could not load your family'), findsOneWidget);
    expect(find.textContaining('Join or create'), findsNothing);
    stalled.complete('late-family');
    await tester.pump();
    expect(backend.sponsorshipReads, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'persistent failure is a retryable error, not missing membership',
    (tester) async {
      var failed = true;
      var calls = 0;
      await show(tester, () async {
        calls++;
        if (failed) throw StateError('offline');
        return 'family';
      });
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('Could not load your family'), findsOneWidget);
      expect(find.textContaining('Join or create'), findsNothing);
      expect(backend.sponsorshipReads, 0);
      expect(find.text('Manage Apple subscriptions'), findsOneWidget);
      failed = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Current plan: Free Family'), findsOneWidget);
      expect(calls, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('confirmed no family can be checked again after joining', (
    tester,
  ) async {
    String? family;
    await show(tester, () async => family);
    await tester.pumpAndSettle();
    expect(find.textContaining('Join or create'), findsOneWidget);
    expect(backend.sponsorshipReads, 0);
    family = 'joined';
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Current plan: Free Family'), findsOneWidget);
    expect(backend.sponsorshipReads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('leaving the page during lookup never initializes billing', (
    tester,
  ) async {
    final family = Completer<String?>();
    await show(tester, () => family.future);
    await tester.pumpWidget(const SizedBox());
    family.complete('family');
    await tester.pump();
    expect(backend.sponsorshipReads, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('an older family lookup cannot replace a newer selection', (
    tester,
  ) async {
    final old = Completer<String?>();
    await show(tester, () => old.future, hint: 'old');
    await show(tester, () async => 'new', hint: 'new');
    await tester.pumpAndSettle();
    expect(backend.sponsorshipReads, 1);
    old.complete('old');
    await tester.pumpAndSettle();
    expect(backend.sponsorshipReads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
