import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/services/apple_subscription_service.dart';
import 'package:immortalink/services/apple_subscription_config.dart';
import 'package:immortalink/widgets/family_storage_bucket_summary.dart';
import 'package:immortalink/widgets/heiro_surface.dart';
import 'apple_subscription_service_test.dart' show FakeSupabase, FakeStore;

void main() {
  setUpAll(() async {
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isEmpty) return;
    final data = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('BUCKET_UI_QA')) return;
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/immortalink_logo.png'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/billing-40-qa/$name.png'),
    );
  }

  const gb = 1073741824;
  late FakeSupabase db;
  late FakeStore store;
  late AppleSubscriptionService service;
  setUp(() {
    db = FakeSupabase();
    store = FakeStore();
    db.sponsorship = {
      'bucket_model': true,
      'active': true,
      'is_sponsor': false,
      'own_plan': null,
      'contributor_count': 2,
      'contributors': [
        {'name': 'Alex', 'is_you': false, 'storage_bytes': 5 * gb},
        {'name': 'Blair', 'is_you': false, 'storage_bytes': 25 * gb},
      ],
    };
    db.usage = {
      'plan': 'everroot_legacy',
      'limits': {
        'storage_bytes': 30 * gb,
        'ai_responses_monthly': 2000,
        'transcription_seconds_monthly': 31200,
      },
      'usage': {
        'storage_bytes': 10000000,
        'ai_responses_monthly': 17,
        'transcription_seconds_monthly': 120,
      },
    };
    service = AppleSubscriptionService(supabase: db, iap: store);
  });
  tearDown(() async {
    service.dispose();
    await store.updates.close();
  });
  Future<void> show(
    WidgetTester tester, {
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: HeiroSurface(
          child: Scaffold(
            appBar: AppBar(title: const Text('Family storage')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: FamilyPlanStatusContent(
                familyId: 'family',
                service: service,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets(
    'cold loading never flashes the old free plan or purchase layout',
    (tester) async {
      final billing = Completer<Map<String, dynamic>>();
      final usage = Completer<Map<String, dynamic>>();
      final savedUsage = Map<String, dynamic>.from(db.usage as Map);
      db.sponsorshipResponse = billing.future;
      db.usage = usage.future;
      await show(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Free Family'), findsNothing);
      expect(find.text('+5 GB for your family'), findsNothing);
      expect(find.text('Checking your family plan...'), findsOneWidget);
      await capture(tester, 'loading');
      if (AppleSubscriptionConfig.purchaseFlowEnabled) expect(store.queries, 1);
      billing.complete(db.sponsorship);
      await tester.pump();
      expect(find.text('Free Family'), findsNothing);
      usage.complete(savedUsage);
      await tester.pumpAndSettle();
      expect(find.text('30 GB'), findsOneWidget);
      expect(find.text('Free Family'), findsNothing);
      await capture(tester, 'storage');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('refresh failure keeps the bucket layout and marks data stale', (
    tester,
  ) async {
    await show(tester);
    db.sponsorshipResponse = Exception('offline');
    db.usage = Exception('offline');
    await service.refreshSponsorship();
    await tester.pump();
    expect(find.text('30 GB'), findsOneWidget);
    expect(find.text('Free Family'), findsNothing);
    expect(find.textContaining('last known usage'), findsOneWidget);
    expect(service.canSponsor, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'both plans use equal-width vertically stacked price buttons',
    (tester) async {
      await show(tester, scale: 1.4);
      final monthly = find.widgetWithText(OutlinedButton, '\$5.99 / month');
      final annual = find.widgetWithText(FilledButton, '\$5.99 / year');
      expect(monthly, findsNWidgets(2));
      expect(annual, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final m = tester.getRect(monthly.at(i));
        final a = tester.getRect(annual.at(i));
        expect(a.left, m.left);
        expect(a.width, m.width);
        expect(a.top, greaterThan(m.bottom));
        expect(m.height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(
          find.text(i == 0 ? 'Heiro Family' : 'Heiro Legacy'),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'prices-$i-large-text');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !AppleSubscriptionConfig.purchaseFlowEnabled,
  );

  test('capacity keeps free MB and clean whole paid GB', () {
    expect(formatFamilyCapacity(524288000), '500 MB');
    expect(formatFamilyCapacity(5 * gb), '5 GB');
    expect(formatFamilyCapacity(30 * gb), '30 GB');
  });
  testWidgets(
    'nonpaying member can contribute despite another active family plan',
    (tester) async {
      await show(tester);
      expect(service.canSponsor, isTrue);
      expect(service.canManageFamilyPlan, isFalse);
      expect(find.text('30 GB'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.textContaining('17 of 2000'), findsOneWidget);
      expect(find.textContaining('2 of 520'), findsOneWidget);
      expect(find.text('Your plan'), findsNothing);
      expect(find.text('Sponsored by'), findsNothing);
      expect(find.text('+5 GB for your family'), findsOneWidget);
      expect(find.text('+25 GB for your family'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'own plan is not confused with highest family plan, large text fits',
    (tester) async {
      db.sponsorship.addAll({
        'is_sponsor': true,
        'own_plan': 'everroot_family',
      });
      await show(tester, scale: 1.6);
      expect(find.text('Your plan'), findsOneWidget);
      expect(service.ownPlan, 'everroot_family');
      expect(find.text('Manage your contribution'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'member uses new checkout and account switch clears own contribution',
    () async {
      await service.initialize(familyId: 'family');
      await service.buy('everroots.family.monthly');
      expect(db.lastCheckout, 'begin_family_storage_contribution');
      expect(db.reservations, 1);
      db.auth.currentUser = null;
      await service.refreshSponsorship();
      expect(service.canSponsor, isFalse);
      expect(service.contributors, isEmpty);
      expect(service.ownPlan, isNull);
    },
    skip: !AppleSubscriptionConfig.purchaseFlowEnabled,
  );
  test(
    'existing payer is directed to management without a second checkout',
    () async {
      db.sponsorship.addAll({
        'is_sponsor': true,
        'own_plan': 'everroot_family',
      });
      await service.initialize(familyId: 'family');
      await service.buy('everroots.legacy.monthly');
      expect(db.reservations, 0);
      expect(service.message, contains('Manage your contribution'));
    },
    skip: !AppleSubscriptionConfig.purchaseFlowEnabled,
  );
}
