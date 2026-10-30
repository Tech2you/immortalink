import 'dart:math';

// The focus remains centered, so reserve the larger side on both sides.
double relationshipTreeWidth({
  required int widestGeneration,
  required int siblings,
  required int spouses,
}) {
  final sideExtent = 260 + max(siblings, spouses) * 175 + 80 + 40;
  return max(1700.0, max(widestGeneration * 190.0, sideExtent * 2.0));
}
