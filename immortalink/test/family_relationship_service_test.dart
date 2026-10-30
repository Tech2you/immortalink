import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/family_relationship_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost response retries the same operation, without storing family details locally',
    () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <Map<String, dynamic>>[];
      var loseResponse = true;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/token')) {
            return http.Response(
              jsonEncode({
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
              }),
              200,
            );
          }
          expect(r.url.path, endsWith('/rpc/create_family_relative'));
          calls.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (loseResponse) throw http.ClientException('Response lost');
          return http.Response(
            jsonEncode({'type': 'legacy', 'id': 'relative'}),
            200,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.signInWithPassword(
        email: 'test@example.invalid',
        password: 'test-only',
      );
      final request = <String, dynamic>{
        'mode': 'legacy',
        'name': 'Private family name',
        'about': 'Private bio',
        'anchor': {'type': 'vault', 'id': 'a'},
        'relation': 'sibling',
      };
      await expectLater(
        FamilyRelationshipService(client).create('family', request),
        throwsA(isA<http.ClientException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      final retryKeys = prefs
          .getKeys()
          .where((k) => k.startsWith('family-relative:'))
          .toList();
      expect(retryKeys, hasLength(1));
      expect(retryKeys.single, isNot(contains('Private')));
      expect(
        prefs.getString(retryKeys.single),
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      loseResponse = false;
      final result = await FamilyRelationshipService(
        client,
      ).create('family', request);
      expect(result['id'], 'relative');
      expect(calls.last['p_request_id'], calls.first['p_request_id']);
      expect(prefs.containsKey(retryKeys.single), isFalse);
      await FamilyRelationshipService(client).create('family', request);
      expect(calls.last['p_request_id'], isNot(calls.first['p_request_id']));
      await client.dispose();
    },
  );
}
