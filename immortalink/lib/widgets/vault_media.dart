import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/media_upload_policy.dart';
import '../utils/video_preview_source.dart';
import 'recent_photo.dart';

class VaultMedia extends StatelessWidget {
  final String url;
  final bool cachedOnly;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  const VaultMedia.network(
    this.url, {
    super.key,
    this.cachedOnly = false,
    this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.gaplessPlayback = false,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!MediaUploadPolicy.isVideo(url)) {
      if (kIsWeb) {
        return Image.network(
          url,
          fit: fit,
          width: width,
          height: height,
          alignment: alignment,
          gaplessPlayback: gaplessPlayback,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        );
      }
      return RecentPhoto(
        url,
        cachedOnly: cachedOnly,
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        errorBuilder: errorBuilder,
      );
    }
    if (cachedOnly) {
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_outlined, size: 28),
                  SizedBox(height: 8),
                  Flexible(child: Text(
                    'Video\nOffline',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.3),
                  )),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return VaultVideoTile(url: url, width: width, height: height, fit: fit);
  }
}

class VaultVideoTile extends StatefulWidget {
  final String url;
  final double? width, height;
  final BoxFit? fit;
  const VaultVideoTile({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
  });

  @override
  State<VaultVideoTile> createState() => _VaultVideoTileState();
}

class _VaultVideoTileState extends State<VaultVideoTile> {
  VideoPlayerController? _preview;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VaultVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final old = _preview;
    final controller = videoController(widget.url);
    _preview = controller;
    await old?.dispose();
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || _preview != controller) return;
      await controller.setVolume(0);
      await controller.seekTo(Duration.zero);
      if (mounted && _preview == controller) setState(() {});
    } catch (_) {
      // Playback remains available to retry even if the preview cannot load.
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Semantics(
      label: 'Play video',
      button: true,
      child: SizedBox(
        width: widget.width,
        height: widget.height ?? 160,
        child: Material(
          color: const Color(0xff242424),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VaultVideoScreen(url: widget.url),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preview != null && preview.value.isInitialized)
                  FittedBox(
                    fit: widget.fit ?? BoxFit.contain,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: preview.value.size.width,
                      height: preview.value.size.height,
                      child: VideoPlayer(preview),
                    ),
                  ),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 48,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PendingVideoPreview extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  const PendingVideoPreview({
    super.key,
    required this.bytes,
    required this.name,
  });
  @override
  State<PendingVideoPreview> createState() => _PendingVideoPreviewState();
}

class _PendingVideoPreviewState extends State<PendingVideoPreview> {
  String? _url;
  Future<void> Function()? _release;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(PendingVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _prepare();
  }

  Future<void> _prepare() async {
    final generation = ++_generation;
    final previous = _release;
    _release = null;
    _url = null;
    _failed = false;
    await previous?.call();
    try {
      final source = await prepareVideoPreview(
        widget.bytes,
        MediaUploadPolicy.extensionForName(widget.name),
      );
      if (!mounted || generation != _generation) {
        await source.release();
        return;
      }
      setState(() {
        _url = source.url;
        _release = source.release;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    ++_generation;
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _url != null
      ? VaultVideoTile(key: ValueKey(_url), url: _url!, height: double.infinity)
      : Center(
          child: _failed
              ? IconButton(
                  tooltip: 'Retry video preview',
                  onPressed: () {
                    setState(() => _failed = false);
                    _prepare();
                  },
                  icon: const Icon(Icons.refresh),
                )
              : const CircularProgressIndicator(),
        );
}

class VaultVideoScreen extends StatefulWidget {
  final String url;
  const VaultVideoScreen({super.key, required this.url});

  @override
  State<VaultVideoScreen> createState() => _VaultVideoScreenState();
}

class _VaultVideoScreenState extends State<VaultVideoScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _load();
  }

  Future<void> _load() async {
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() => _failed = false);
    final controller = videoController(widget.url);
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted || _controller != controller) return;
      setState(() {});
      if (_foreground) await controller.play();
    } catch (_) {
      if (mounted && _controller == controller) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  String _time(Duration time) =>
      '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Video'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not play this video.',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : controller == null || !controller.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) => Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                    if (value.hasError)
                      const Text(
                        'Playback interrupted. Reopen the video to retry.',
                        style: TextStyle(color: Colors.white),
                      ),
                    if (value.isBuffering) const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          color: Colors.white,
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: () async {
                            if (value.isPlaying) {
                              await controller.pause();
                            } else {
                              if (value.position >= value.duration) {
                                await controller.seekTo(Duration.zero);
                              }
                              await controller.play();
                            }
                          },
                        ),
                        Text(
                          '${_time(value.position)} / ${_time(value.duration)}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const Spacer(),
                        IconButton(
                          color: Colors.white,
                          tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                          icon: Icon(
                            value.volume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                          onPressed: () =>
                              controller.setVolume(value.volume == 0 ? 1 : 0),
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
