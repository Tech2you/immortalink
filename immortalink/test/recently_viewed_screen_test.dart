import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/recently_viewed_screen.dart';
import 'package:immortalink/services/recent_cache.dart';
import 'recent_cache_test.dart' show MemoryDisk;

void main() {
  testWidgets(
    'narrow phone gallery loads lazily and clear requires confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = RecentCache(disk: MemoryDisk());
      await cache.setUser('a');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      for (var i = 0; i < 100; i++) {
        await cache.put(
          'photo:$i',
          png,
          epoch: cache.generation,
          kind: 'photo',
        );
      }
      await tester.pumpWidget(
        MaterialApp(home: RecentlyViewedScreen(cache: cache)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OfflinePhoto).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Clear offline storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await cache.list()).length, 100);
      await tester.tap(find.byTooltip('Clear offline storage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(await cache.list(), isEmpty);
      expect(find.text('No recent offline copies.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
