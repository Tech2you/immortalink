import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'offline_disk.dart';

/// Device-private, disposable cache. Never used to authorize an online action.
class RecentCache extends ChangeNotifier {
  RecentCache({
    OfflineDisk? disk,
    this.maxBytes = 250 * 1024 * 1024,
    this.maxAge = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _disk = disk ?? OfflineDisk(),
       _clock = clock ?? DateTime.now;
  static final instance = RecentCache();
  final OfflineDisk _disk;
  final int maxBytes;
  final Duration maxAge;
  final DateTime Function() _clock;
  String? _user;
  int generation = 0;
  Future<void> _queue = Future.value();
  Map<String, Map<String, dynamic>> _entries = {};
  String? get user => _user;
  bool get supported => !kIsWeb;

  String photoKey(String url) {
    final uri = Uri.parse(url);
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('token')
      ..remove('t'); // App-generated refresh timestamp, not image identity.
    return 'photo:${uri.replace(queryParameters: query, fragment: '')}';
  }

  String _file(String key) => sha256.convert(utf8.encode(key)).toString();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> setUser(String? user) {
    if (_user == user && user != null) return _queue;
    final switching = _user != null;
    _user = user;
    final epoch = ++generation;
    _entries = {};
    final pending = _serial(() async {
      try {
        final bytes = await _disk.read('index');
        final data = bytes == null ? null : jsonDecode(utf8.decode(bytes));
        if (switching || user == null || data?['user'] != user) {
          await _disk.clear();
        } else if (epoch == generation) {
          _entries = (data['entries'] as Map).map(
            (key, value) => MapEntry(
              key.toString(),
              Map<String, dynamic>.from(value as Map),
            ),
          );
          await _prune();
          await _normalizePhotoEntries();
        }
      } catch (_) {
        try {
          await _disk.clear();
        } catch (_) {}
      }
    });
    notifyListeners();
    return pending;
  }

  Future<void> _saveIndex() => _disk.write(
    'index',
    utf8.encode(jsonEncode({'user': _user, 'entries': _entries})),
  );

  Future<void> _prune() async {
    final epoch = generation;
    final now = _clock().millisecondsSinceEpoch;
    for (final key in _entries.keys.toList()) {
      if (epoch != generation) return;
      final saved = _entries[key]!['saved'] as int;
      if (now < saved || now - saved >= maxAge.inMilliseconds) {
        await _disk.remove(_file(key));
        if (epoch != generation) return;
        _entries.remove(key);
      }
    }
    var size = _entries.values.fold<int>(
      0,
      (sum, e) => sum + (e['size'] as int),
    );
    final oldest = _entries.keys.toList()
      ..sort(
        (a, b) => (_entries[a]!['used'] as int).compareTo(
          _entries[b]!['used'] as int,
        ),
      );
    while ((size > maxBytes || _entries.length > 1000) && oldest.isNotEmpty) {
      final key = oldest.removeAt(0);
      size -= _entries.remove(key)!['size'] as int;
      await _disk.remove(_file(key));
      if (epoch != generation) return;
    }
    await _saveIndex();
  }

  Future<void> _normalizePhotoEntries() async {
    final epoch = generation;
    final groups = <String, List<String>>{};
    for (final entry in _entries.entries) {
      if (entry.value['kind'] != 'photo' || !entry.key.startsWith('photo:')) {
        continue;
      }
      final canonical = photoKey(entry.key.substring(6));
      groups.putIfAbsent(canonical, () => []).add(entry.key);
    }
    for (final group in groups.entries) {
      if (epoch != generation) return;
      if (group.value.length == 1 && group.value.single == group.key) continue;
      final keys = group.value
        ..sort(
          (a, b) => (_entries[b]!['saved'] as int).compareTo(
            _entries[a]!['saved'] as int,
          ),
        );
      String? chosen;
      Uint8List? bytes;
      for (final key in keys) {
        bytes = await _disk.read(_file(key));
        if (epoch != generation) return;
        if (bytes != null) {
          chosen = key;
          break;
        }
      }
      if (chosen == null || bytes == null) {
        for (final key in keys) {
          _entries.remove(key);
        }
        continue;
      }
      final metadata = Map<String, dynamic>.from(_entries[chosen]!);
      await _disk.write(_file(group.key), bytes);
      if (epoch != generation) return;
      _entries[group.key] =
          metadata; // Preserve original age; migration is not a fetch.
      for (final key in keys.where((key) => key != group.key)) {
        await _disk.remove(_file(key));
        if (epoch != generation) return;
        _entries.remove(key);
      }
    }
    await _saveIndex();
  }

  Future<void> put(
    String key,
    List<int> bytes, {
    required int epoch,
    required String kind,
    String? title,
    String? familyId,
  }) => _serial(() async {
    if (_user == null || epoch != generation || bytes.length > maxBytes) return;
    try {
      await _disk.write(_file(key), bytes);
      if (epoch != generation) return;
      final now = _clock().millisecondsSinceEpoch;
      _entries[key] = {
        'size': bytes.length,
        'saved': now,
        'used': now,
        'kind': kind,
        'title': title,
        'familyId': familyId,
      };
      await _prune();
    } catch (_) {
      /* A full device must not break online viewing. */
    }
  });

  Future<Uint8List?> read(String key) {
    final epoch = generation;
    return _serial(() async {
      if (_user == null || epoch != generation) return null;
      try {
        await _prune();
        if (epoch != generation) return null;
        final entry = _entries[key];
        if (entry == null) return null;
        final bytes = await _disk.read(_file(key));
        if (epoch != generation) return null;
        entry['used'] = _clock().millisecondsSinceEpoch;
        await _saveIndex();
        return epoch == generation ? bytes : null;
      } catch (_) {
        return null;
      }
    });
  }

  Future<List<Map<String, dynamic>>> list() {
    final epoch = generation;
    return _serial(() async {
      if (_user == null || epoch != generation) return [];
      try {
        await _prune();
        await _normalizePhotoEntries();
      } catch (_) {
        return [];
      }
      if (epoch != generation) return [];
      return _entries.entries.map((e) => {'key': e.key, ...e.value}).toList()
        ..sort((a, b) => (b['used'] as int).compareTo(a['used'] as int));
    });
  }

  Future<void> remove(String key) {
    final epoch = generation;
    return _serial(() async {
      if (epoch != generation) return;
      _entries.remove(key);
      try {
        await _disk.remove(_file(key));
        await _saveIndex();
      } catch (_) {}
    });
  }

  Future<void> clear() {
    ++generation; // In-flight downloads may not repopulate a cleared cache.
    _entries = {};
    final pending = _serial(() async {
      try {
        await _disk.clear();
      } catch (_) {}
    });
    notifyListeners();
    return pending;
  }
}
