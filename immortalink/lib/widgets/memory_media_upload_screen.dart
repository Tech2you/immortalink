import 'dart:async';

import 'package:flutter/material.dart';
import '../services/memory_media_batch.dart';
import '../utils/everroot_upgrade_prompt.dart';
import '../utils/media_upload_policy.dart';
import '../utils/public_error.dart';
import 'vault_media.dart';

Future<int> showMemoryMediaUpload(
  BuildContext context, {
  required MemoryMediaBatch batch,
  bool autoStart = false,
}) async =>
    await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            MemoryMediaUploadScreen(batch: batch, autoStart: autoStart),
      ),
    ) ??
    batch.savedCount;

class MemoryMediaUploadScreen extends StatefulWidget {
  const MemoryMediaUploadScreen({
    super.key,
    required this.batch,
    this.autoStart = false,
  });
  final MemoryMediaBatch batch;
  final bool autoStart;
  @override
  State<MemoryMediaUploadScreen> createState() =>
      _MemoryMediaUploadScreenState();
}

class _MemoryMediaUploadScreenState extends State<MemoryMediaUploadScreen> {
  MemoryMediaBatch get batch => widget.batch;
  bool _leaving = false;
  bool _confirming = false;
  StreamSubscription<dynamic>? _authSubscription;
  @override
  void initState() {
    super.initState();
    _authSubscription = batch.client.auth.onAuthStateChange.listen((_) {
      if (!batch.sameAccount) batch.pause();
      if (mounted) setState(() {});
    });
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _upload());
    }
  }

  @override
  void dispose() {
    batch.pause();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _upload() async {
    if (!mounted) return;
    await batch.upload(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _close() async {
    if (batch.running || _confirming) return;
    if (batch.started && !batch.complete && batch.sameAccount) {
      _confirming = true;
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave without remaining media?'),
          content: Text(
            '${batch.savedCount} of ${batch.items.length} saved. '
            'The memory and saved media will stay. Remaining items will not be added.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      _confirming = false;
      if (leave != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, batch.savedCount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final errors = batch.items.where((item) => item.error != null);
    final error = errors.isEmpty ? null : errors.first.error;
    return PopScope<int>(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            onPressed: batch.running ? null : _close,
            icon: const Icon(Icons.close),
          ),
          title: Text(batch.started ? 'Adding media' : 'Selected media'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            batch.started
                                ? '${batch.savedCount} of ${batch.items.length} saved'
                                : '${batch.items.length} / ${MediaUploadPolicy.photoBatchMaxCount} selected',
                          ),
                        ),
                        if (batch.running)
                          IconButton(
                            tooltip: 'Pause after current item',
                            onPressed: batch.pause,
                            icon: const Icon(Icons.pause),
                          ),
                      ],
                    ),
                  ),
                  if (batch.running)
                    LinearProgressIndicator(
                      value: batch.savedCount / batch.items.length,
                      semanticsLabel: 'Media upload progress',
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        isEverRootQuotaError(error)
                            ? everRootQuotaMessageFromError(error)
                            : publicErrorMessage(error),
                      ),
                    ),
                  Expanded(
                    child: !batch.sameAccount
                        ? const Center(
                            child: Text('Account changed. Reopen this memory.'),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) => GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: constraints.maxWidth < 500
                                        ? 3
                                        : 5,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: batch.items.length,
                              itemBuilder: (_, index) {
                                final item = batch.items[index];
                                return Semantics(
                                  label:
                                      'Media ${index + 1}${item.saved ? ', saved' : ''}',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ColoredBox(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          MediaUploadPolicy.isVideo(
                                                item.media.name,
                                              )
                                              ? PendingVideoPreview(
                                                  bytes: item.media.bytes,
                                                  name: item.media.name,
                                                )
                                              : Image.memory(
                                                  item.media.bytes,
                                                  cacheWidth: 360,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                        ),
                                                      ),
                                                ),
                                          Positioned(
                                            bottom: 4,
                                            left: 4,
                                            child: CircleAvatar(
                                              radius: 14,
                                              child: Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (!batch.started)
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: IconButton.filledTonal(
                                                tooltip:
                                                    'Remove media ${index + 1}',
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                ),
                                                onPressed: () => setState(
                                                  () => batch.removeAt(index),
                                                ),
                                              ),
                                            ),
                                          if (item.saved ||
                                              item.error != null ||
                                              item.busy)
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: CircleAvatar(
                                                radius: 14,
                                                child: Icon(
                                                  item.saved
                                                      ? Icons.check
                                                      : item.busy
                                                      ? Icons.upload
                                                      : Icons.error_outline,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: batch.running
                            ? null
                            : batch.complete
                            ? _close
                            : !batch.sameAccount || batch.items.isEmpty
                            ? null
                            : _upload,
                        icon: Icon(
                          batch.complete
                              ? Icons.check
                              : batch.started
                              ? Icons.refresh
                              : Icons.upload,
                        ),
                        label: Text(
                          batch.complete
                              ? 'Done'
                              : batch.running
                              ? 'Uploading...'
                              : batch.started
                              ? 'Retry remaining media'
                              : 'Add ${batch.items.length} items',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
