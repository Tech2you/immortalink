import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vault_home_screen.dart';
import 'package:immortalink/screens/recently_viewed_screen.dart';
import 'package:immortalink/screens/create_memory_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/vault_media.dart';
import 'package:immortalink/services/connection_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var networkCalls = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => 1,
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      httpClient: MockClient((_) async {
        networkCalls++;
        throw http.ClientException('private-host secret');
      }),
    );
    ConnectionStatus.instance.report(http.ClientException('offline'));
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('directory opens a visited relative vault without any requests', (
    tester,
  ) async {
    final cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('a');
    await cache.put(
      'legacy-screen:relative',
      utf8.encode(
        jsonEncode({
          'name': 'Relative',
          'about': 'Their story',
          'photos': [],
          'memories': [
            {'id': 'm', 'body': 'Shared memory'},
          ],
        }),
      ),
      epoch: cache.generation,
      kind: 'vault',
    );
    networkCalls = 0;
    await tester.pumpWidget(
      MaterialApp(home: RecentlyViewedScreen(cache: cache)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vaults'), findsOneWidget);
    await tester.tap(find.text('Relative'));
    await tester.pumpAndSettle();
    expect(find.text('Shared memory'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(networkCalls, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal vault route restores stories, blocks edits and clears expired content',
    (tester) async {
      var now = DateTime(2026);
      final cache = RecentCache(disk: MemoryDisk(), clock: () => now);
      await cache.setUser('a');
      await cache.put(
        'vault-screen:vault',
        utf8.encode(
          jsonEncode({
            'name': 'Test Person',
            'about': 'About text',
            'photos': [],
            'memories': [
              {'id': 'm', 'prompt_text': 'Trip', 'body': 'A recent story'},
            ],
          }),
        ),
        epoch: cache.generation,
        kind: 'vault',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VaultHomeScreen(
            vaultId: 'vault',
            vaultName: 'Test Person',
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Offline copy'), findsNothing);
      expect(find.textContaining('Recently viewed - read-only'), findsNothing);
      expect(find.text('A recent story'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.textContaining('private-host'), findsNothing);
      now = now.add(const Duration(hours: 6));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('A recent story'), findsNothing);
      expect(find.text('Test Person'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('offline media tiles stay square at $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = RecentCache(disk: MemoryDisk());
      await cache.setUser('a');
      await cache.put(
        'vault-screen:vault',
        utf8.encode(
          jsonEncode({
            'name': 'Test Person',
            'about': '',
            'memories': [
              {'id': 'm', 'body': 'Story'},
            ],
            'photos': [
              for (var i = 0; i < 4; i++)
                {
                  'id': '$i',
                  'memoryId': 'm',
                  'path': '$i.mp4',
                  'url': 'https://example.com/$i.mp4',
                },
            ],
          }),
        ),
        epoch: cache.generation,
        kind: 'vault',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VaultHomeScreen(
            vaultId: 'vault',
            vaultName: 'Test',
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Media'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      for (final tile in find.byType(VaultMedia).evaluate()) {
        final size = (tile.renderObject as RenderBox).size;
        expect(size.width, closeTo(size.height, 0.1));
      }
      expect(find.text('Offline copy'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('offline composer preserves typed text and disables preserve', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateMemoryScreen(vaultId: 'vault')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keep this draft');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Preserve'))
          .onPressed,
      isNull,
    );
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.textContaining('private-host'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
