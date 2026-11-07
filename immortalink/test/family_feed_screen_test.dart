import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/paged_family_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_feed_page_test.dart' show FeedFixture, feedId;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = FeedFixture(now: DateTime.now().toUtc());
  final user = feedId(1000);
  final family = feedId(1001);
  var memberPresent = true;
  var failPage = false;
  var denyPage = false;
  var hidden = 'hidden-vault';
  Completer<void>? pageGate;
  var requests = 0;
  final mediaRequests = <Uri>[];
  final writes = <String>[];

  Map<String, dynamic> vault(String id, String owner) => {
    'id': id,
    'owner_id': owner,
    'family_id': family,
    'name': owner,
    'display_name': owner,
    'avatar_path': null,
    'created_at': '2026-01-01T00:00:00Z',
  };
  Map<String, dynamic> member(String owner) => {
    'family_id': family,
    'user_id': owner,
    'role': 'member',
    'joined_at': '2026-02-01T00:00:00Z',
    'is_primary': true,
  };
  http.Response response(http.Request r, Object? data, [int status = 200]) =>
      http.Response(
        jsonEncode(data),
        status,
        request: r,
        headers: {'content-type': 'application/json'},
      );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'com.llfbandit.app_links/messages',
      'com.llfbandit.app_links/events',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          if (call.method == 'create') {
            final player = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$player'),
              (_) async => null,
            );
          }
          return null;
        },
      );
    }
    // One visible relative, plus the viewer and a hidden relative. More than
    // thirty visible rows prove the UI ceiling independently of server output.
    fixture.rows = List.generate(
      45,
      (i) => {
        'id': feedId(i + 1),
        'vault_id': 'relative-vault',
        'created_at': fixture.now
            .subtract(Duration(minutes: i + 1))
            .toIso8601String(),
        'share_to_family_feed': true,
        'prompt_key': 'memory',
        'prompt_text': '',
        'body': 'Family story ${i + 1}',
      },
    );
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/token')) {
          return response(r, {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': user,
              'aud': 'authenticated',
              'email': 'test@example.com',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        if (r.method != 'GET' && path.startsWith('/rest/')) writes.add(path);
        if (path.endsWith('/vaults')) {
          return response(
            r,
            r.url.queryParameters['owner_id']?.startsWith('in.') == true
                ? [
                    vault('own-vault', user),
                    vault('relative-vault', 'relative'),
                    vault('hidden-vault', 'hidden'),
                  ]
                : [vault('own-vault', user)],
          );
        }
        if (path.endsWith('/family_members')) {
          return response(
            r,
            r.url.queryParameters.containsKey('family_id')
                ? [
                    if (memberPresent) member(user),
                    member('relative'),
                    member('hidden'),
                  ]
                : [if (memberPresent) member(user)],
          );
        }
        if (path.endsWith('/family_groups')) {
          return response(r, [
            {'id': family, 'name': 'Test family'},
          ]);
        }
        if (path.endsWith('/family_feed_hidden_vaults')) {
          return response(r, [
            {'hidden_vault_id': hidden},
          ]);
        }
        if (path.endsWith('/memories')) {
          requests++;
          final result = fixture.respond(r);
          final gate = pageGate;
          await gate?.future;
          if (denyPage || failPage) {
            return response(r, {
              'code': denyPage ? '42501' : 'XX000',
              'message': 'Failed test page',
            }, denyPage ? 403 : 500);
          }
          expect(
            r.url.queryParameters['vault_id']?.replaceAll('"', ''),
            'in.(relative-vault)',
          );
          return result;
        }
        if (path.endsWith('/memory_photos') ||
            path.endsWith('/memory_voice_notes')) {
          mediaRequests.add(r.url);
        }
        if (path.startsWith('/storage/')) {
          return response(r, {'message': 'No photo'}, 404);
        }
        return response(r, <Object>[]);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'real feed pages, retries, refresh races and access invalidation stay bounded',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: VaultsScreen()));
      await settle(tester);
      PagedFamilyFeed feed() => tester.widget(find.byType(PagedFamilyFeed));
      expect(feed().itemCount, 10);
      expect(requests, 1);
      expect(find.text('Tree'), findsOneWidget);
      expect(find.text('My vault'), findsOneWidget);
      expect(mediaRequests, hasLength(2));
      for (final request in mediaRequests) {
        expect(request.queryParameters['memory_id']!.split(','), hasLength(10));
      }

      // A transient continuation failure keeps the first page. Retrying twice
      // while the first retry is pending still starts just one request.
      failPage = true;
      feed().onLoadMore();
      await settle(tester);
      expect(feed().itemCount, 10);
      expect(feed().error, isNotNull);
      failPage = false;
      pageGate = Completer<void>();
      final beforeRetry = requests;
      feed().onLoadMore();
      feed().onLoadMore();
      await settle(tester);
      expect(requests, beforeRetry + 1);
      pageGate!.complete();
      pageGate = null;
      await settle(tester);
      expect(feed().itemCount, 20);
      expect(feed().error, null);

      // A refresh supersedes an in-flight continuation. The late old page must
      // neither append stale rows nor erase the refreshed result.
      pageGate = Completer<void>();
      feed().onLoadMore();
      await settle(tester);
      final oldGate = pageGate!;
      pageGate = null;
      fixture.rows.removeAt(0);
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      unawaited(refresh());
      await settle(tester);
      expect(feed().itemCount, 20);
      expect(feed().itemKey(0), ValueKey(feedId(2)));
      oldGate.complete();
      await settle(tester);
      expect(feed().itemCount, 20);
      expect(feed().itemKey(0), ValueKey(feedId(2)));
      feed().onLoadMore();
      await settle(tester);
      expect(feed().itemCount, 30);
      expect(feed().hasMore, false);
      expect(List.generate(30, feed().itemKey).toSet(), hasLength(30));
      final atLimit = requests;
      feed().onLoadMore();
      await settle(tester);
      expect(requests, atLimit);

      // A server authorization denial clears visible content instead of keeping
      // cached posts. An absent membership then prevents any memory request.
      denyPage = true;
      unawaited(refresh());
      await settle(tester);
      expect(feed().itemCount, 0);
      denyPage = false;
      memberPresent = false;
      final beforeLeave = requests;
      unawaited(refresh());
      await settle(tester);
      expect(feed().itemCount, 0);
      expect(requests, beforeLeave);

      memberPresent = true;
      unawaited(refresh());
      await settle(tester);
      expect(feed().itemCount, 10);
      pageGate = Completer<void>();
      feed().onLoadMore();
      await settle(tester);
      // Logout/access invalidation drops both visible and pending pages.
      unawaited(RecentCache.instance.clear());
      await settle(tester);
      pageGate!.complete();
      pageGate = null;
      await settle(tester);
      expect(find.byType(PagedFamilyFeed), findsNothing);
      expect(find.textContaining('Family story'), findsNothing);
      expect(writes, isEmpty);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await Supabase.instance.client.realtime.disconnect();
      // The fake socket never connects; cancel its SDK reconnect timer too.
      Supabase.instance.client.realtime.reconnectTimer.reset();
      await tester.pumpAndSettle();
    },
  );
}
