import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IndexingService {
  static final _client = Supabase.instance.client;

  static String _accessTokenOrThrow() {
    final session = _client.auth.currentSession;
    final token = session?.accessToken?.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Missing JWT (access token). Please sign in again.');
    }
    return token;
  }

  static Map<String, String> _authHeadersOrThrow() {
    final token = _accessTokenOrThrow();
    // Send both casings to avoid weird edge cases.
    return {'Authorization': 'Bearer $token', 'authorization': 'Bearer $token'};
  }

  static String _prettyData(dynamic data) {
    try {
      if (data == null) return '(null)';
      if (data is String) return data;
      return data.toString();
    } catch (_) {
      return '(unprintable)';
    }
  }

  static String _extractError(dynamic data) {
    if (data is Map) {
      // common edge patterns
      final err = data['error'] ?? data['message'] ?? data['details'];
      if (err != null) return err.toString();
      if (data['details'] != null) return data['details'].toString();
    }
    return _prettyData(data);
  }

  /// Index a single memory by calling the Edge Function `index_memory`.
  /// Returns chunk_count (0+).
  static Future<int> indexMemory({
    required String vaultId,
    required String memoryId,
  }) async {
    final headers = _authHeadersOrThrow();

    final res = await _client.functions
        .invoke(
          'index_memory',
          headers: headers,
          body: {'vault_id': vaultId, 'memory_id': memoryId},
        )
        .timeout(const Duration(seconds: 60));

    if (res.status != 200) {
      throw Exception(
        'index_memory failed: HTTP ${res.status}: ${_extractError(res.data)}',
      );
    }

    final data = res.data;

    if (data is Map) {
      final n = data['chunk_count'] ?? data['chunks'] ?? 0;
      return int.tryParse(n.toString()) ?? 0;
    }

    return 0;
  }

  /// ✅ NEW: Index "About Me" text using the same Edge Function `index_memory`.
  ///
  /// This calls index_memory with:
  /// {
  ///   vault_id,
  ///   source: "about_me",
  ///   about_me_text: "..."
  /// }
  ///
  /// Returns chunk_count (0+).
  static Future<int> indexAboutMe({
    required String vaultId,
    required String aboutMeText,
  }) async {
    final headers = _authHeadersOrThrow();

    final text = aboutMeText.trim();
    if (text.isEmpty) return 0;

    final res = await _client.functions
        .invoke(
          'index_memory',
          headers: headers,
          body: {
            'vault_id': vaultId,
            'source': 'about_me',
            'about_me_text': text,
          },
        )
        .timeout(const Duration(seconds: 60));

    if (res.status != 200) {
      throw Exception(
        'index_about_me failed: HTTP ${res.status}: ${_extractError(res.data)}',
      );
    }

    final data = res.data;
    if (data is Map) {
      final n = data['chunk_count'] ?? data['chunks'] ?? 0;
      return int.tryParse(n.toString()) ?? 0;
    }
    return 0;
  }

  /// Re-index every memory in the vault (sequential, safer).
  /// Returns how many memories were indexed successfully.
  static Future<int> backfillVault({required String vaultId}) async {
    _authHeadersOrThrow();

    final rows = await _client
        .from('memories')
        .select('id, created_at')
        .eq('vault_id', vaultId)
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 25));

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return 0;

    int ok = 0;
    for (final r in list) {
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      try {
        final chunks = await indexMemory(vaultId: vaultId, memoryId: id);
        debugPrint('✅ Indexed memory $id → $chunks chunks');
        ok++;
      } catch (e) {
        debugPrint('❌ Index failed for $id: $e');
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    return ok;
  }

  /// Optional helper for quick debugging (call it from a button).
  static Future<void> debugIndexMemory({
    required String vaultId,
    required String memoryId,
  }) async {
    final chunks = await indexMemory(vaultId: vaultId, memoryId: memoryId);
    debugPrint('INDEX DEBUG → memory=$memoryId chunks=$chunks');
  }

  /// ✅ Optional helper for quick debugging of About Me indexing.
  static Future<void> debugIndexAboutMe({
    required String vaultId,
    required String aboutMeText,
  }) async {
    final chunks = await indexAboutMe(
      vaultId: vaultId,
      aboutMeText: aboutMeText,
    );
    debugPrint('ABOUT ME INDEX DEBUG → vault=$vaultId chunks=$chunks');
  }
}
