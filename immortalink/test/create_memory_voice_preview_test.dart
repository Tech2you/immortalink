import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/screens/create_memory_screen.dart';
import 'package:immortalink/services/connection_status.dart';
import 'record_memory_screen_test.dart'
    show FakeMemoryRecorder, mockPreviewAudio;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final memories = <Map<String, dynamic>>[];
  final voices = <Map<String, dynamic>>[];
  var uploads = 0;
  setUp(mockPreviewAudio);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        Object? value = [];
        final path = request.url.path;
        if (path.endsWith('/token')) {
          value = {
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'user-a',
              'aud': 'authenticated',
              'created_at': '2026-10-26T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (path.endsWith('/memories') && request.method == 'POST') {
          memories.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          value = {'id': 'memory-a'};
        } else if (path.endsWith('/memory_voice_notes') &&
            request.method == 'POST') {
          voices.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          value = {'id': 'voice-${voices.length}'};
        } else if (path.startsWith('/storage/v1/object/') &&
            request.method == 'POST') {
          uploads++;
          value = {'Key': path};
        } else if (path.endsWith('/has_ai_processing_consent')) {
          value = false;
        }
        return http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('multiple named recordings stay local until Preserve memory', (
    tester,
  ) async {
    final recorder = FakeMemoryRecorder();
    bool? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Compose'),
              onPressed: () async => saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateMemoryScreen(
                    vaultId: 'vault-a',
                    displayName: 'Demo Person',
                    recorder: recorder,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    for (final title in ['Sunday lunch', 'The old garden']) {
      final label = title == 'Sunday lunch'
          ? 'Record voice'
          : 'Add another voice note';
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and review'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), title);
      await tester.tap(find.text('Use recording'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(uploads, 0);
    expect(voices, isEmpty);
    expect(memories, isEmpty);
    await tester.ensureVisible(find.text('Sunday lunch'));
    await tester.tap(find.byTooltip('Recording options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recording name'),
      'Mum\'s Sunday story',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Mum\'s Sunday story'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(voices, isEmpty);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.scrollUntilVisible(
      find.text('Preserve memory'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(Supabase.instance.client.auth.currentUser?.id, 'user-a');
    await tester.runAsync(
      () => Supabase.instance.client.from('vaults').select('id').limit(1),
    );
    expect(
      await tester.runAsync(() => ConnectionStatus.instance.check()),
      isTrue,
    );
    await tester.tap(find.text('Preserve memory'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      memories.length,
      1,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .join(' | '),
    );
    expect(find.text('AI data permission'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(memories.single['vault_id'], 'vault-a');
    expect(memories.single['share_to_family_feed'], isFalse);
    expect(uploads, 2);
    expect(voices.map((voice) => voice['title']), [
      'Mum\'s Sunday story',
      'The old garden',
    ]);
    expect(
      voices.every(
        (voice) =>
            voice['vault_id'] == 'vault-a' && voice['memory_id'] == 'memory-a',
      ),
      isTrue,
    );
    // Saving intentionally does not await the existing background index task.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
