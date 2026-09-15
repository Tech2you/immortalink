import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'image_upload_optimizer.dart';
import 'media_upload_policy.dart';

Future<FilePickerResult?> pickVaultMedia(
  BuildContext context, {
  bool allowMultiple = false,
  int remainingBytes = MediaUploadPolicy.pendingMediaMaxBytes,
}) async {
  final type = await showModalBottomSheet<FileType>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photos'),
            onTap: () => Navigator.pop(sheetContext, FileType.image),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Videos'),
            onTap: () => Navigator.pop(sheetContext, FileType.video),
          ),
        ],
      ),
    ),
  );
  if (type == null) return null;
  final result = await FilePicker.platform.pickFiles(
    type: type,
    // Read only after checking sizes, rather than loading every selected video.
    withData: false,
    withReadStream: true,
    allowMultiple: allowMultiple && type == FileType.image,
  );
  if (result == null) return null;
  return readVaultMediaFiles(result.files, remainingBytes: remainingBytes);
}

Future<FilePickerResult> readVaultMediaFiles(
  List<PlatformFile> selected, {
  int remainingBytes = MediaUploadPolicy.pendingMediaMaxBytes,
}) async {
  final files = <PlatformFile>[];
  var used = 0;
  for (final file in selected.take(10)) {
    final kind = MediaUploadPolicy.visualKind(file.name);
    MediaUploadPolicy.validateBytesOrThrow(
      kind,
      file.size,
      fileName: file.name,
    );
    if (used + file.size > remainingBytes) {
      throw const MediaUploadException(
        'Selected media exceeds the 100 MB draft limit. Add fewer files.',
      );
    }
    final builder = BytesBuilder(copy: false);
    final stream = file.readStream;
    if (stream != null) {
      await for (final chunk in stream) {
        if (builder.length + chunk.length >
                MediaUploadPolicy.maxBytesFor(kind) ||
            used + builder.length + chunk.length > remainingBytes) {
          throw const MediaUploadException(
            'This file is too large. Choose a smaller file.',
          );
        }
        builder.add(chunk);
      }
    } else {
      builder.add(file.bytes ?? await file.xFile.readAsBytes());
    }
    final bytes = builder.takeBytes();
    MediaUploadPolicy.validateBytesOrThrow(
      kind,
      bytes.length,
      fileName: file.name,
    );
    used += bytes.length;
    if (used > remainingBytes) {
      throw const MediaUploadException(
        'Selected media exceeds the 100 MB draft limit.',
      );
    }
    files.add(PlatformFile(name: file.name, size: bytes.length, bytes: bytes));
  }
  return FilePickerResult(files);
}

class VaultMediaUpload {
  static Future<OptimizedImageUpload> prepare(
    Uint8List bytes, {
    required String fileName,
    String? contentType,
  }) async {
    final kind = MediaUploadPolicy.visualKind(fileName);
    if (kind == MediaUploadKind.photo) {
      return ImageUploadOptimizer.optimize(
        bytes,
        kind: kind,
        fileName: fileName,
        contentType: contentType,
      );
    }
    final extension = MediaUploadPolicy.extensionForName(fileName);
    final mime = MediaUploadPolicy.contentTypeForExtension(extension);
    MediaUploadPolicy.validateUint8ListOrThrow(
      kind,
      bytes,
      fileName: fileName,
      contentType: mime,
    );
    // MP4/MOV/M4V are ISO base media containers. Reject renamed arbitrary files.
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
      throw const MediaUploadException(
        'This video format is not supported. Export it as MP4 or MOV and try again.',
      );
    }
    return OptimizedImageUpload(
      bytes: bytes,
      extension: extension,
      contentType: mime,
      optimized: false,
      originalByteLength: bytes.length,
    );
  }
}
