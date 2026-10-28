import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/content_screening_permission.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apple_subscription_service_test.dart' show FakeSupabase, FakeRpc;

Map<String, Object> state({
  bool allowed = false,
  String revision = '0',
  String policy = contentScreeningPolicyVersion,
}) => {'allowed': allowed, 'revision': revision, 'policy_version': policy};

class ScreeningBackend extends FakeSupabase {
  Object? readResult = state();
  Object? writeResult;
  final reads = <String>[];
  final choices = <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #rpc) {
      final name = invocation.positionalArguments.first as String;
      reads.add(name);
      if (name == 'get_content_screening_permission') {
        return FakeRpc(readResult);
      }
      if (name == 'set_content_screening_permission') {
        final params =
            invocation.namedArguments[#params] as Map<String, dynamic>;
        choices.add(params);
        return FakeRpc(
          writeResult ??
              state(allowed: params['p_allowed'] as bool, revision: '2'),
        );
      }
      throw StateError('Unexpected RPC: $name');
    }
    return super.noSuchMethod(invocation);
  }
}

User otherUser() => User(
  id: '00000000-0000-4000-8000-000000000002',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '',
);

Future<List<bool>> open(
  WidgetTester tester,
  ScreeningBackend backend, {
  bool enabled = true,
  bool settings = true,
  bool twice = false,
  double textScale = 1,
}) async {
  final results = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              for (var i = 0; i < (twice ? 2 : 1); i++) {
                requestContentScreeningPermission(
                  context,
                  client: backend,
                  enabled: enabled,
                  settings: settings,
                ).then(results.add);
              }
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return results;
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
  });
  testWidgets('release gate is off and makes no RPC or provider request', (
    tester,
  ) async {
    expect(contentScreeningControlsEnabled, false);
    final backend = ScreeningBackend();
    final results = await open(
      tester,
      backend,
      enabled: contentScreeningControlsEnabled,
    );
    expect(results, [false]);
    expect(backend.reads, isEmpty);
    expect(backend.functions.calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('signed-out user is not prompted', (tester) async {
    final backend = ScreeningBackend()..auth.currentUser = null;
    expect(await open(tester, backend), [false]);
    expect(backend.reads, isEmpty);
  });

  for (final allowed in [false, true]) {
    testWidgets('explicit choice $allowed is separate and account-bound', (
      tester,
    ) async {
      final backend = ScreeningBackend();
      final results = await open(tester, backend);
      expect(
        find.textContaining('Private drafts and existing archives'),
        findsOneWidget,
      );
      expect(find.textContaining('voice recordings or videos'), findsOneWidget);
      expect(find.textContaining('cannot recall'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(backend.choices, isEmpty);
      await tester.tap(find.text(allowed ? 'Allow safety checks' : 'Decline'));
      await tester.pumpAndSettle();
      expect(results, [allowed]);
      expect(backend.choices.single, {
        'p_allowed': allowed,
        'p_policy_version': contentScreeningPolicyVersion,
        'p_expected_user_id': backend.auth.currentUser!.id,
      });
      expect(backend.reads, [
        'get_content_screening_permission',
        'set_content_screening_permission',
      ]);
      expect(backend.functions.calls, 0);
    });
  }

  testWidgets(
    'current acceptance avoids repeat prompt but settings allow withdrawal',
    (tester) async {
      final backend = ScreeningBackend()
        ..readResult = state(allowed: true, revision: '1');
      expect(await open(tester, backend, settings: false), [true]);
      await tester.pumpAndSettle();
      expect(backend.choices, isEmpty);
      final results = await open(tester, backend);
      await tester.tap(find.text('Turn off checks'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(backend.choices.single['p_allowed'], false);
    },
  );

  testWidgets(
    'new disclosure cannot be accepted by old app; withdrawal still works',
    (tester) async {
      final backend = ScreeningBackend()
        ..readResult = state(
          allowed: true,
          revision: '1',
          policy: 'future-disclosure',
        );
      final results = await open(tester, backend);
      expect(find.textContaining('Update Heiro'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Turn off checks'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    },
  );

  for (final response in <Object?>[
    Exception('lookup failed'),
    null,
    true,
    {
      'allowed': 'true',
      'revision': '1',
      'policy_version': contentScreeningPolicyVersion,
    },
    state(allowed: true),
    state(revision: '-1'),
    state(revision: '9223372036854775808'),
  ]) {
    testWidgets(
      'invalid lookup cannot grant; withdrawal remains accessible: $response',
      (tester) async {
        final backend = ScreeningBackend()..readResult = response;
        final results = await open(tester, backend);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.textContaining('Could not load'), findsOneWidget);
        await tester.tap(find.text('Turn off checks'));
        await tester.pumpAndSettle();
        expect(results, [false]);
        expect(backend.choices.single['p_allowed'], false);
      },
    );
  }

  testWidgets(
    'failed withdrawal is not represented as success and can be retried',
    (tester) async {
      final backend = ScreeningBackend()
        ..readResult = state(allowed: true, revision: '1')
        ..writeResult = Exception('offline');
      final results = await open(tester, backend);
      await tester.tap(find.text('Turn off checks'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(
        find.textContaining('Checks may still be enabled'),
        findsOneWidget,
      );
      backend.writeResult = state(revision: '2');
      await tester.tap(find.text('Turn off checks'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(backend.choices.length, 2);
    },
  );

  for (final response in <Object>[
    Exception('offline'),
    state(),
    state(allowed: true, revision: '1'),
    state(allowed: true, revision: '2', policy: 'future-disclosure'),
  ]) {
    testWidgets('unconfirmed write never authorizes processing: $response', (
      tester,
    ) async {
      final backend = ScreeningBackend()
        ..readResult = state(revision: '1')
        ..writeResult = response;
      final results = await open(tester, backend);
      await tester.tap(find.text('Allow safety checks'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.textContaining('Could not confirm'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  }

  testWidgets('bigint revisions remain exact', (tester) async {
    final backend = ScreeningBackend()
      ..readResult = state(revision: '9007199254740992')
      ..writeResult = state(allowed: true, revision: '9007199254740993');
    final results = await open(tester, backend);
    await tester.tap(find.text('Allow safety checks'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets(
    'switching accounts before choice cannot save to the new account',
    (tester) async {
      final backend = ScreeningBackend();
      final results = await open(tester, backend);
      backend.auth.currentUser = otherUser();
      await tester.tap(find.text('Allow safety checks'));
      await tester.pumpAndSettle();
      expect(backend.choices, isEmpty);
      expect(results, isEmpty);
      expect(find.textContaining('Your account changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('account change during lookup rejects the result', (
    tester,
  ) async {
    final delayed = Completer<Object?>();
    final backend = ScreeningBackend()..readResult = delayed.future;
    final results = await open(tester, backend, settings: false);
    backend.auth.currentUser = otherUser();
    delayed.complete(state(allowed: true, revision: '1'));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets(
    'write captures original account; switched session is not authorized',
    (tester) async {
      final delayed = Completer<Object?>();
      final backend = ScreeningBackend()..writeResult = delayed.future;
      final originalUser = backend.auth.currentUser!.id;
      final results = await open(tester, backend);
      await tester.tap(find.text('Allow safety checks'));
      await tester.pump();
      backend.auth.currentUser = otherUser();
      delayed.complete(state(allowed: true, revision: '1'));
      await tester.pumpAndSettle();
      expect(backend.choices.single['p_expected_user_id'], originalUser);
      expect(results, isEmpty);
      expect(find.textContaining('Your account changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    },
  );

  testWidgets(
    'duplicate requests use one dialog and buttons lock while saving',
    (tester) async {
      final delayed = Completer<Object?>();
      final backend = ScreeningBackend()..writeResult = delayed.future;
      final results = await open(tester, backend, twice: true);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(backend.reads.length, 1);
      await tester.tap(find.text('Allow safety checks'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(backend.choices.length, 1);
      delayed.complete(state(allowed: true, revision: '1'));
      await tester.pumpAndSettle();
      expect(results, [true, true]);
    },
  );

  testWidgets('lookup timeout permits retry, without enabling processing', (
    tester,
  ) async {
    final delayed = Completer<Object?>();
    final backend = ScreeningBackend()..readResult = delayed.future;
    final results = await open(tester, backend);
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsOneWidget);
    backend.readResult = state();
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    delayed.complete(state(allowed: true, revision: '1'));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(backend.choices, isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('closing during lookup ignores a late grant', (tester) async {
    final delayed = Completer<Object?>();
    final backend = ScreeningBackend()..readResult = delayed.future;
    final results = await open(tester, backend, settings: false);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    delayed.complete(state(allowed: true, revision: '1'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(1024, 768),
  ]) {
    testWidgets('dialog fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, ScreeningBackend(), textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(size.width));
      expect(dialog.bottom, lessThanOrEqualTo(size.height));
      final button = find.widgetWithText(FilledButton, 'Allow safety checks');
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
      if (const bool.fromEnvironment('CAPTURE_SCREENING_PERMISSION')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '/private/tmp/heiro-screening-${size.width.toInt()}.png',
          ),
        );
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  }

  test('app and migration use the same policy and setter contract', () {
    final migration = File(
      'supabase/migrations/20261023110215_content_screening_permission.sql',
    ).readAsStringSync();
    expect(migration, contains("'$contentScreeningPolicyVersion'"));
    expect(migration, contains('p_expected_user_id uuid'));
    final screen = File('lib/screens/vaults_screen.dart').readAsStringSync();
    expect(screen, contains('if (contentScreeningControlsEnabled)'));
  });
}
