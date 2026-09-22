import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/relationship_tree_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/family_tree_settings_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var networkCalls = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('[]', 200);
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('cached tree makes no requests and has no edit actions', (
    tester,
  ) async {
    final cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('a');
    await cache.put(
      'tree:family',
      utf8.encode(
        jsonEncode({
          'viewer': 'vault:one',
          'people': [
            {
              'type': 'vault',
              'id': 'one',
              'name': 'Test Person',
              'ownerId': 'a',
              'slotKey': null,
              'placeholder': false,
            },
          ],
          'relationships': [],
        }),
      ),
      epoch: cache.generation,
      kind: 'tree',
      familyId: 'family',
    );
    networkCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RelationshipTreeScreen(
          familyId: 'family',
          cachedOnly: true,
          cache: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Open Vault'), findsNothing);
    expect(find.text('Add child'), findsNothing);
    expect(find.text('Add parent'), findsNothing);
    expect(networkCalls, 0);
    final menu = tester.widget<FamilyTreeSettingsMenu>(
      find.byType(FamilyTreeSettingsMenu),
    );
    expect(menu.canLeave, isFalse);
    expect(menu.canEditName, isFalse);
    menu.onSelected(FamilyTreeAction.refresh);
    await tester.pumpAndSettle();
    expect(networkCalls, 0);
    await cache.clear();
    await tester.pumpAndSettle();
    expect(find.text('Test Person'), findsNothing);
    expect(
      find.text('This offline copy is no longer available.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
