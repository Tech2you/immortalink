import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/content_sharing_service.dart';
import 'package:immortalink/widgets/content_screening_permission.dart';
import 'package:immortalink/widgets/memory_sharing_status.dart';

import 'apple_subscription_service_test.dart' show FakeSupabase, FakeRpc;
import 'content_screening_permission_test.dart' show otherUser, state;

const target = '00000000-0000-4000-8000-000000000010';
Map<String, Object> sharing(String name, [bool request = false]) => {
  'state': name,
  'can_request': request,
};

class SharingBackend extends FakeSupabase {
  Object? statusResult = sharing('ready', true);
  Object? requestResult = {'code': 'QUEUED', 'state': 'queued'};
  Object? permission = state();
  Object? onRequestStatus = sharing('queued');
  final calls = <String>[];
  final parameters = <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #rpc) {
      final name = invocation.positionalArguments.first as String;
      calls.add(name);
      final params =
          invocation.namedArguments[#params] as Map<String, dynamic>? ?? {};
      parameters.add(params);
      switch (name) {
        case 'get_content_sharing_status':
          return FakeRpc(statusResult);
        case 'get_content_screening_permission':
          return FakeRpc(permission);
        case 'set_content_screening_permission':
          permission = state(
            allowed: params['p_allowed'] as bool,
            revision: '2',
          );
          return FakeRpc(permission);
        case 'request_content_screening':
          statusResult = onRequestStatus;
          return FakeRpc(requestResult);
      }
      throw StateError('Unexpected RPC $name');
    }
    return super.noSuchMethod(invocation);
  }
}

ContentSharingService service(SharingBackend backend, {bool enabled = true}) =>
    ContentSharingService(
      client: backend,
      expectedUserId: backend.auth.currentUser!.id,
      enabled: enabled,
    );

Future<void> open(
  WidgetTester tester,
  SharingBackend backend, {
  bool initial = false,
  bool enabled = true,
  String kind = 'memory',
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMemorySharingStatus(
              context,
              kind: kind,
              targetId: target,
              client: backend,
              requestAfterSave: initial,
              enabled: enabled,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment('SCREENING_TEST_FONT');
    if (fontPath.isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(fontPath).readAsBytes()),
          ),
        );
      await loader.load();
    }
    const iconPath = String.fromEnvironment('SCREENING_TEST_ICONS');
    if (iconPath.isNotEmpty) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(iconPath).readAsBytes()),
          ),
        );
      await loader.load();
    }
  });
  test('disabled service does not resolve client data or call RPCs', () async {
    final backend = SharingBackend();
    final disabled = service(backend, enabled: contentScreeningControlsEnabled);
    backend.auth.currentUser = null;
    expect(
      (await disabled.status('memory', target)).state,
      ContentSharingState.disabled,
    );
    expect(
      (await disabled.request('memory', target)).state,
      ContentSharingState.disabled,
    );
    expect(backend.calls, isEmpty);
    expect(backend.functions.calls, 0);
  });

  for (final malformed in <Object?>[
    null,
    true,
    {},
    {'state': 'shared', 'can_request': 'true'},
    sharing('future'),
    sharing('shared', true),
    sharing('held', true),
  ]) {
    test('malformed status cannot claim publication: $malformed', () {
      expect(
        () => ContentSharingStatus.parse(malformed),
        throwsFormatException,
      );
    });
  }

  test(
    'request acknowledgement is not shared; status is re-read and account-bound',
    () async {
      final backend = SharingBackend();
      final result = await service(backend).request('memory', target);
      expect(result.state, ContentSharingState.queued);
      expect(backend.calls, [
        'request_content_screening',
        'get_content_sharing_status',
      ]);
      for (final params in backend.parameters) {
        expect(params, {
          'p_kind': 'memory',
          'p_target': target,
          'p_expected_user_id': backend.auth.currentUser!.id,
        });
      }
    },
  );

  test('queue capacity offers retry, not re-upload or false success', () async {
    final backend = SharingBackend()..requestResult = {'code': 'QUEUE_LIMIT'};
    final result = await service(backend).request('memory', target);
    expect(result.state, ContentSharingState.limited);
    expect(result.canRequest, true);
    expect(backend.calls, ['request_content_screening']);
  });

  test('account switch before call makes no request', () async {
    final backend = SharingBackend();
    final bound = service(backend);
    backend.auth.currentUser = otherUser();
    await expectLater(bound.request('memory', target), throwsStateError);
    expect(backend.calls, isEmpty);
  });

  test(
    'account switch during request rejects completion and does not read new session',
    () async {
      final pending = Completer<Object?>();
      final backend = SharingBackend()..requestResult = pending.future;
      final future = service(backend).request('memory', target);
      backend.auth.currentUser = otherUser();
      pending.complete({'code': 'QUEUED'});
      await expectLater(future, throwsStateError);
      expect(backend.calls, ['request_content_screening']);
    },
  );

  testWidgets('disabled UI has no new dialog or side effects', (tester) async {
    final backend = SharingBackend();
    await open(
      tester,
      backend,
      enabled: contentScreeningControlsEnabled,
      initial: true,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(backend.calls, isEmpty);
  });

  for (final kind in ['memory', 'legacy_memory']) {
    testWidgets(
      '$kind saved flow asks separate consent and queues only after acceptance',
      (tester) async {
        final backend = SharingBackend();
        await open(tester, backend, initial: true, kind: kind);
        await tester.pumpAndSettle();
        expect(find.text('Sharing safety'), findsOneWidget);
        expect(backend.calls, [
          'get_content_sharing_status',
          'get_content_screening_permission',
        ]);
        await tester.tap(find.text('Allow safety checks'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Waiting for safety checks'),
          findsOneWidget,
        );
        expect(backend.calls, [
          'get_content_sharing_status',
          'get_content_screening_permission',
          'set_content_screening_permission',
          'request_content_screening',
          'get_content_sharing_status',
        ]);
        expect(backend.parameters[3]['p_kind'], kind);
        expect(backend.functions.calls, 0);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      },
    );
  }

  for (final choice in ['Decline', 'Close']) {
    testWidgets(
      '$choice preserves saved source without enqueueing or falsely claiming shared',
      (tester) async {
        final backend = SharingBackend();
        await open(tester, backend, initial: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        expect(
          find.text('Saved. No new sharing request was sent.'),
          findsOneWidget,
        );
        expect(backend.calls, isNot(contains('request_content_screening')));
        expect(find.text('Request sharing'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      },
    );
  }

  for (final stateName in [
    'held',
    'unsupported',
    'archive',
    'shared',
    'paused',
    'not_requested',
  ]) {
    testWidgets('$stateName cannot auto-prompt consent or queue another copy', (
      tester,
    ) async {
      final backend = SharingBackend()..statusResult = sharing(stateName);
      await open(tester, backend, initial: true);
      await tester.pumpAndSettle();
      expect(backend.calls, ['get_content_sharing_status']);
      expect(find.text('Request sharing'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'request failure can refresh same target without duplicate writes',
    (tester) async {
      final backend = SharingBackend()
        ..permission = state(allowed: true, revision: '1')
        ..requestResult = Exception('offline');
      await open(tester, backend, initial: true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not confirm sharing'), findsOneWidget);
      expect(
        backend.calls.where((c) => c == 'request_content_screening').length,
        1,
      );
      backend.statusResult = sharing('queued');
      await tester.tap(find.byTooltip('Refresh sharing status'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Waiting for safety checks'), findsOneWidget);
      expect(
        backend.calls.where((c) => c == 'request_content_screening').length,
        1,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'account changes during permission prompt cannot queue under another login',
    (tester) async {
      final backend = SharingBackend();
      await open(tester, backend, initial: true);
      await tester.pumpAndSettle();
      backend.auth.currentUser = otherUser();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your account changed'), findsOneWidget);
      expect(backend.calls, isNot(contains('request_content_screening')));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'slow request locks buttons; timeout allows status recovery, not another save',
    (tester) async {
      final pending = Completer<Object?>();
      final backend = SharingBackend()
        ..permission = state(allowed: true, revision: '1')
        ..requestResult = pending.future;
      await open(tester, backend, initial: true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Done'))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not confirm sharing'), findsOneWidget);
      pending.complete({'code': 'QUEUED'});
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not confirm sharing'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1024, 768),
  ]) {
    testWidgets('sharing controls fit $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, SharingBackend(), scale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(dialog.right, lessThanOrEqualTo(size.width));
      expect(dialog.bottom, lessThanOrEqualTo(size.height));
      if (const bool.fromEnvironment('CAPTURE_SHARING_STATUS')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '/private/tmp/heiro-sharing-${size.width.toInt()}.png',
          ),
        );
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
  }

  test(
    'production callers retain off switch and create requests only after attachment saves',
    () {
      final composer = File(
        'lib/screens/create_memory_screen.dart',
      ).readAsStringSync();
      expect(
        composer,
        contains('_shareToFamilyFeed && !contentScreeningControlsEnabled'),
      );
      expect(
        composer.indexOf('await _uploadVoice(userId, memoryId)'),
        lessThan(composer.indexOf('await showMemorySharingStatus(')),
      );
      for (final name in [
        'vault_home_screen.dart',
        'legacy_vault_screen.dart',
      ]) {
        final screen = File('lib/screens/$name').readAsStringSync();
        expect(screen, contains('contentScreeningControlsEnabled'));
        expect(screen, contains("Text('Sharing status')"));
        expect(screen, contains('requestAfterSave: true'));
      }
    },
  );
}
