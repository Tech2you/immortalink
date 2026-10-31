import 'package:supabase_flutter/supabase_flutter.dart';

/// A missing home-screen selection is not proof of missing membership.
/// This read never creates a family or changes the user's home family.
Future<String?> resolveSubscriptionFamily(
  SupabaseClient client, {
  String? preferredFamilyId,
}) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw StateError('Sign in to load your family.');
  final rows = await client
      .from('family_members')
      .select('family_id, is_primary, joined_at')
      .eq('user_id', userId)
      .order('joined_at', ascending: true)
      .timeout(const Duration(seconds: 8));
  if (client.auth.currentUser?.id != userId) {
    throw StateError('The signed-in account changed.');
  }
  if (rows.isEmpty) return null;
  final ids = rows.map((row) {
    final id = row['family_id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Invalid family membership');
    }
    return id.trim();
  }).toList();
  final preferred = preferredFamilyId?.trim();
  if (preferred != null && ids.contains(preferred)) return preferred;
  final primary = rows.indexWhere((row) => row['is_primary'] == true);
  return primary >= 0 ? ids[primary] : ids.first;
}
