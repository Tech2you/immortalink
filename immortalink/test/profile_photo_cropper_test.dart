import 'dart:io';
import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/profile_photo_cropper.dart';

void main() {
  testWidgets('photo editor has fixed circular framing and supports cancel', (
    tester,
  ) async {
    final bytes = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png',
    ).readAsBytesSync();
    Uint8List? result;
    bool closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<Uint8List>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePhotoCropper(bytes: bytes),
                ),
              );
              closed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final crop = tester.widget<Crop>(find.byType(Crop));
    expect(crop.withCircleUi, isTrue);
    expect(crop.interactive, isTrue);
    expect(crop.fixCropRect, isTrue);
    expect(find.text('Save'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
