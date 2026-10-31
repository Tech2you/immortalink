import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:immortalink/utils/media_upload_policy.dart';
import 'package:immortalink/utils/vault_media_upload.dart';
import 'package:immortalink/widgets/memory_creation_menu.dart';
import 'multi_photo_picker_test.dart' show FakePhotoPicker;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePhotoPicker picker;
  late ImagePickerPlatform previous;
  setUp(() {
    previous = ImagePickerPlatform.instance;
    picker = FakePhotoPicker();
    ImagePickerPlatform.instance = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    ImagePickerPlatform.instance = previous;
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> openPicker(
    WidgetTester tester, {
    bool allowCamera = false,
    ValueChanged<FilePickerResult?>? selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected?.call(
                  await pickVaultMedia(
                    context,
                    allowCamera: allowCamera,
                    allowMultiple: true,
                  ),
                );
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
  }

  testWidgets('existing-memory default keeps camera out of the picker', (
    tester,
  ) async {
    await openPicker(tester, selected: (_) {});
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Take photo'), findsNothing);
    expect(picker.captures, 0);
    debugDefaultTargetPlatformOverride = null;
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('new photo picker captures one photo on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      picker.files.add(
        XFile.fromData(Uint8List.fromList([1, 2]), path: 'capture.jpg'),
      );
      FilePickerResult? result;
      await openPicker(
        tester,
        allowCamera: true,
        selected: (value) => result = value,
      );
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(picker.source, ImageSource.camera);
      expect(picker.captures, 1);
      expect(picker.options, isNull);
      expect(picker.singleOptions?.requestFullMetadata, isFalse);
      expect(result?.files.single.name, 'capture.jpg');
      expect(result?.files.single.bytes, [1, 2]);
      debugDefaultTargetPlatformOverride = null;
    });
  }
  test('cancelling camera returns no selection', () async {
    expect(await takeVaultPhoto(), isNull);
    expect(picker.captures, 1);
  });
  test('camera images obey remaining draft storage limit', () async {
    picker.files.add(
      XFile.fromData(Uint8List.fromList([1, 2]), path: 'capture.jpg'),
    );
    await expectLater(
      takeVaultPhoto(remainingBytes: 1),
      throwsA(isA<MediaUploadException>()),
    );
  });
  for (final code in [
    'camera_access_denied',
    'camera_access_restricted',
    'no_available_camera',
    'already_active',
  ]) {
    test(
      '$code gives an actionable message without platform details',
      () async {
        picker.captureError = PlatformException(
          code: code,
          message: 'internal private platform diagnostic',
        );
        await expectLater(
          takeVaultPhoto(),
          throwsA(
            isA<MediaUploadException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('internal')),
            ),
          ),
        );
      },
    );
  }
  testWidgets('unsupported desktop keeps gallery and videos available', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await openPicker(tester, allowCamera: true, selected: (_) {});
    expect(find.text('Take photo'), findsNothing);
    expect(find.text('Photos'), findsOneWidget);
    expect(picker.captures, 0);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'new memory menu passes camera mode without opening it prematurely',
    (tester) async {
      String? mode;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  mode = await showMemoryCreationMenu(context);
                },
                child: const Text('New'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('Add photos'), findsOneWidget);
      expect(picker.captures, 0);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(mode, 'camera');
      expect(picker.captures, 0);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
