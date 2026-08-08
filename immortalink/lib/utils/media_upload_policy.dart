import 'dart:typed_data';

enum MediaUploadKind { avatarPhoto, photo, voice }

class MediaUploadException implements Exception {
  final String message;

  const MediaUploadException(this.message);

  @override
  String toString() => message;
}

class MediaUploadPolicy {
  static const int avatarPhotoMaxBytes = 5 * 1024 * 1024;
  static const int photoMaxBytes = 12 * 1024 * 1024;
  static const int voiceMaxBytes = 25 * 1024 * 1024;

  static const Set<String> imageMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };

  static const Set<String> voiceMimeTypes = {
    'audio/aac',
    'audio/mp4',
    'audio/m4a',
    'audio/mpeg',
    'audio/ogg',
    'audio/wav',
    'audio/webm',
    'audio/x-m4a',
  };

  static int maxBytesFor(MediaUploadKind kind) => switch (kind) {
    MediaUploadKind.avatarPhoto => avatarPhotoMaxBytes,
    MediaUploadKind.photo => photoMaxBytes,
    MediaUploadKind.voice => voiceMaxBytes,
  };

  static String labelFor(MediaUploadKind kind) => switch (kind) {
    MediaUploadKind.avatarPhoto => 'profile photo',
    MediaUploadKind.photo => 'photo',
    MediaUploadKind.voice => 'voice note',
  };

  static String extensionForName(String name, {String fallback = 'bin'}) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpeg')) return 'jpg';
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return fallback;
    return lower.substring(dot + 1);
  }

  static String contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'webm':
        return 'audio/webm';
      default:
        return 'application/octet-stream';
    }
  }

  static String? validateBytes(
    MediaUploadKind kind,
    int byteLength, {
    String? fileName,
    String? contentType,
  }) {
    final maxBytes = maxBytesFor(kind);
    if (byteLength > maxBytes) {
      return 'This ${labelFor(kind)} is ${_formatBytes(byteLength)}, but the limit is ${_formatBytes(maxBytes)}. Please choose a smaller file.';
    }

    final normalizedContentType = contentType?.trim().toLowerCase();
    final extension = fileName == null ? '' : extensionForName(fileName);
    final inferredType = extension.isEmpty
        ? ''
        : contentTypeForExtension(extension).toLowerCase();
    final type =
        (normalizedContentType == null ||
            normalizedContentType.isEmpty ||
            normalizedContentType == 'application/octet-stream')
        ? inferredType
        : normalizedContentType;

    if (kind == MediaUploadKind.avatarPhoto || kind == MediaUploadKind.photo) {
      if (type.isNotEmpty && !imageMimeTypes.contains(type)) {
        return 'That file type is not supported for photos. Please choose a JPEG, PNG, WebP, HEIC, or HEIF image.';
      }
    }

    if (kind == MediaUploadKind.voice) {
      if (type.isNotEmpty && !voiceMimeTypes.contains(type)) {
        return 'That file type is not supported for voice notes. Please choose M4A, MP3, WAV, AAC, OGG, or WebM audio.';
      }
    }

    return null;
  }

  static void validateBytesOrThrow(
    MediaUploadKind kind,
    int byteLength, {
    String? fileName,
    String? contentType,
  }) {
    final error = validateBytes(
      kind,
      byteLength,
      fileName: fileName,
      contentType: contentType,
    );
    if (error != null) throw MediaUploadException(error);
  }

  static void validateListOrThrow(
    MediaUploadKind kind,
    List<int> bytes, {
    String? fileName,
    String? contentType,
  }) {
    validateBytesOrThrow(
      kind,
      bytes.length,
      fileName: fileName,
      contentType: contentType,
    );
  }

  static void validateUint8ListOrThrow(
    MediaUploadKind kind,
    Uint8List bytes, {
    String? fileName,
    String? contentType,
  }) {
    validateBytesOrThrow(
      kind,
      bytes.length,
      fileName: fileName,
      contentType: contentType,
    );
  }

  static String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
}
