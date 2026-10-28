import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/family_directory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'directory pages beyond 1000 members and bounds owner filters',
    () async {
      var memberCalls = 0;
      var vaultCalls = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          final offset = int.parse(query['offset'] ?? '0');
          expect(query['limit'], '200');
          if (request.url.path.endsWith('/family_members')) {
            memberCalls++;
            expect(query['family_id'], 'eq.family');
            expect(query['order'], startsWith('user_id.asc'));
            return http.Response(
              jsonEncode([
                for (var i = offset; i < offset + 200 && i < 1001; i++)
                  {'user_id': 'member-$i', 'role': 'member'},
              ]),
              200,
              request: request,
            );
          }
          vaultCalls++;
          final filter = query['owner_id']!;
          final ids = filter.substring(4, filter.length - 1).split(',');
          expect(ids.length, lessThanOrEqualTo(50));
          expect(query['order'], startsWith('id.asc'));
          return http.Response(
            jsonEncode([
              for (final id in ids) {'id': 'vault-$id', 'owner_id': id},
            ]),
            200,
            request: request,
          );
        }),
      );
      final members = await loadFamilyMembers(client, 'family');
      final vaults = await loadFamilyVaults(
        client,
        members.map((row) => row['user_id'] as String),
      );
      expect(members, hasLength(1001));
      expect(vaults, hasLength(1001));
      expect(memberCalls, 6);
      expect(vaultCalls, 21);
      await client.dispose();
    },
  );

  test('page failures do not return a misleading partial family', () async {
    await expectLater(
      pagedFamilyRows((from, to) async {
        if (from > 0) throw StateError('access lost');
        return List.generate(200, (i) => {'id': i});
      }),
      throwsStateError,
    );
  });

  test('ID batches deduplicate and do not produce empty requests', () {
    expect(familyIdBatches(['a', 'a', '', 'b']).toList(), [
      ['a', 'b'],
    ]);
    expect(familyIdBatches([]), isEmpty);
  });
}
