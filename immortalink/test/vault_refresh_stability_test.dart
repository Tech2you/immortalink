import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vault_home_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/content_placeholder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  Completer<void>? pending;
  var denied = false;
  final memories = [
    for (var i = 0; i < 8; i++)
      {
        'id': 'memory-$i',
        'body': 'Saved story $i',
        'prompt_key': 'social_memory_text',
        'prompt_text': 'Memory',
      },
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isNotEmpty) {
      final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    const iconPath = String.fromEnvironment('LOADING_QA_ICONS');
    if (iconPath.isNotEmpty) {
      final bytes = ByteData.sublistView(await File(iconPath).readAsBytes());
      await (FontLoader('MaterialIcons')..addFont(Future.value(bytes))).load();
    }
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
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        http.Response json(Object? value, [int status = 200]) => http.Response(
          jsonEncode(value),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/token')) {
          return json({
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'a',
              'aud': 'authenticated',
              'email': 'test@example.com',
              'created_at': '2026-09-15T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        if (request.url.queryParameters['limit'] == '1' &&
            request.url.path.endsWith('/vaults')) {
          return json([
            {'id': 'vault'},
          ]);
        }
        final wait = pending;
        if (wait != null) await wait.future;
        if (denied) {
          return json({'message': 'Not allowed', 'code': '42501'}, 403);
        }
        if (request.url.path.endsWith('/vaults')) {
          return json({
            'name': 'Test Person',
            'display_name': 'Test Person',
            'avatar_path': null,
            'family_id': null,
          });
        }
        if (request.url.path.endsWith('/memories')) {
          return json(
            request.url.queryParameters.containsKey('prompt_key')
                ? null
                : memories,
          );
        }
        if (request.url.path.endsWith('/vault_core_voice_note')) {
          return json(null);
        }
        return json([]);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'com.llfbandit.record/messages',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async {
          if (name == 'xyz.luan/audioplayers' && call.method == 'create') {
            final playerId = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$playerId'),
              (_) async => null,
            );
          }
          return name == 'com.llfbandit.record/messages' ? null : 1;
        },
      );
    }
  });

  for (final variant in [
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    (name: 'tablet', size: const Size(834, 1194), scale: 1.0),
    (name: 'large-text', size: const Size(320, 844), scale: 1.6),
  ]) {
    testWidgets(
      'cached and refreshed vault keep a stable layout: ${variant.name}',
      (tester) async {
        tester.view.physicalSize = variant.size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final cache = RecentCache(disk: MemoryDisk());
        await cache.setUser('a');
        await cache.put(
          'vault-screen:vault',
          utf8.encode(
            jsonEncode({
              'name': 'Test Person',
              'about': '',
              'photos': [],
              'memories': memories,
            }),
          ),
          epoch: cache.generation,
          kind: 'vault',
        );
        denied = false;
        pending = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: VaultHomeScreen(
              vaultId: 'vault',
              vaultName: 'Test Person',
              cache: cache,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final name = find.text('Test Person').first;
        final element = tester.element(name);
        final rect = tester.getRect(name);
        expect(find.text('Offline'), findsNothing);
        expect(find.byType(FeedPlaceholder), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Edit profile',
                ),
              )
              .onPressed,
          isNull,
        );
        if (const bool.fromEnvironment('LOADING_VISUAL_QA')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/ui-preview-33-qa/cached-${variant.name}.png',
            ),
          );
        }
        pending!.complete();
        pending = null;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(tester.element(name), same(element));
        expect(tester.getRect(name), rect);
        expect(find.text('Offline'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Edit profile',
                ),
              )
              .onPressed,
          isNotNull,
        );
        if (const bool.fromEnvironment('LOADING_VISUAL_QA')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/ui-preview-33-qa/live-${variant.name}.png',
            ),
          );
        }

        await tester.scrollUntilVisible(
          find.text('Saved story 3'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final storyRect = tester.getRect(find.text('Saved story 3'));
        pending = Completer<void>();
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(FeedPlaceholder), findsNothing);
        expect(tester.getRect(find.text('Saved story 3')), storyRect);
        pending!.complete();
        pending = null;
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('Saved story 3')), storyRect);

        await tester.scrollUntilVisible(
          find.text('About'),
          -400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        expect(find.text('About me (Text)'), findsNothing);
        expect(find.text('Upload VN'), findsNothing);
        expect(find.byTooltip('Edit about me'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Voice introduction'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('LOADING_VISUAL_QA')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/ui-preview-34-qa/about-${variant.name}.png',
            ),
          );
        }
        expect(tester.takeException(), isNull);

        // Revoked access must remove stale data, not preserve it for smoothness.
        denied = true;
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        expect(find.text('Saved story 3'), findsNothing);
        expect(await cache.read('vault-screen:vault'), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('account switch clears a vault during an in-flight refresh', (
    tester,
  ) async {
    final cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('a');
    await cache.put(
      'vault-screen:vault',
      utf8.encode(
        jsonEncode({
          'name': 'Test Person',
          'about': '',
          'photos': [],
          'memories': memories,
        }),
      ),
      epoch: cache.generation,
      kind: 'vault',
    );
    denied = false;
    pending = Completer<void>();
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
    expect(find.text('Test Person'), findsWidgets);
    await cache.setUser('b');
    await tester.pump();
    expect(find.text('Test Person'), findsNothing);
    pending!.complete();
    pending = null;
    await tester.pumpAndSettle();
    expect(find.text('Test Person'), findsNothing);
    expect(find.text('Saved story 0'), findsNothing);
    expect(await cache.read('vault-screen:vault'), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
