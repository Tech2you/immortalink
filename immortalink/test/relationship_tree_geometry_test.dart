import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/relationship_tree_geometry.dart';

void main() {
  test(
    'both rows and add controls remain inside the canvas for uneven families',
    () {
      for (final siblings in [0, 1, 3, 4, 6, 20, 100]) {
        for (final spouses in [0, 1, 3, 5, 20]) {
          for (final generation in [1, 10, 100]) {
            final width = relationshipTreeWidth(
              widestGeneration: generation,
              siblings: siblings,
              spouses: spouses,
            );
            final center = width / 2;
            expect(
              center - 260 - siblings * 175 - 80,
              greaterThanOrEqualTo(40),
            );
            expect(
              center + 260 + spouses * 175 + 80,
              lessThanOrEqualTo(width - 40),
            );
            expect(width, greaterThanOrEqualTo(generation * 190));
          }
        }
      }
    },
  );
  test('small-tree dimensions do not change', () {
    expect(
      relationshipTreeWidth(widestGeneration: 1, siblings: 0, spouses: 0),
      1700,
    );
    expect(
      relationshipTreeWidth(widestGeneration: 4, siblings: 2, spouses: 1),
      1700,
    );
  });
}
