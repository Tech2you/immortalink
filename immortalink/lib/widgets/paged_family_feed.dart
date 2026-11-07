import 'package:flutter/material.dart';

import 'brand_loading.dart';

/// Only constructs posts within the viewport and a small prefetch margin.
class PagedFamilyFeed extends StatelessWidget {
  const PagedFamilyFeed({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemKey,
    required this.empty,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.error,
    this.header,
  });

  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Key Function(int) itemKey;
  final Widget empty;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;
  final String? error;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final headerCount = header == null ? 0 : 1;
    final contentCount = itemCount == 0 ? 1 : itemCount;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            (notification.scrollDelta ?? 0) > 0 &&
            notification.metrics.extentAfter < 650 &&
            hasMore &&
            !loading &&
            error == null) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        cacheExtent: 400,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: headerCount + contentCount + 1,
        findChildIndexCallback: (key) {
          for (var i = 0; i < itemCount; i++) {
            if (itemKey(i) == key) return headerCount + i;
          }
          return null;
        },
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) return header!;
          final itemIndex = index - headerCount;
          if (itemIndex < contentCount) {
            return itemCount == 0
                ? empty
                : KeyedSubtree(
                    key: itemKey(itemIndex),
                    child: itemBuilder(context, itemIndex),
                  );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: loading && itemCount > 0
                ? const Center(child: BrandLoading(size: 36))
                : error != null
                ? Column(
                    children: [
                      Text(error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: onLoadMore,
                        child: const Text('Try again'),
                      ),
                    ],
                  )
                : hasMore
                ? TextButton(
                    onPressed: onLoadMore,
                    child: const Text('Load more memories'),
                  )
                : itemCount > 0
                ? Text(
                    itemCount >= 30
                        ? 'Showing the latest 30 memories · Past 30 days'
                        : 'You’re up to date',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
