import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/everroot_upgrade_prompt.dart';
import '../utils/media_upload_policy.dart';
import '../utils/public_error.dart';
import '../utils/vault_media_upload.dart';

Future<List<PendingMemoryMedia>> prepareMemoryMedia(
  List<PlatformFile> files,
) async {
  final media = <PendingMemoryMedia>[];
  for (final file in files) {
    final bytes = file.bytes;
    if (bytes == null) {
      throw const MediaUploadException(
        'This photo could not be read. Select it again.',
      );
    }
    final prepared = await VaultMediaUpload.prepare(bytes, fileName: file.name);
    media.add(
      PendingMemoryMedia(
        name: file.name,
        bytes: prepared.bytes,
        extension: prepared.extension,
        contentType: prepared.contentType,
      ),
    );
  }
  return media;
}

class PendingMemoryMedia {
  const PendingMemoryMedia({
    required this.name,
    required this.bytes,
    required this.extension,
    required this.contentType,
  });
  final String name;
  final Uint8List bytes;
  final String extension;
  final String contentType;
}

class MemoryMediaTarget {
  MemoryMediaTarget.personal({
    required String vaultId,
    required String memoryId,
  }) : bucket = 'memory_photos',
       table = 'memory_photos',
       folder = '$vaultId/memories/$memoryId',
       values = {'vault_id': vaultId, 'memory_id': memoryId};
  MemoryMediaTarget.legacy({
    required String familyId,
    required String memberId,
    required String memoryId,
  }) : bucket = 'vault_photos',
       table = 'legacy_memory_photos',
       folder = '$familyId/legacy/$memberId/memories/$memoryId',
       values = {
         'family_id': familyId,
         'legacy_member_id': memberId,
         'legacy_memory_id': memoryId,
       };
  final String bucket, table, folder;
  final Map<String, String> values;
}

class MemoryMediaItem {
  MemoryMediaItem(this.media, this.path);
  final PendingMemoryMedia media;
  final String path;
  bool uploaded = false;
  bool saved = false;
  bool attempted = false;
  bool linkingAttempted = false;
  bool busy = false;
  Object? error;
}

/// One session-scoped sequential queue. Paths survive retries, never overwrites.
class MemoryMediaBatch {
  MemoryMediaBatch({
    required this.client,
    required this.target,
    required List<PendingMemoryMedia> media,
  }) : userId = client.auth.currentUser?.id ?? '' {
    if (userId.isEmpty) throw const AuthException('Please sign in again.');
    if (media.isEmpty || media.length > MediaUploadPolicy.photoBatchMaxCount) {
      throw const MediaUploadException('Select between 1 and 20 photos.');
    }
    if (media.fold<int>(0, (sum, file) => sum + file.bytes.length) >
        MediaUploadPolicy.pendingMediaMaxBytes) {
      throw const MediaUploadException(
        'Selected media exceeds the 100 MB draft limit.',
      );
    }
    final random = Random.secure();
    final batchId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    for (var index = 0; index < media.length; index++) {
      final file = media[index];
      if (MediaUploadPolicy.contentTypeForExtension(file.extension) !=
          file.contentType) {
        throw const MediaUploadException('Unsupported media format.');
      }
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadPolicy.visualKind(file.name),
        file.bytes,
        fileName: file.name,
        contentType: file.contentType,
      );
      items.add(
        MemoryMediaItem(
          file,
          '$userId/${target.folder}/${batchId}_$index.${file.extension}',
        ),
      );
    }
  }
  final SupabaseClient client;
  final MemoryMediaTarget target;
  final String userId;
  final List<MemoryMediaItem> items = [];
  bool running = false;
  bool started = false;
  bool _stop = false;
  int get savedCount => items.where((item) => item.saved).length;
  bool get complete => items.isNotEmpty && items.every((item) => item.saved);
  bool get sameAccount => client.auth.currentUser?.id == userId;
  void pause() => _stop = true;
  void removeAt(int index) {
    if (!started && !running) items.removeAt(index);
  }

  void _checkAccount() {
    if (!sameAccount) {
      throw const AuthException('Account changed. Reopen this memory.');
    }
  }

  Future<void> upload({void Function()? onChanged}) async {
    if (running || items.isEmpty) return;
    running = true;
    started = true;
    _stop = false;
    onChanged?.call();
    try {
      for (final item in items) {
        if (_stop) break;
        if (item.saved) continue;
        item.busy = true;
        item.error = null;
        onChanged?.call();
        try {
          _checkAccount();
          // An interrupted response may have already committed the row.
          if (item.linkingAttempted) {
            final existing = await client.from(target.table).select('id').match(
              {...target.values, 'path': item.path},
            ).maybeSingle();
            _checkAccount();
            if (existing != null) {
              item.saved = true;
              continue;
            }
          }
          if (!item.uploaded) {
            final retry = item.attempted;
            item.attempted = true;
            try {
              await client.storage
                  .from(target.bucket)
                  .uploadBinary(
                    item.path,
                    item.media.bytes,
                    fileOptions: FileOptions(
                      upsert: false,
                      contentType: item.media.contentType,
                    ),
                    retryAttempts: 0,
                  );
            } on StorageException catch (e) {
              // Only our previously attempted random path may already exist.
              if (!retry ||
                  !(e.statusCode == '409' || e.error == 'Duplicate')) {
                rethrow;
              }
            }
            _checkAccount();
            item.uploaded = true;
          }
          item.linkingAttempted = true;
          await client.from(target.table).insert({
            ...target.values,
            'path': item.path,
          });
          _checkAccount();
          item.saved = true;
        } catch (e) {
          item.error = e;
          if (!sameAccount ||
              e is AuthException ||
              isConnectionFailure(e) ||
              isEverRootQuotaError(e) ||
              (e is PostgrestException && e.code == '42501') ||
              (e is StorageException &&
                  const ['401', '403'].contains(e.statusCode))) {
            _stop = true;
          }
        } finally {
          item.busy = false;
          onChanged?.call();
        }
      }
    } finally {
      running = false;
      onChanged?.call();
    }
  }
}
