import 'dart:typed_data';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/offline_disk.dart';
import 'package:immortalink/services/recent_cache.dart';

class MemoryDisk extends OfflineDisk {
  final files = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => files[key];
  @override
  Future<void> write(String key, List<int> bytes) async {
    files[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    files.remove(key);
  }

  @override
  Future<void> clear() async {
    files.clear();
  }
}

class PausedDisk extends MemoryDisk {
  final writing = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> write(String key, List<int> bytes) async {
    if (key != 'index') {
      writing.complete();
      await resume.future;
    }
    await super.write(key, bytes);
  }
}

void main() {
  test(
    'switching accounts during a disk write cannot retain old bytes',
    () async {
      final disk = PausedDisk();
      final cache = RecentCache(disk: disk);
      await cache.setUser('a');
      final put = cache.put(
        'late',
        [1, 2],
        epoch: cache.generation,
        kind: 'photo',
      );
      await disk.writing.future;
      final switchUser = cache.setUser('b');
      disk.resume.complete();
      await put;
      await switchUser;
      expect(await cache.read('late'), isNull);
      expect(disk.files.keys.where((key) => key != 'index'), isEmpty);
    },
  );
  late MemoryDisk disk;
  late RecentCache cache;
  late DateTime now;
  setUp(() async {
    disk = MemoryDisk();
    now = DateTime(2026);
    cache = RecentCache(disk: disk, maxBytes: 10, clock: () => now);
    await cache.setUser('a');
  });
  Future<void> put(String key, int size) => cache.put(
    key,
    List.filled(size, 1),
    epoch: cache.generation,
    kind: 'photo',
  );
  test('signed URLs have stable keys without storing tokens', () {
    expect(
      cache.photoKey('https://example.com/avatar?token=a&t=123'),
      cache.photoKey('https://example.com/avatar?token=b&t=456'),
    );
    expect(
      cache.photoKey('https://example.com/p?token=secret'),
      cache.photoKey('https://example.com/p?token=other'),
    );
    expect(
      cache.photoKey('https://example.com/p?token=secret'),
      isNot(contains('secret')),
    );
  });
  test('least recently used entries are evicted', () async {
    await put('a', 4);
    now = now.add(const Duration(seconds: 1));
    await put('b', 4);
    now = now.add(const Duration(seconds: 1));
    await cache.read('a');
    now = now.add(const Duration(seconds: 1));
    await put('c', 4);
    expect(await cache.read('b'), isNull);
    expect(await cache.read('a'), isNotNull);
    expect((await cache.list()).length, 2);
  });
  test('old timestamp variants consolidate without extending expiry', () async {
    await put('photo:https://example.com/p?t=1', 2);
    now = now.add(const Duration(minutes: 1));
    await put('photo:https://example.com/p?t=2', 3);
    await put('photo:https://example.com/p?width=80', 2);
    now = now.add(const Duration(hours: 5));
    final entries = await cache.list();
    expect(entries.length, 2);
    expect(
      (await cache.read(cache.photoKey('https://example.com/p')))?.length,
      3,
    );
    expect(disk.files.length, 3); // Two files and the index.
    now = now.add(const Duration(hours: 1));
    expect(await cache.list(), isEmpty);
  });
  test('expiry does not extend when a cached item is viewed', () async {
    await put('a', 4);
    now = now.add(const Duration(hours: 5));
    expect(await cache.read('a'), isNotNull);
    now = now.add(const Duration(hours: 1));
    expect(await cache.read('a'), isNull);
  });
  test('same account survives restart but switching destroys copies', () async {
    await put('a', 4);
    final same = RecentCache(disk: disk, clock: () => now);
    await same.setUser('a');
    expect(await same.read('a'), isNotNull);
    await cache.setUser('b');
    expect(await cache.read('a'), isNull);
    await cache.setUser('a');
    expect(await cache.read('a'), isNull);
  });
  test('clear rejects old downloads and signout clears files', () async {
    final epoch = cache.generation;
    await put('a', 4);
    await cache.clear();
    await cache.put('late', [1], epoch: epoch, kind: 'photo');
    expect(await cache.list(), isEmpty);
    await put('a', 4);
    await cache.setUser(null);
    expect(disk.files, isEmpty);
  });
  test('oversized entries do not evict valid photos', () async {
    await put('a', 4);
    await put('huge', 11);
    expect(await cache.read('a'), isNotNull);
    expect(await cache.read('huge'), isNull);
  });
  test('corrupted manifest is discarded', () async {
    disk.files['index'] = Uint8List.fromList([0, 1]);
    final fresh = RecentCache(disk: disk);
    await fresh.setUser('a');
    expect(await fresh.list(), isEmpty);
  });
}
