import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/services/about_me_service.dart';

void main() {
  late SupabaseClient client;
  final writes = <http.Request>[];
  String? existingId;
  bool denied = false;

  setUp(() async {
    writes.clear();
    existingId = null;
    denied = false;
    client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object? body;
        var status = 200;
        if (request.url.path.endsWith('/token')) {
          body = {
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'owner',
              'aud': 'authenticated',
              'created_at': '2026-10-01T00:00:00Z',
            },
          };
        } else if (request.method == 'GET') {
          body = existingId == null
              ? []
              : [
                  {'id': existingId},
                ];
        } else {
          writes.add(request);
          if (denied) {
            status = 403;
            body = {'code': '42501', 'message': 'Not allowed'};
          } else {
            body = {'id': existingId ?? jsonDecode(request.body)['id']};
          }
        }
        return http.Response(
          jsonEncode(body),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test',
    );
  });
  tearDown(() => client.dispose());

  test(
    'new biography persists before indexing, and is not a feed post',
    () async {
      final service = AboutMeService(client);
      final id = await service.save(vaultId: 'vault', text: 'My story');
      final saved = jsonDecode(writes.single.body);
      expect(saved['body'], 'My story');
      expect(saved['prompt_key'], 'about_me');
      expect(saved['share_to_family_feed'], false);
      expect(writes.single.url.path, '/rest/v1/memories');
      expect(await service.save(vaultId: 'vault', text: 'My story'), id);
      expect(jsonDecode(writes.last.body)['id'], id);
      expect(writes.last.url.queryParameters['on_conflict'], 'id');
    },
  );

  test('editing preserves existing id, metadata and sharing', () async {
    existingId = 'original';
    expect(
      await AboutMeService(client).save(vaultId: 'vault', text: 'Updated'),
      'original',
    );
    expect(writes.single.method, 'PATCH');
    expect(jsonDecode(writes.single.body), {'body': 'Updated'});
    expect(writes.single.url.queryParameters['vault_id'], 'eq.vault');
    expect(writes.single.url.queryParameters['prompt_key'], 'eq.about_me');
  });

  test('permission rejection is not reported as saved', () async {
    existingId = 'other-owner';
    denied = true;
    await expectLater(
      AboutMeService(client).save(vaultId: 'vault', text: 'Draft'),
      throwsA(isA<PostgrestException>()),
    );
    expect(writes.length, 1);
  });

  test('blank biography can be cleared without deleting the account', () async {
    existingId = 'original';
    await AboutMeService(client).save(vaultId: 'vault', text: '');
    expect(jsonDecode(writes.single.body), {'body': ''});
  });
}
