import 'package:supabase_flutter/supabase_flutter.dart';

typedef FamilyRows = List<Map<String, dynamic>>;

// Each caller supplies a stable ordering so API row limits cannot silently
// truncate a large family. A failed page fails the load instead of hiding people.
Future<FamilyRows> pagedFamilyRows(
  Future<FamilyRows> Function(int from, int to) fetch,
) async {
  const size = 200;
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0; ; offset += size) {
    final page = await fetch(offset, offset + size - 1);
    rows.addAll(page);
    if (page.length < size) return rows;
  }
}

Iterable<List<String>> familyIdBatches(Iterable<String> ids) sync* {
  final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
  for (var start = 0; start < unique.length; start += 50) {
    yield unique.sublist(start, (start + 50).clamp(0, unique.length));
  }
}

Future<FamilyRows> loadFamilyMembers(SupabaseClient client, String familyId) {
  return pagedFamilyRows(
    (from, to) => client
        .from('family_members')
        .select('user_id, slot_key, role, is_primary')
        .eq('family_id', familyId)
        .order('user_id', ascending: true)
        .range(from, to)
        .timeout(const Duration(seconds: 12)),
  );
}

Future<FamilyRows> loadFamilyVaults(
  SupabaseClient client,
  Iterable<String> owners,
) async {
  final rows = <Map<String, dynamic>>[];
  // Keep URLs and concurrent work bounded even when a family grows large.
  for (final batch in familyIdBatches(owners)) {
    rows.addAll(
      await pagedFamilyRows(
        (from, to) => client
            .from('vaults')
            .select('id, name, display_name, owner_id, family_id, avatar_path')
            .inFilter('owner_id', batch)
            .order('id', ascending: true)
            .range(from, to)
            .timeout(const Duration(seconds: 12)),
      ),
    );
  }
  return rows;
}
