import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/batched_signed_urls.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('50 avatars use one fresh signing request instead of 50', () async {
    final requests = <List<dynamic>>[];
    final client = SupabaseClient(
      'https://test.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/storage/v1/object/sign/avatars');
        final body = jsonDecode(request.body) as Map;
        expect(body['expiresIn'], 3600);
        final paths = body['paths'] as List;
        requests.add(paths);
        return http.Response(
          jsonEncode([
            for (final path in paths)
              {
                'path': path,
                'signedURL': '/object/sign/avatars/$path?token=test',
              },
          ]),
          200,
        );
      }),
    );
    final paths = List.generate(50, (i) => 'person-$i/avatar');
    final urls = await batchedSignedUrls(client, 'avatars', [
      ...paths,
      '',
      paths.first,
    ]);
    expect(requests, hasLength(1));
    expect(requests.single, hasLength(50));
    expect(urls, hasLength(50));
    await batchedSignedUrls(client, 'avatars', paths);
    expect(
      requests,
      hasLength(2),
    ); // A reload rechecks access; no old-link cache.
    await client.dispose();
  });

  test(
    'large loads are bounded and missing or denied objects stay absent',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          final paths = (jsonDecode(request.body) as Map)['paths'] as List;
          expect(paths.length, lessThanOrEqualTo(100));
          return http.Response(
            jsonEncode([
              for (final path in paths)
                if (path == 'missing')
                  {'path': path, 'error': 'not found', 'signedURL': null}
                else if (path == 'denied')
                  {'path': path, 'signedURL': ''}
                else
                  {
                    'path': path,
                    'signedURL': '/object/sign/photos/$path?token=test',
                  },
              {
                'path': 'not-requested',
                'signedURL': '/object/sign/photos/extra?token=test',
              },
            ]),
            200,
          );
        }),
      );
      final urls = await batchedSignedUrls(client, 'photos', [
        ...List.generate(201, (i) => 'photo-$i'),
        'missing',
        'denied',
      ]);
      expect(calls, 3);
      expect(urls, hasLength(201));
      expect(urls.containsKey('missing'), isFalse);
      expect(urls.containsKey('denied'), isFalse);
      expect(urls.containsKey('not-requested'), isFalse);
      await client.dispose();
    },
  );

  test(
    'empty input sends nothing; failed signing does not block the screen',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('{"message":"denied"}', 403);
        }),
      );
      expect(await batchedSignedUrls(client, 'avatars', ['', '  ']), isEmpty);
      expect(calls, 0);
      expect(await batchedSignedUrls(client, 'avatars', ['avatar']), isEmpty);
      expect(calls, 1);
      await client.dispose();
    },
  );
}
