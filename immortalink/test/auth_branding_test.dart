import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:immortalink/screens/sign_in_screen.dart';
import 'package:immortalink/widgets/logo_watermark.dart';
import 'package:immortalink/widgets/startup_screen.dart';

void main() {
  const background = AssetImage('assets/images/immortalink_logo.png');
  const authImage = AssetImage('assets/images/sign_in_logo_heiro.png');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isNotEmpty) {
      final font = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(font))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'http://localhost:54321',
        anonKey: 'test-anon-key',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
    }
  });

  Future<void> settleImage(WidgetTester tester, AssetImage asset) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(asset, tester.element(find.image(asset)));
    });
    await tester.pumpAndSettle();
    final rawImage = tester.widget<RawImage>(
      find.descendant(of: find.image(asset), matching: find.byType(RawImage)),
    );
    expect(rawImage.image, isNotNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('BRANDING_VISUAL_QA')) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/branding-29-qa/$name.png'),
    );
  }

  testWidgets('startup uses the unlettered in-app background tree', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: StartupScreen(),
      ),
    );
    await settleImage(tester, background);
    expect(find.image(background), findsOneWidget);
    expect(find.image(authImage), findsNothing);
    expect(tester.getSize(find.byType(Image)), const Size(180, 180));
    await capture(tester, 'startup-phone');
    tester.view.physicalSize = const Size(834, 1194);
    await tester.pumpAndSettle();
    await capture(tester, 'startup-tablet');
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing background artwork is not replaced with auth artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LogoWatermark(child: SizedBox.expand())),
    );
    expect(find.image(background), findsOneWidget);
    expect(find.image(authImage), findsNothing);
  });

  for (final variant in [
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    (name: 'tablet', size: const Size(834, 1194), scale: 1.0),
    (name: 'small-large-text', size: const Size(320, 568), scale: 2.0),
  ]) {
    for (final signIn in [false, true]) {
      final mode = signIn ? 'sign-in' : 'create-account';
      testWidgets('$mode uses the lettered icon tree on ${variant.name}', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'auth_has_seen_create_account_prompt': signIn,
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = variant.size;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SignInScreen(),
          ),
        );
        await settleImage(tester, authImage);
        expect(find.image(authImage), findsOneWidget);
        expect(find.image(background), findsNothing);
        expect(
          find.text(
            signIn
                ? 'Use the account your family knows.'
                : 'Start free. Add your vault, then invite or join family.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final image = tester.getRect(find.image(authImage));
        expect(image.left, greaterThanOrEqualTo(0));
        expect(image.right, lessThanOrEqualTo(variant.size.width));
        await capture(tester, '$mode-${variant.name}');
      });
    }
  }
}
