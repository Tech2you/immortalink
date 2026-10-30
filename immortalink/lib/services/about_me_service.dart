import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AboutMeService {
  const AboutMeService(this.client);
  final SupabaseClient client;

  Future<String> save({required String vaultId, required String text}) async {
    if (client.auth.currentUser == null) {
      throw const AuthException('Please sign in again.');
    }
    if (text.length > 10000) throw const FormatException('Biography too long');
    final existing = await client
        .from('memories')
        .select('id')
        .eq('vault_id', vaultId)
        .eq('prompt_key', 'about_me')
        .order('created_at')
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 20));
    final id = existing?['id'] as String?;
    if (id != null) {
      // A returned row confirms RLS permitted the update, not just HTTP success.
      final row = await client
          .from('memories')
          .update({'body': text})
          .eq('id', id)
          .eq('vault_id', vaultId)
          .eq('prompt_key', 'about_me')
          .select('id')
          .single()
          .timeout(const Duration(seconds: 20));
      return row['id'] as String;
    }
    // Stable UUID keeps retries and simultaneous first saves to a single row.
    // Existing biographies above retain their IDs and sharing settings.
    final bytes = sha256.convert(utf8.encode('heiro:about-me:$vaultId')).bytes;
    final uuid = bytes.take(16).toList();
    uuid[6] = (uuid[6] & 0x0f) | 0x80;
    uuid[8] = (uuid[8] & 0x3f) | 0x80;
    final h = uuid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final stableId =
        '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    final row = await client
        .from('memories')
        .upsert({
          'id': stableId,
          'vault_id': vaultId,
          'life_stage': 'mid',
          'prompt_key': 'about_me',
          'prompt_text': 'About me',
          'body': text,
          'share_to_family_feed': false,
        }, onConflict: 'id')
        .select('id')
        .single()
        .timeout(const Duration(seconds: 20));
    return row['id'] as String;
  }
}
