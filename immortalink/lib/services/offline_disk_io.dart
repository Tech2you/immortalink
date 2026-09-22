import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class OfflineDisk {
  Future<Directory> _directory() async => Directory(
    '${(await getApplicationCacheDirectory()).path}/ever_roots_recent_v1',
  );

  Future<Uint8List?> read(String key) async {
    final file = File('${(await _directory()).path}/$key');
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> write(String key, List<int> bytes) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final temporary = File('${dir.path}/$key.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename('${dir.path}/$key');
  }

  Future<void> remove(String key) async {
    final file = File('${(await _directory()).path}/$key');
    if (await file.exists()) await file.delete();
  }

  Future<void> clear() async {
    final dir = await _directory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
