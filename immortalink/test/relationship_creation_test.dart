import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/relationship_tree_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final writes = <Map<String, dynamic>>[];
  late RecentCache cache;
  http.Response response(http.Request r, Object? data) => http.Response(
    jsonEncode(data),
    200,
    request: r,
    headers: {'content-type': 'application/json'},
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/token')) {
          return response(r, {
            'access_token': 'token',
            'refresh_token': 'refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'user',
              'aud': 'authenticated',
              'email': 'test@example.invalid',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        if (path.endsWith('/rpc/create_family_relative')) {
          writes.add(jsonDecode(r.body) as Map<String, dynamic>);
          return response(r, {
            'type': 'invite',
            'id': 'new',
            'invite_code': 'TESTCODE',
            'expires_at': '2027-01-01T00:00:00Z',
          });
        }
        expect(
          r.method,
          'GET',
          reason: 'Creation must not use separate table writes',
        );
        if (path.endsWith('/family_members')) {
          return response(r, [
            {'user_id': 'user', 'role': 'member'},
          ]);
        }
        if (path.endsWith('/vaults')) {
          return response(r, [
            {
              'id': 'one',
              'owner_id': 'user',
              'name': 'Person',
              'display_name': 'Person',
            },
          ]);
        }
        return response(r, []);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.invalid',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> show(WidgetTester tester, {bool invite = false}) async {
    writes.clear();
    cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('user');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: RelationshipTreeScreen(
          familyId: 'family',
          cache: cache,
          inviteOnOpen: invite,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await cache.clear();
    expect(tester.takeException(), isNull);
  }

  testWidgets('cancel sibling parent selection performs no writes', (
    tester,
  ) async {
    await show(tester, invite: true);
    await tester.tap(find.text('Invite sibling'));
    await tester.pumpAndSettle();
    expect(find.text('Sibling only (no parent lineage)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await close(tester);
  });
  testWidgets('invited-child placeholder is chosen before one atomic save', (
    tester,
  ) async {
    await show(tester, invite: true);
    await tester.tap(find.text('Invite child'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Parent not added yet'));
    await tester.tap(find.text('Save parent'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final payload = writes.single['p_request'] as Map;
    expect(payload['relation'], 'child');
    expect(payload['mode'], 'invite');
    expect(payload['other_parent'], {'type': 'placeholder'});
    expect(find.text('TESTCODE'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
    'legacy sibling-only saves as sibling with no intermediate child write',
    (tester) async {
      await show(tester);
      // Pan to the sibling add control without changing the tree's zoom.
      final viewer = find.byType(InteractiveViewer);
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      controller.value = Matrix4.identity()
        ..translateByDouble(-400.0, -750.0, 0.0, 1.0)
        ..scaleByDouble(0.7, 0.7, 0.7, 1.0);
      await tester.pumpAndSettle();
      final add = find.ancestor(
        of: find.text('Add sibling'),
        matching: find.byType(InkWell),
      );
      tester.widget<InkWell>(add).onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add legacy relative'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sibling');
      await tester.tap(find.text('Create profile'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      final payload = writes.single['p_request'] as Map;
      expect(payload['relation'], 'sibling');
      expect(payload['mode'], 'legacy');
      expect(payload['shared_parents'], isEmpty);
      expect(payload['anchor'], {'type': 'vault', 'id': 'one'});
      await close(tester);
    },
  );
}
