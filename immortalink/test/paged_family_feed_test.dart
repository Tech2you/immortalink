import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/paged_family_feed.dart';
import 'package:immortalink/widgets/story_feed_item.dart';

void main() {
  testWidgets('posts and their photos are built only near the viewport', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final photos = <int>{};
    var moreCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedFamilyFeed(
            controller: controller,
            itemCount: 10,
            itemKey: (i) => ValueKey(i),
            empty: const Text('Empty'),
            hasMore: true,
            loading: false,
            onLoadMore: () => moreCalls++,
            itemBuilder: (_, i) => StoryFeedItem(
              author: Text('Author $i'),
              title: '',
              body: 'Memory $i',
              photos: [
                Builder(
                  builder: (_) {
                    photos.add(i);
                    return const ColoredBox(color: Colors.blue);
                  },
                ),
              ],
              recordings: const [],
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(photos, contains(0));
    expect(photos.length, lessThan(4));
    expect(moreCalls, 0);
    for (var i = 0; i < 12 && moreCalls == 0; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
    }
    expect(moreCalls, greaterThan(0));
    expect(photos, contains(9));
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('page error retains posts and requires an explicit retry', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PagedFamilyFeed(
            controller: controller,
            itemCount: 1,
            itemKey: (i) => ValueKey(i),
            empty: const Text('Empty'),
            hasMore: true,
            loading: false,
            error: 'Could not load more memories.',
            onLoadMore: () => calls++,
            itemBuilder: (_, i) =>
                const SizedBox(height: 500, child: Text('Saved post')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Saved post'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
