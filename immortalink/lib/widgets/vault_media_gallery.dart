import 'package:flutter/material.dart';

import '../services/recent_cache.dart';
import '../utils/media_upload_policy.dart';
import 'vault_media.dart';

/// Read-only preview. Uploads, edits and deletion stay with the owning screen.
Future<void> openVaultMediaGallery(
  BuildContext context,
  List<String> urls, {
  required int initialIndex,
  bool cachedOnly = false,
}) async {
  if (initialIndex < 0 || initialIndex >= urls.length) return;
  final selected = urls[initialIndex];
  if (selected.trim().isEmpty) return;
  if (!cachedOnly && MediaUploadPolicy.isVideo(selected)) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => VaultVideoScreen(url: selected)),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => VaultMediaGallery(
      urls: List.unmodifiable(urls),
      initialIndex: initialIndex,
      cachedOnly: cachedOnly,
    ),
  );
}

class VaultMediaGallery extends StatefulWidget {
  const VaultMediaGallery({
    super.key,
    required this.urls,
    required this.initialIndex,
    this.cachedOnly = false,
  });
  final List<String> urls;
  final int initialIndex;
  final bool cachedOnly;

  @override
  State<VaultMediaGallery> createState() => _VaultMediaGalleryState();
}

class _VaultMediaGalleryState extends State<VaultMediaGallery> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _accessChanged = false;

  @override
  void initState() {
    super.initState();
    RecentCache.instance.addListener(_clear);
  }

  void _clear() {
    if (mounted) setState(() => _accessChanged = true);
  }

  @override
  void dispose() {
    RecentCache.instance.removeListener(_clear);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.95,
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Media',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close media',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: _accessChanged
                    ? const Center(
                        child: Text('Reopen this media from your vault.'),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ColoredBox(
                          color: Colors.black,
                          child: PageView.builder(
                            controller: _pages,
                            itemCount: widget.urls.length,
                            onPageChanged: (index) =>
                                setState(() => _index = index),
                            itemBuilder: (_, index) => InteractiveViewer(
                              key: ValueKey('media-preview-$index'),
                              minScale: 1,
                              maxScale: 4,
                              child: VaultMedia.network(
                                widget.urls[index],
                                cachedOnly: widget.cachedOnly,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Row(
                children: [
                  if (!_accessChanged)
                    Text('${_index + 1} / ${widget.urls.length}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
