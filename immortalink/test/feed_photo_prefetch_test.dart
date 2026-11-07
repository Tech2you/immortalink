import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/story_feed_item.dart';

void main() {
  testWidgets('feed prepares only adjacent media before a swipe', (
    tester,
  ) async {
    final prepared = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoryFeedItem(
              author: const Text('Family member'),
              title: '',
              body: '',
              photos: List.generate(
                20,
                (index) => Builder(
                  builder: (_) {
                    prepared.add(index);
                    return ColoredBox(
                      color: Colors.blue,
                      child: Center(child: Text('Photo $index')),
                    );
                  },
                ),
              ),
              recordings: const [],
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(prepared, {0, 1});
    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(prepared, contains(2));
    expect(prepared.length, lessThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
  });
}
