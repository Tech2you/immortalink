import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/screens/vault_companion_screen.dart';
import 'apple_subscription_service_test.dart'
    show FakeRpc, FakeFunctions, FakeAuth;

class _ChatAuth extends FakeAuth {
  @override
  Session get currentSession =>
      Session(accessToken: 'fixture', tokenType: 'bearer', user: currentUser!);
}

class _ChatClient extends Fake implements SupabaseClient {
  @override
  final _ChatAuth auth = _ChatAuth();
  @override
  final FakeFunctions functions = FakeFunctions();
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #rpc) return FakeRpc(true);
    return super.noSuchMethod(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Completer<String>? reply;
  final requests = <Map<String, dynamic>>[];
  final backend = _ChatClient();
  late SupabaseClient original;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'ai_chat_warning_never_show_${backend.auth.currentUser!.id}': true,
    });
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    original = Supabase.instance.client;
    Supabase.instance.client = backend;
    backend.functions.result = (Object? value) {
      final body = Map<String, dynamic>.from(value as Map);
      if (body['mode'] == 'icebreakers') {
        return FunctionResponse(
          status: 200,
          data: {
            'icebreakers': ['What is saved about you?'],
          },
        );
      }
      requests.add(body);
      return reply!.future.then(
        (text) => FunctionResponse(status: 200, data: {'answer': text}),
      );
    };
  });
  tearDownAll(() {
    Supabase.instance.client = original;
    return Supabase.instance.dispose();
  });

  Future<void> open(WidgetTester tester, {bool legacy = true}) async {
    reply = Completer<String>();
    requests.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: VaultCompanionScreen(
          displayName: 'Bremner',
          legacyMemberId: legacy ? 'bremner' : null,
          vaultId: legacy ? null : 'vault',
          familyId: 'family',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String question) async {
    await tester.enterText(find.byType(TextField), question);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> answer(WidgetTester tester, String text) async {
    reply!.complete(text);
    await tester.pump();
  }

  ScrollController scroller(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!;

  for (final legacy in [false, true]) {
    testWidgets(
      'chat keeps keyboard, next draft and scroll bounds stable (legacy=$legacy)',
      (tester) async {
        await open(tester, legacy: legacy);
        await send(tester, 'Can you share a memory of your grandparents?');
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enabled, true);
        expect(field.focusNode!.hasFocus, true);
        expect(tester.testTextInput.isVisible, true);
        expect(requests, hasLength(1));
        expect(scroller(tester).position.outOfRange, false);
        await tester.enterText(find.byType(TextField), 'My next question');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        expect(requests, hasLength(1));
        await answer(tester, 'No grandparents are linked to my profile yet.');
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(scroller(tester).position.outOfRange, false);
        }
        expect(find.text('My next question'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          true,
        );
        expect(
          find.text('No grandparents are linked to my profile yet.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'long answer does not pull a reader away from earlier messages or reopen the keyboard',
    (tester) async {
      await open(tester);
      await send(tester, 'Tell me the saved story');
      await answer(tester, List.filled(70, 'A saved detail.').join('\n'));
      await tester.pumpAndSettle();
      reply = Completer<String>();
      await send(tester, 'And another?');
      final scroll = scroller(tester);
      scroll.jumpTo(0);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      final before = scroll.offset;
      await answer(tester, 'One more saved detail.');
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('leaving AI while a response is pending is safe', (tester) async {
    await open(tester);
    await send(tester, 'Tell me something saved');
    await tester.pumpWidget(const SizedBox());
    await answer(tester, 'Saved detail.');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
