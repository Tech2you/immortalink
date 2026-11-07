import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/family_feed_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String feedId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class FeedFixture {
  FeedFixture({DateTime? now}) : now = now ?? DateTime.utc(2026, 11, 4, 12);
  final DateTime now;
  final requests = <Uri>[];
  late List<Map<String, dynamic>> rows = List.generate(
    80,
    (i) => {
      'id': feedId(i + 1),
      'vault_id': 'vault-${i % 65}',
      'created_at': now.subtract(Duration(hours: i ~/ 3 + 1)).toIso8601String(),
      'share_to_family_feed': true,
      'prompt_key': 'memory',
      'prompt_text': '',
      'body': 'Family story ${i + 1}',
    },
  );

  http.Response respond(http.Request request) {
    requests.add(request.url);
    final q = request.url.queryParameters;
    final allowed = q['vault_id']!
        .substring(4, q['vault_id']!.length - 1)
        .split(',')
        .map((id) => id.replaceAll('"', ''))
        .toList();
    final dates = request.url.queryParametersAll['created_at']!;
    final oldest = DateTime.parse(
      dates.firstWhere((v) => v.startsWith('gte.')).substring(4),
    );
    final newest = DateTime.parse(
      dates.firstWhere((v) => v.startsWith('lte.')).substring(4),
    );
    expect(q['share_to_family_feed'], 'eq.true');
    expect(q['prompt_key'], 'neq.about_me');
    expect(q['order']?.replaceAll('.nullslast', ''), 'created_at.desc,id.desc');
    expect(allowed.length, lessThanOrEqualTo(50));
    var filtered = rows.where((r) {
      final date = DateTime.parse(r['created_at'] as String);
      if (!allowed.contains(r['vault_id']) ||
          date.isBefore(oldest) ||
          date.isAfter(newest) ||
          r['share_to_family_feed'] != true ||
          r['prompt_key'] == 'about_me') {
        return false;
      }
      final cursor = q['or'];
      if (cursor != null) {
        final time = DateTime.parse(
          RegExp(r'created_at\.lt\.([^,]+)').firstMatch(cursor)!.group(1)!,
        );
        final id = RegExp(
          r'id\.lt\.([0-9a-f-]+)',
        ).firstMatch(cursor)!.group(1)!;
        return date.isBefore(time) ||
            (date == time && (r['id'] as String).compareTo(id) < 0);
      }
      return true;
    }).toList();
    filtered.sort((a, b) {
      final date = (b['created_at'] as String).compareTo(
        a['created_at'] as String,
      );
      return date == 0
          ? (b['id'] as String).compareTo(a['id'] as String)
          : date;
    });
    return http.Response(
      jsonEncode(filtered.take(int.parse(q['limit']!)).toList()),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  test(
    'ten-row pages merge a large family in stable order, even after insertion and deletion',
    () async {
      final fixture = FeedFixture();
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((r) async => fixture.respond(r)),
      );
      addTearDown(client.dispose);
      final vaults = List.generate(65, (i) => 'vault-$i');
      Future<FamilyFeedPage> load([FamilyFeedCursor? cursor]) =>
          loadFamilyFeedPage(
            client,
            vaultIds: vaults,
            cutoff: fixture.now.subtract(const Duration(days: 30)),
            asOf: fixture.now,
            before: cursor,
          );
      final first = await load();
      expect(first.rows, hasLength(10));
      expect(first.hasMore, true);
      final firstIds = first.rows.map((r) => r['id']).toSet();
      fixture.rows.removeWhere((r) => r['id'] == first.rows.first['id']);
      fixture.rows.add({
        ...fixture.rows.first,
        'id': feedId(100),
        'created_at': fixture.now
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      });
      final second = await load(first.next);
      final third = await load(second.next);
      expect(second.rows, hasLength(10));
      expect(third.rows, hasLength(10));
      final all = [...first.rows, ...second.rows, ...third.rows];
      expect(all.map((r) => r['id']).toSet(), hasLength(30));
      expect(second.rows.any((r) => firstIds.contains(r['id'])), false);
      expect(all.any((r) => r['id'] == feedId(100)), false);
      expect(fixture.requests, hasLength(6));
      expect(
        fixture.requests.every((u) => u.queryParameters['limit'] == '11'),
        true,
      );
    },
  );

  test(
    'filters old, future, unshared, About and unselected vault rows before paging',
    () async {
      final fixture = FeedFixture();
      final good = fixture.rows.first;
      fixture.rows = [
        good,
        {
          ...good,
          'id': feedId(90),
          'created_at': fixture.now
              .subtract(const Duration(days: 31))
              .toIso8601String(),
        },
        {
          ...good,
          'id': feedId(91),
          'created_at': fixture.now
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
        {...good, 'id': feedId(92), 'share_to_family_feed': false},
        {...good, 'id': feedId(93), 'prompt_key': 'about_me'},
        {...good, 'id': feedId(94), 'vault_id': 'hidden-or-own'},
      ];
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((r) async => fixture.respond(r)),
      );
      addTearDown(client.dispose);
      final page = await loadFamilyFeedPage(
        client,
        vaultIds: ['vault-0'],
        cutoff: fixture.now.subtract(const Duration(days: 30)),
        asOf: fixture.now,
      );
      expect(page.rows, [good]);
      expect(page.next, null);
      expect(page.hasMore, false);
    },
  );

  test(
    'cursor syntax is validated; page work is bounded; empty scope makes no request',
    () async {
      final fixture = FeedFixture();
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((r) async => fixture.respond(r)),
      );
      addTearDown(client.dispose);
      expect(
        () => FamilyFeedCursor(
          createdAt: fixture.now,
          id: 'id),vault_id.neq.secret',
        ),
        throwsFormatException,
      );
      final empty = await loadFamilyFeedPage(
        client,
        vaultIds: [],
        cutoff: fixture.now,
        asOf: fixture.now,
      );
      expect(empty.rows, isEmpty);
      expect(fixture.requests, isEmpty);
      await loadFamilyFeedPage(
        client,
        vaultIds: ['vault-0'],
        limit: 100000,
        cutoff: fixture.now.subtract(const Duration(days: 30)),
        asOf: fixture.now,
      );
      expect(fixture.requests.single.queryParameters['limit'], '31');
    },
  );

  test(
    'failed page fails as a whole, without exposing a partial result',
    () async {
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient(
          (r) async => http.Response(
            '{"code":"42501","message":"permission denied"}',
            403,
            request: r,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        loadFamilyFeedPage(
          client,
          vaultIds: ['private-vault'],
          cutoff: DateTime.utc(2026),
          asOf: DateTime.utc(2027),
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
