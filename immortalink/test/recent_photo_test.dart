import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/recent_photo.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  const url = 'https://example.com/photo?token=test';
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  Future<RecentCache> seed() async {
    final cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('a');
    await cache.put(
      cache.photoKey(url),
      png,
      epoch: cache.generation,
      kind: 'photo',
    );
    return cache;
  }

  testWidgets('snapshot photos use local bytes without a network request', (tester) async {
    final cache = await seed();
    var requests = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecentPhoto(url, cache: cache, cachedOnly: true,
      clientFactory: () => MockClient((_) async { requests++; return http.Response('', 403); })))));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'network failure uses a labelled cached photo, cleared on signout',
    (tester) async {
      final cache = await seed();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentPhoto(
              url,
              width: 200,
              height: 200,
              cache: cache,
              clientFactory: () => MockClient(
                (_) async => throw http.ClientException('offline'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline copy'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      await cache.setUser(null);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('permission denied never displays the cached photo', (
    tester,
  ) async {
    final cache = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentPhoto(
            url,
            cache: cache,
            clientFactory: () =>
                MockClient((_) async => http.Response('', 403)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(await cache.read(cache.photoKey(url)), isNull);
  });
  testWidgets('successful online viewing saves a valid photo', (tester) async {
    final cache = await seed();
    await cache.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentPhoto(
            url,
            cache: cache,
            clientFactory: () =>
                MockClient((_) async => http.Response.bytes(png, 200)),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(await cache.read(cache.photoKey(url)), isNotNull);
    expect(find.text('Offline copy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
