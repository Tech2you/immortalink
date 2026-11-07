import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/vault_media.dart';
import 'package:immortalink/widgets/vault_media_gallery.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_media_test.dart' show FakeVideoPlatform;

void main() {
  Future<void> open(
    WidgetTester tester, {
    bool video = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openVaultMediaGallery(
                context,
                video
                    ? ['https://example.com/clip.mp4?token=test']
                    : [
                        'https://example.com/one.jpg',
                        'https://example.com/two.jpg',
                      ],
                initialIndex: video ? 0 : 1,
                cachedOnly: !video,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'photos open at selected index, swipe and close at text scale $scale',
      (tester) async {
        await open(tester, scale: scale);
        expect(find.text('2 / 2'), findsOneWidget);
        expect(find.byKey(const ValueKey('media-preview-1')), findsOneWidget);
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
              .maxScale,
          4,
        );
        await tester.drag(find.byType(PageView), const Offset(320, 0));
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        await tester.tap(find.byTooltip('Close media'));
        await tester.pumpAndSettle();
        expect(find.byType(VaultMediaGallery), findsNothing);
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selected video opens the existing player directly', (
    tester,
  ) async {
    final platform = FakeVideoPlatform();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    VideoPlayerPlatform.instance = platform;
    addTearDown(platform.close);
    await open(tester, video: true);
    expect(find.byType(VaultVideoScreen), findsOneWidget);
    expect(platform.sources.single.uri, contains('clip.mp4'));
    expect(platform.plays, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(platform.disposals, 1);
    expect(tester.takeException(), isNull);
  });
}
