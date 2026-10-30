import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FamilyRelationshipService {
  FamilyRelationshipService(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> create(
    String familyId,
    Map<String, dynamic> request,
  ) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Not signed in');
    final prefs = await SharedPreferences.getInstance();
    // Retain only an opaque retry ID, never the relative's personal information.
    final digest = sha256.convert(utf8.encode(jsonEncode(request)));
    final key = 'family-relative:$userId:$familyId:$digest';
    var requestId = prefs.getString(key);
    if (requestId == null) {
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      requestId =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (!await prefs.setString(key, requestId)) {
        throw StateError('Could not preserve the retry identifier');
      }
    }
    if (client.auth.currentUser?.id != userId) {
      throw const AuthException('Your account changed. Please try again.');
    }
    final result = await client.rpc(
      'create_family_relative',
      params: {
        'p_family_id': familyId,
        'p_request_id': requestId,
        'p_request': request,
      },
    );
    if (result is! Map ||
        result['id'] is! String ||
        (result['id'] as String).isEmpty ||
        (request['mode'] == 'invite' &&
            (result['invite_code'] is! String ||
                result['expires_at'] is! String))) {
      throw StateError('Incomplete family relationship response');
    }
    // A local preference failure must not turn a committed save into a failure.
    try {
      await prefs.remove(key);
    } catch (_) {}
    return Map<String, dynamic>.from(result);
  }
}
