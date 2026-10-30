import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/brand_loading.dart';
import 'package:immortalink/widgets/heiro_surface.dart';
import 'package:immortalink/widgets/story_feed_item.dart';
import 'package:immortalink/widgets/memory_creation_menu.dart';
import 'package:immortalink/screens/heiro_settings_screen.dart';

void main() {
  setUpAll(() async {
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isNotEmpty) {
      final data = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(data))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('UI_PREVIEW_QA')) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/ui-preview-33-qa/$name.png'),
    );
  }

  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(834, 1194),
  ]) {
    testWidgets('story layout, carousel and recordings at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (size.width == 320) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: HeiroSurface(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Heiro'),
                actions: const [
                  IconButton(
                    onPressed: null,
                    tooltip: 'New memory',
                    icon: Icon(Icons.add_circle),
                  ),
                  IconButton(
                    onPressed: null,
                    tooltip: 'Settings',
                    icon: Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    children: [
                      StoryFeedItem(
                        author: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text('Nora'),
                          subtitle: Text('Yesterday · Family'),
                        ),
                        title: 'Sunday at Mum\'s',
                        body: List.filled(
                          10,
                          'Everyone stayed for seconds. Mum told us how she met Dad, and we finally recorded the whole story.',
                        ).join(' '),
                        photos: List.generate(
                          3,
                          (i) => Image.asset(
                            'assets/images/immortalink_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        recordings: const [
                          ListTile(
                            leading: Icon(Icons.play_circle),
                            title: Text('Mum\'s Sunday story'),
                            trailing: Text('0:42'),
                          ),
                          ListTile(
                            leading: Icon(Icons.play_circle),
                            title: Text('How they met'),
                            trailing: Text('1:08'),
                          ),
                        ],
                        onOpen: () => opened = true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/immortalink_logo.png'),
          tester.element(find.byType(StoryFeedItem)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('See more', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Tap to open'), findsNothing);
      expect(find.text('How they met'), findsNothing);
      await capture(tester, 'feed-${size.width.toInt()}');
      await tester.tap(find.text('Sunday at Mum\'s'));
      expect(opened, isTrue);
      await tester.scrollUntilVisible(
        find.byType(PageView),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(PageView));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('1 more recording'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 more recording'));
      await tester.pumpAndSettle();
      expect(find.text('How they met'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings are a page and all entries remain reachable', (
    tester,
  ) async {
    var selected = '';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final labels = [
      'Change password',
      'Subscription and storage',
      'Family settings',
      'Offline memories',
      'AI data permission',
      'Safety and blocked members',
      'Contact support',
      'Privacy Policy',
      'Terms of Use',
      'Sign out',
      'Delete account',
    ];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HeiroSettingsScreen(
          entries: [
            for (var i = 0; i < labels.length; i++)
              HeiroSettingsEntry(
                group: i < 2
                    ? 'Account'
                    : i < 4
                    ? 'Family'
                    : i < 6
                    ? 'Privacy and safety'
                    : i < 9
                    ? 'Help'
                    : 'Account actions',
                label: labels[i],
                icon: Icons.chevron_right,
                onTap: () => selected = labels[i],
                destructive: labels[i] == 'Delete account',
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'settings-phone');
    expect(find.byType(PopupMenuButton), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out'));
    expect(selected, 'Sign out');
    expect(selected, isNot('Delete account'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plus returns the existing composer modes', (tester) async {
    String? mode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              tooltip: 'New memory',
              icon: const Icon(Icons.add),
              onPressed: () async =>
                  mode = await showMemoryCreationMenu(context),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('New memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record voice'));
    await tester.pumpAndSettle();
    expect(mode, 'voice');
  });

  testWidgets('brand loading settles and respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLoading()));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: BrandLoading(),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value,
      1,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
