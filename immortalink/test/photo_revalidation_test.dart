import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'package:immortalink/widgets/recent_photo.dart';

import 'recent_cache_test.dart' show MemoryDisk, PausedDisk;

void main() {
  const url = 'https://example.com/photo.jpg?token=old';
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
      entityTag: '"original"',
    );
    return cache;
  }

  Widget photo(
    RecentCache cache,
    Future<http.Response> Function(http.Request) get,
  ) => MaterialApp(
    home: RecentPhoto(
      'https://example.com/photo.jpg?token=renewed&t=123',
      cache: cache,
      clientFactory: () => MockClient(get),
    ),
  );
  Future<void> decoded(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renewed URL reuses bytes only after server confirms unchanged', (
    tester,
  ) async {
    final cache = await seed();
    final pending = Completer<http.Response>();
    http.Request? received;
    await tester.pumpWidget(
      photo(cache, (request) {
        received = request;
        return pending.future;
      }),
    );
    await tester.pump();
    expect(received?.headers['If-None-Match'], '"original"');
    expect(find.byType(Image), findsNothing); // Not a blind cache-first render.
    pending.complete(http.Response('', 304));
    await decoded(tester);
    expect(find.byType(Image), findsOneWidget);
    final provider =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    expect(provider.bytes, png);
    expect(find.bySemanticsLabel('Cached photo, offline copy'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changed server photo replaces both bytes and validator', (
    tester,
  ) async {
    final cache = await seed();
    // PNG permits trailing bytes; use a different valid response body.
    final changed = Uint8List.fromList([...png, 0, 1]);
    await tester.pumpWidget(
      photo(
        cache,
        (_) async =>
            http.Response.bytes(changed, 200, headers: {'etag': '"changed"'}),
      ),
    );
    await decoded(tester);
    final entry = await cache.readEntry(cache.photoKey(url));
    expect(entry?.bytes, changed);
    expect(entry?.entityTag, '"changed"');
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final status in [401, 403, 404, 410]) {
    testWidgets(
      'access/deletion response $status rejects a validated cache entry',
      (tester) async {
        final cache = await seed();
        await tester.pumpWidget(
          photo(cache, (_) async => http.Response('', status)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        expect(await cache.readEntry(cache.photoKey(url)), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('account switch discards an in-flight 304 and its bytes', (
    tester,
  ) async {
    final cache = await seed();
    final pending = Completer<http.Response>();
    await tester.pumpWidget(photo(cache, (_) => pending.future));
    await tester.pump();
    await cache.setUser('b');
    pending.complete(http.Response('', 304));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(await cache.readEntry(cache.photoKey(url)), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unexpected 304 without bytes retries a normal download once', (
    tester,
  ) async {
    final cache = RecentCache(disk: MemoryDisk());
    await cache.setUser('a');
    var requests = 0;
    await tester.pumpWidget(
      photo(cache, (request) async {
        expect(request.headers['If-None-Match'], isNull);
        return ++requests == 1
            ? http.Response('', 304)
            : http.Response.bytes(png, 200, headers: {'etag': '"new"'});
      }),
    );
    await decoded(tester);
    expect(requests, 2);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'slow cache persistence does not hold a downloaded photo offscreen',
    (tester) async {
      final disk = PausedDisk();
      final cache = RecentCache(disk: disk);
      await cache.setUser('a');
      await tester.pumpWidget(
        photo(cache, (_) async => http.Response.bytes(png, 200)),
      );
      await decoded(tester);
      expect(disk.writing.isCompleted, isTrue);
      expect(disk.resume.isCompleted, isFalse);
      expect(find.byType(Image), findsOneWidget);
      disk.resume.complete();
      await cache.clear();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'expired entries do not supply a validator; legacy entries still read',
    () async {
      var now = DateTime.utc(2026, 11, 1);
      final cache = RecentCache(disk: MemoryDisk(), clock: () => now);
      await cache.setUser('a');
      await cache.put('old', png, epoch: cache.generation, kind: 'photo');
      expect((await cache.readEntry('old'))?.entityTag, isNull);
      expect(await cache.read('old'), png);
      await cache.put(
        'new',
        png,
        epoch: cache.generation,
        kind: 'photo',
        entityTag: '"new"',
      );
      now = now.add(const Duration(hours: 6));
      expect(await cache.readEntry('new'), isNull);
    },
  );
}
