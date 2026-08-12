import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/media_upload_policy.dart';

void main() {
  group('MediaUploadPolicy', () {
    test('accepts files at or under each configured size limit', () {
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.avatarPhoto,
          MediaUploadPolicy.avatarPhotoMaxBytes - 1,
          fileName: 'avatar.jpg',
          contentType: 'image/jpeg',
        ),
        isNull,
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.avatarPhoto,
          MediaUploadPolicy.avatarPhotoMaxBytes,
          fileName: 'avatar.jpg',
          contentType: 'image/jpeg',
        ),
        isNull,
      );

      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.photo,
          MediaUploadPolicy.photoMaxBytes - 1,
          fileName: 'memory.webp',
          contentType: 'image/webp',
        ),
        isNull,
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.photo,
          MediaUploadPolicy.photoMaxBytes,
          fileName: 'memory.webp',
          contentType: 'image/webp',
        ),
        isNull,
      );

      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.voice,
          MediaUploadPolicy.voiceMaxBytes - 1,
          fileName: 'voice.m4a',
          contentType: 'audio/mp4',
        ),
        isNull,
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.voice,
          MediaUploadPolicy.voiceMaxBytes,
          fileName: 'voice.m4a',
          contentType: 'audio/mp4',
        ),
        isNull,
      );
    });

    test('rejects files over each configured size limit', () {
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.avatarPhoto,
          MediaUploadPolicy.avatarPhotoMaxBytes + 1,
          fileName: 'avatar.jpg',
          contentType: 'image/jpeg',
        ),
        contains('limit is 5.0 MB'),
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.photo,
          MediaUploadPolicy.photoMaxBytes + 1,
          fileName: 'memory.jpg',
          contentType: 'image/jpeg',
        ),
        contains('limit is 12 MB'),
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.voice,
          MediaUploadPolicy.voiceMaxBytes + 1,
          fileName: 'voice.m4a',
          contentType: 'audio/mp4',
        ),
        contains('limit is 25 MB'),
      );
    });

    test('rejects invalid declared MIME types', () {
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.photo,
          1024,
          fileName: 'memory.txt',
          contentType: 'text/plain',
        ),
        contains('not supported for photos'),
      );
      expect(
        MediaUploadPolicy.validateBytes(
          MediaUploadKind.voice,
          1024,
          fileName: 'voice.txt',
          contentType: 'text/plain',
        ),
        contains('not supported for voice notes'),
      );
    });

    test(
      'infers MIME type from extension when a picker returns octet-stream',
      () {
        expect(
          MediaUploadPolicy.validateBytes(
            MediaUploadKind.photo,
            1024,
            fileName: 'memory.heic',
            contentType: 'application/octet-stream',
          ),
          isNull,
        );
        expect(
          MediaUploadPolicy.validateBytes(
            MediaUploadKind.voice,
            1024,
            fileName: 'voice.mp3',
            contentType: 'application/octet-stream',
          ),
          isNull,
        );
      },
    );
  });
}
