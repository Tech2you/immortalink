import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'media_upload_policy.dart';

class OptimizedImageUpload {
  final Uint8List bytes;
  final String extension;
  final String contentType;
  final bool optimized;
  final int originalByteLength;

  const OptimizedImageUpload({
    required this.bytes,
    required this.extension,
    required this.contentType,
    required this.optimized,
    required this.originalByteLength,
  });
}

class ImageUploadOptimizer {
  static Future<OptimizedImageUpload> optimize(
    Uint8List originalBytes, {
    required MediaUploadKind kind,
    required String fileName,
    String? contentType,
  }) async {
    MediaUploadPolicy.validateUint8ListOrThrow(
      kind,
      originalBytes,
      fileName: fileName,
      contentType: contentType,
    );

    List<int> optimized;
    try {
      optimized = await FlutterImageCompress.compressWithList(
        originalBytes,
        minWidth: MediaUploadPolicy.imageMaxDimensionFor(kind),
        minHeight: MediaUploadPolicy.imageMaxDimensionFor(kind),
        quality: MediaUploadPolicy.imageQualityFor(kind),
        format: CompressFormat.jpeg,
        keepExif: false,
      );
    } catch (_) {
      optimized = const [];
    }

    final optimizedBytes = Uint8List.fromList(optimized);
    if (optimizedBytes.isEmpty ||
        optimizedBytes.length >= originalBytes.length) {
      return OptimizedImageUpload(
        bytes: originalBytes,
        extension: MediaUploadPolicy.extensionForName(
          fileName,
          fallback: 'jpg',
        ),
        contentType: MediaUploadPolicy.contentTypeForExtension(
          MediaUploadPolicy.extensionForName(fileName, fallback: 'jpg'),
        ),
        optimized: false,
        originalByteLength: originalBytes.length,
      );
    }

    MediaUploadPolicy.validateUint8ListOrThrow(
      kind,
      optimizedBytes,
      fileName: 'optimized.jpg',
      contentType: 'image/jpeg',
    );

    return OptimizedImageUpload(
      bytes: optimizedBytes,
      extension: 'jpg',
      contentType: 'image/jpeg',
      optimized: true,
      originalByteLength: originalBytes.length,
    );
  }
}
