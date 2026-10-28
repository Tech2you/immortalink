import 'package:flutter/material.dart';

/// A quiet reserved space; loading media never changes the surrounding layout.
class ContentPlaceholder extends StatelessWidget {
  const ContentPlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
    ),
  );
}

class FeedPlaceholder extends StatelessWidget {
  const FeedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading memories',
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ClipOval(child: ContentPlaceholder(width: 38, height: 38)),
              SizedBox(width: 10),
              Expanded(child: ContentPlaceholder(height: 16)),
              SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContentPlaceholder(width: 96, height: 76),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    ContentPlaceholder(height: 16),
                    SizedBox(height: 10),
                    ContentPlaceholder(height: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const ContentPlaceholder(width: 110, height: 30),
        ],
      ),
    ),
  );
}
