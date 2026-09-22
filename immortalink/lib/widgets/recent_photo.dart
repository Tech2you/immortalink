import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/recent_cache.dart';
import '../services/connection_status.dart';

class RecentPhoto extends StatefulWidget {
  const RecentPhoto(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.cache,
    this.clientFactory,
    this.cachedOnly = false,
  });
  final String url;
  final bool cachedOnly;
  final BoxFit? fit;
  final double? width, height;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final RecentCache? cache;
  final http.Client Function()? clientFactory;
  @override
  State<RecentPhoto> createState() => _RecentPhotoState();
}

class _RecentPhotoState extends State<RecentPhoto> {
  late final _cache = widget.cache ?? RecentCache.instance;
  Uint8List? _bytes;
  Object? _error;
  bool _cached = false;
  bool _onlineOnly = false;
  int _request = 0;
  http.Client? _client;
  Timer? _expiryTimer;
  @override
  void initState() {
    super.initState();
    _cache.addListener(_clear);
    _load();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_cached && await _cache.read(_cache.photoKey(widget.url)) == null) {
        _clear();
      }
    });
  }

  void _clear() {
    ++_request;
    _client?.close();
    if (mounted) {
      setState(() {
        _bytes = null;
        _onlineOnly = false;
        _error = StateError('Cache cleared');
      });
    }
  }

  @override
  void didUpdateWidget(RecentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.cachedOnly != widget.cachedOnly) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final epoch = _cache.generation;
    final key = _cache.photoKey(widget.url);
    _client?.close();
    final client = _client = widget.clientFactory?.call() ?? http.Client();
    _bytes = null;
    _error = null;
    _cached = false;
    _onlineOnly = false;
    Uint8List? bytes;
    Object? error;
    bool cached = false;
    bool onlineOnly = false;
    try {
      if (widget.cachedOnly || ConnectionStatus.instance.offline) {
        throw http.ClientException('Offline');
      }
      final response = await client
          .send(http.Request('GET', Uri.parse(widget.url)))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        if (epoch == _cache.generation &&
            [401, 403, 404, 410].contains(response.statusCode)) {
          await _cache.remove(key);
        }
        throw StateError('Photo unavailable (${response.statusCode})');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        builder.add(chunk);
        if (builder.length > 20 * 1024 * 1024) {
          onlineOnly = true;
          throw StateError('Photo is too large for offline viewing');
        }
      }
      bytes = builder.takeBytes();
      // Only store decodable images, not a successful HTML/error response.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1);
      codec.dispose();
      await _cache.put(key, bytes, epoch: epoch, kind: 'photo');
    } on http.ClientException catch (e) {
      error = e;
      if (epoch == _cache.generation) bytes = await _cache.read(key);
      cached = bytes != null;
    } on TimeoutException catch (e) {
      error = e;
      if (epoch == _cache.generation) bytes = await _cache.read(key);
      cached = bytes != null;
    } catch (e) {
      error = e;
      bytes = null;
    } finally {
      client.close();
    }
    if (!mounted || request != _request || epoch != _cache.generation) return;
    setState(() {
      _bytes = bytes;
      _error = error;
      _cached = cached;
      _onlineOnly = onlineOnly;
    });
  }

  @override
  void dispose() {
    _cache.removeListener(_clear);
    _expiryTimer?.cancel();
    ++_request;
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_onlineOnly) {
      return Image.network(
        widget.url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        errorBuilder: widget.errorBuilder,
      );
    }
    if (_bytes != null) {
      return Semantics(
        label: _cached ? 'Cached photo, offline copy' : 'Photo',
        child: Image.memory(
          _bytes!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
          errorBuilder: widget.errorBuilder,
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _error == null
          ? const Center(child: CircularProgressIndicator())
          : widget.errorBuilder?.call(context, _error!, null) ??
                const Center(child: Icon(Icons.image_not_supported_outlined)),
    );
  }
}
