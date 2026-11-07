import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_directory.dart';

const familyFeedPageSize = 10;
const familyFeedMaximum = 30;

class FamilyFeedCursor {
  FamilyFeedCursor({required this.createdAt, required this.id}) {
    // This value enters a PostgREST boolean expression, so never accept raw
    // client text or an arbitrary database string as filter syntax.
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('Invalid memory cursor');
    }
  }

  final DateTime createdAt;
  final String id;

  factory FamilyFeedCursor.fromRow(Map<String, dynamic> row) =>
      FamilyFeedCursor(
        createdAt: DateTime.parse(row['created_at'] as String),
        id: row['id'] as String,
      );

  String get filter {
    final time = createdAt.toUtc().toIso8601String();
    return 'created_at.lt.$time,and(created_at.eq.$time,id.lt.$id)';
  }
}

class FamilyFeedPage {
  const FamilyFeedPage(this.rows, {required this.hasMore});
  final FamilyRows rows;
  final bool hasMore;
  FamilyFeedCursor? get next =>
      hasMore && rows.isNotEmpty ? FamilyFeedCursor.fromRow(rows.last) : null;
}

/// Reads through the signed-in client's RLS policies. A cursor never grants
/// access. Hidden/own vault filtering is supplied by the screen on every page.
Future<FamilyFeedPage> loadFamilyFeedPage(
  SupabaseClient client, {
  required Iterable<String> vaultIds,
  required DateTime cutoff,
  required DateTime asOf,
  FamilyFeedCursor? before,
  int limit = familyFeedPageSize,
}) async {
  // A refresh may replace all currently loaded rows, but can never expand the
  // feed beyond 30. Ordinary continuation requests use ten rows.
  final count = limit.clamp(1, familyFeedMaximum);
  final rows = <Map<String, dynamic>>[];
  final batches = familyIdBatches(vaultIds).toList();
  // Three small requests at most in flight, even for very large families.
  for (var start = 0; start < batches.length; start += 3) {
    final pages = await Future.wait([
      for (final batch in batches.skip(start).take(3))
        (() async {
          var query = client
              .from('memories')
              .select(
                'id, vault_id, life_stage, prompt_text, prompt_key, body, created_at, share_to_family_feed',
              )
              .inFilter('vault_id', batch)
              .eq('share_to_family_feed', true)
              .neq('prompt_key', 'about_me')
              .gte('created_at', cutoff.toUtc().toIso8601String())
              .lte('created_at', asOf.toUtc().toIso8601String());
          if (before != null) query = query.or(before.filter);
          return query
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(count + 1)
              .timeout(const Duration(seconds: 12));
        })(),
    ]);
    for (final page in pages) {
      rows.addAll(page);
    }
  }
  rows.sort((a, b) {
    final time = DateTime.parse(
      b['created_at'] as String,
    ).compareTo(DateTime.parse(a['created_at'] as String));
    return time != 0 ? time : (b['id'] as String).compareTo(a['id'] as String);
  });
  final unique = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    unique.putIfAbsent(row['id'] as String, () => row);
  }
  return FamilyFeedPage(
    unique.values.take(count).toList(),
    hasMore: unique.length > count,
  );
}
