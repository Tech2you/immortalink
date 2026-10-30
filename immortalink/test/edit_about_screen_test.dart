import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/edit_about_screen.dart';

void main() {
  setUpAll(() async {
    const font = String.fromEnvironment('LOADING_QA_FONT');
    if (font.isNotEmpty) {
      final bytes = ByteData.sublistView(await File(font).readAsBytes());
      await (FontLoader('Roboto')..addFont(Future.value(bytes))).load();
      await (FontLoader('Ahem')..addFont(Future.value(bytes))).load();
      await (FontLoader('MaterialIcons')..addFont(
        rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final width in [320.0, 390.0, 834.0]) {
    testWidgets('failed About save retains text and retries at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.6
          : 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var fail = true;
      var draft = '';
      var saved = '';
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open editor'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditAboutScreen(
                      initialText: 'Original story',
                      onChanged: (text) => draft = text,
                      onSave: (text) async {
                        if (fail) throw StateError('HTTP 403');
                        saved = text;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My family and my story.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save your changes. Your text is still here."),
        findsOneWidget,
      );
      expect(find.text('My family and my story.'), findsOneWidget);
      expect(draft, 'My family and my story.');
      if (const bool.fromEnvironment('UI_PREVIEW_QA')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../build/ui-preview-34-qa/about-error-${width.toInt()}.png',
          ),
        );
      }
      expect(tester.takeException(), isNull);
      fail = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(saved, draft);
      expect(find.text('Open editor'), findsOneWidget);
    });
  }
}
