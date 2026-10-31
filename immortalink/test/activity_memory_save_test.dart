import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/screens/create_memory_screen.dart';
import 'package:immortalink/services/activity_tracking_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var failSave = false;
  var saved = 0;
  final requests = <String>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          }
          return 1;
        },
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        Object? result = [];
        var status = 200;
        if (request.url.path.endsWith('/token')) {
          result = {
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'user-a',
              'aud': 'authenticated',
              'created_at': '2026-10-30T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.url.path.endsWith('/memories') &&
            request.method == 'POST') {
          if (failSave) {
            status = 500;
            result = {'message': 'save failed', 'code': 'XX000'};
          } else {
            saved++;
            result = {'id': 'memory-a'};
          }
        } else if (request.url.path.contains('/functions/')) {
          result = {'chunk_count': 0};
        }
        return http.Response(
          jsonEncode(result),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'demo@example.test',
      password: 'test',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    failSave = false;
    saved = 0;
    SharedPreferences.setMockInitialValues({});
  });
  for (final failure in [false, true]) {
    testWidgets(
      failure
          ? 'failed memory save emits no success activity'
          : 'memory save closes successfully without waiting for stalled analytics',
      (tester) async {
        failSave = failure;
        final pending = Completer<bool>();
        final events = <AppActivity>[];
        final tracker = ActivityTrackingService(
          userId: 'user-a',
          send: (e, _) {
            events.add(e);
            return pending.future;
          },
          isCurrentUser: () => true,
          preferences: SharedPreferences.getInstance,
        );
        ActivityTrackingService.current = tracker;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const CreateMemoryScreen(vaultId: 'vault-a'),
                    ),
                  ),
                  child: const Text('Open composer'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open composer'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'What would you like to remember?'),
          'A private test memory',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('Preserve memory'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Preserve memory'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (failure) {
          expect(saved, 0);
          expect(events, isEmpty);
          expect(find.text('New memory'), findsOneWidget);
        } else {
          expect(
            saved,
            1,
            reason:
                'requests=$requests; text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
          );
          expect(events, [AppActivity.memorySaved]);
          expect(find.text('Open composer'), findsOneWidget);
          expect(pending.isCompleted, false);
        }
        expect(tester.takeException(), isNull);
        pending.complete(false);
        await tester.pump();
        tracker.dispose();
        await tester.pumpWidget(const SizedBox());
        // Drain the existing optional index/push timeout futures after checking
        // that neither they nor analytics delayed the successful navigation.
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }
}
