import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/services/apple_subscription_service.dart';
import 'package:immortalink/services/apple_subscription_config.dart';
import 'package:immortalink/widgets/contribution_move_card.dart';
import 'apple_subscription_service_test.dart' show FakeSupabase, FakeStore;

void main() {
  late FakeSupabase backend;
  late FakeStore store;
  late AppleSubscriptionService service;
  final details = {
    'confirmation_id': '00000000-0000-4000-8000-000000000099',
    'paid_until': '2026-12-01T00:00:00Z',
    'storage_bytes': 5 * 1024 * 1024 * 1024,
    'ai_remaining': 300,
    'transcription_seconds_remaining': 5400,
    'previous_family_exists': true,
  };
  setUp(() async {
    backend = FakeSupabase();
    store = FakeStore();
    backend.sponsorship = {
      'bucket_model': true,
      'can_move_contribution': true,
      'active': false,
      'is_sponsor': false,
    };
    backend.functions.result = FunctionResponse(
      status: 200,
      data: {'ok': true, 'move': details},
    );
    service = AppleSubscriptionService(supabase: backend, iap: store);
    await service.initialize(familyId: 'new-family');
  });
  tearDown(() async {
    service.dispose();
    await store.updates.close();
  });
  group(
    'verified contribution move',
    () {
      test(
        'preview never purchases; confirmation requires the exact reviewed quote',
        () async {
          expect(service.canMoveContribution, true);
          expect(service.canSponsor, false);
          final preview = await service.previewContributionMove();
          expect(preview?.aiRemaining, 300);
          expect(store.lastPurchase, isNull);
          expect(backend.reservations, 0);
          expect(
            await service.confirmContributionMove(
              ContributionMovePreview(details),
            ),
            false,
          );
          backend.sponsorship['can_move_contribution'] = false;
          backend.functions.result = FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'move': {'moved': true},
            },
          );
          expect(await service.confirmContributionMove(preview!), true);
          expect(
            (backend.functions.lastBody as Map)['purpose'],
            'confirm_move',
          );
          expect(service.canMoveContribution, false);
          expect(service.message, contains('No new payment'));
          expect(store.lastPurchase, isNull);
          expect(backend.reservations, 0);
        },
      );
      test(
        'account/family changes discard the pending preview and confirmation',
        () async {
          final preview = await service.previewContributionMove();
          await service.initialize(familyId: 'another-family');
          expect(await service.confirmContributionMove(preview!), false);
          final response = Completer<FunctionResponse>();
          backend.functions.result = response.future;
          final pending = service.previewContributionMove();
          await Future<void>.delayed(Duration.zero);
          backend.auth.currentUser = null;
          response.complete(
            FunctionResponse(status: 200, data: {'ok': true, 'move': details}),
          );
          expect(await pending, isNull);
          expect(service.canMoveContribution, false);
          expect(service.purchasePending, false);
        },
      );
      test(
        'stale details and Apple failures keep the grant unchanged and offer review again',
        () async {
          final preview = await service.previewContributionMove();
          backend.functions.result = FunctionException(
            status: 409,
            details: {'code': 'APPLE_MOVE_STALE'},
          );
          expect(await service.confirmContributionMove(preview!), false);
          expect(service.moveError, contains('changed'));
          expect(store.lastPurchase, isNull);
          expect(service.canMoveContribution, true);
        },
      );
      test('double tapping cannot send a second move request', () async {
        final preview = await service.previewContributionMove();
        final pendingResponse = Completer<FunctionResponse>();
        backend.functions.result = pendingResponse.future;
        final first = service.confirmContributionMove(preview!);
        final calls = backend.functions.calls;
        expect(await service.confirmContributionMove(preview), false);
        pendingResponse.complete(
          FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'move': {'moved': true},
            },
          ),
        );
        expect(await first, true);
        expect(backend.functions.calls, calls + 1);
        expect(store.lastPurchase, isNull);
      });
      testWidgets(
        'readable confirmation on narrow screen with large text; cancelling does not move',
        (tester) async {
          service.dispose();
          service = AppleSubscriptionService(supabase: backend, iap: store);
          await service.initialize(familyId: 'new-family');
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.7)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ContributionMoveCard(service: service),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Move my contribution'));
          await tester.pumpAndSettle();
          expect(service.moveError, isNull);
          expect(backend.functions.calls, 1);
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Move your contribution here?'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(find.textContaining('previous family loses'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(
            (backend.functions.lastBody as Map)['purpose'],
            'preview_move',
          );
          expect(store.lastPurchase, isNull);
        },
      );
    },
    skip: !AppleSubscriptionConfig.purchaseFlowEnabled,
  );
}
