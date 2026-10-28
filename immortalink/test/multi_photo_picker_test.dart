import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:immortalink/utils/media_upload_policy.dart';
import 'package:immortalink/utils/vault_media_upload.dart';

class FakePhotoPicker extends ImagePickerPlatform {
  MultiImagePickerOptions? options;
  ImagePickerOptions? singleOptions;
  final files = <XFile>[];
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    this.options = options;
    return files;
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    singleOptions = options;
    return files.isEmpty ? null : files.first;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all 20 are read in order, without truncation', () async {
    final files = List.generate(
      20,
      (i) =>
          PlatformFile(name: '$i.jpg', size: 1, readStream: Stream.value([i])),
    );
    final result = await readVaultMediaFiles(files);
    expect(result.files, hasLength(20));
    expect(
      result.files.map((f) => f.bytes!.single),
      orderedEquals(List.generate(20, (i) => i)),
    );
  });
  test('21 rejected before reading any file', () async {
    var reads = 0;
    Stream<List<int>> stream() async* {
      reads++;
      yield [1];
    }

    final files = List.generate(
      21,
      (i) => PlatformFile(name: '$i.jpg', size: 1, readStream: stream()),
    );
    await expectLater(
      readVaultMediaFiles(files),
      throwsA(isA<MediaUploadException>()),
    );
    expect(reads, 0);
  });
  test('remaining count and aggregate bytes rejected before reads', () async {
    var reads = 0;
    Stream<List<int>> stream() async* {
      reads++;
      yield [1];
    }

    final files = List.generate(
      20,
      (i) => PlatformFile(
        name: '$i.jpg',
        size: 6 * 1024 * 1024,
        readStream: stream(),
      ),
    );
    await expectLater(
      readVaultMediaFiles(files),
      throwsA(isA<MediaUploadException>()),
    );
    await expectLater(
      readVaultMediaFiles(files.take(2).toList(), maxFiles: 1),
      throwsA(isA<MediaUploadException>()),
    );
    expect(reads, 0);
  });
  test('actual stream length cannot bypass remaining bytes', () async {
    final files = [
      PlatformFile(name: 'a.jpg', size: 1, readStream: Stream.value([1, 2, 3])),
    ];
    await expectLater(
      readVaultMediaFiles(files, remainingBytes: 2),
      throwsA(isA<MediaUploadException>()),
    );
  });
  for (final limit in [20, 4, 1]) {
    testWidgets('iPhone native picker receives remaining limit $limit', (
      tester,
    ) async {
      final oldPlatform = ImagePickerPlatform.instance;
      final picker = FakePhotoPicker();
      picker.files.add(
        XFile.fromData(Uint8List.fromList([1, 2]), path: 'a.jpg'),
      );
      ImagePickerPlatform.instance = picker;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        ImagePickerPlatform.instance = oldPlatform;
        debugDefaultTargetPlatformOverride = null;
      });
      FilePickerResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await pickVaultMedia(
                  context,
                  allowMultiple: true,
                  maxFiles: limit,
                );
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      if (limit == 1) {
        expect(picker.singleOptions?.requestFullMetadata, isFalse);
      } else {
        expect(picker.options?.limit, limit);
        expect(picker.options?.imageOptions.requestFullMetadata, isFalse);
      }
      expect(result?.files.single.name, 'a.jpg');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
