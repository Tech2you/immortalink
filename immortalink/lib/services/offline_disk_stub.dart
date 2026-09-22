import 'dart:typed_data';

class OfflineDisk {
  Future<Uint8List?> read(String key) async => null;
  Future<void> write(String key, List<int> bytes) async {}
  Future<void> remove(String key) async {}
  Future<void> clear() async {}
}
