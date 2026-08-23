// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;

import 'web_audio_recorder_types.dart';

WebAudioRecorder createWebAudioRecorderImpl() => _WebAudioRecorder();

class _WebAudioRecorder implements WebAudioRecorder {
  static const int _targetAudioBitsPerSecond = 64000;

  static const List<String> _mimeCandidates = [
    'audio/mp4;codecs=mp4a.40.2',
    'audio/mp4',
    'audio/aac',
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/ogg;codecs=opus',
    'audio/ogg',
  ];

  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  String? _selectedMimeType;

  final List<html.Blob> _chunks = [];
  bool _recording = false;

  Completer<void>? _stopCompleter;

  Object? _dataHandler;
  Object? _stopHandler;

  @override
  bool get isRecording => _recording;

  @override
  bool get isSupported {
    final hasMediaDevices = html.window.navigator.mediaDevices != null;
    var hasMediaRecorder = false;
    try {
      hasMediaRecorder = _pickMimeType() != null;
    } catch (_) {
      hasMediaRecorder = false;
    }
    return hasMediaDevices && hasMediaRecorder;
  }

  @override
  Future<void> start() async {
    if (!isSupported) {
      throw StateError('Recording not supported in this browser.');
    }
    if (_recording) return;

    _chunks.clear();
    _stopCompleter = Completer<void>();

    _stream = await html.window.navigator.mediaDevices!.getUserMedia({
      'audio': {
        'channelCount': {'ideal': 1},
        'sampleRate': {'ideal': 44100},
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
    });

    final mime = _pickMimeType();

    _recorder = _createRecorder(_stream!, mime);

    _dataHandler = (html.Event event) {
      try {
        final blob = event is html.BlobEvent ? event.data : null;
        if (blob != null) {
          // ignore empty chunks
          final size = blob.size;
          if (size > 0) _chunks.add(blob);
        }
      } catch (_) {
        // ignore
      }
    };

    _stopHandler = (html.Event _) {
      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }
    };

    _recorder!.addEventListener(
      'dataavailable',
      _dataHandler as html.EventListener,
    );
    _recorder!.addEventListener('stop', _stopHandler as html.EventListener);

    _recorder!.start(200);

    _recording = true;
  }

  @override
  Future<RecordedAudio> stop() async {
    if (!_recording || _recorder == null) {
      throw StateError('Not recording.');
    }

    final recorder = _recorder!;
    final mime = _getRecorderMimeType(recorder);

    recorder.stop();

    // Never hang the UI
    try {
      await _stopCompleter!.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      // If stop event doesn’t fire, continue anyway.
    }

    // Final blob from chunks
    final blob = html.Blob(_chunks, mime);

    // Blob -> bytes
    final bytes = await _readBlobAsBytes(blob);

    // cleanup
    await _cleanup();

    return RecordedAudio(
      bytes: bytes,
      mimeType: mime,
      extension: _extFromMime(mime),
    );
  }

  @override
  Future<void> cancel() async {
    if (_recording && _recorder != null) {
      try {
        _recorder!.stop();
      } catch (_) {}
    }
    _chunks.clear();
    await _cleanup();
  }

  @override
  void dispose() {
    // fire and forget
    cancel();
  }

  Future<void> _cleanup() async {
    _recording = false;

    // remove listeners
    try {
      if (_recorder != null) {
        if (_dataHandler != null) {
          _recorder!.removeEventListener(
            'dataavailable',
            _dataHandler as html.EventListener,
          );
        }
        if (_stopHandler != null) {
          _recorder!.removeEventListener(
            'stop',
            _stopHandler as html.EventListener,
          );
        }
      }
    } catch (_) {}

    _dataHandler = null;
    _stopHandler = null;
    _stopCompleter = null;

    // stop tracks
    try {
      final tracks = _stream?.getTracks() ?? [];
      for (final t in tracks) {
        try {
          t.stop();
        } catch (_) {}
      }
    } catch (_) {}

    _recorder = null;
    _stream = null;
    _selectedMimeType = null;
  }

  String? _pickMimeType() {
    for (final mime in _preferredMimeCandidates()) {
      try {
        if (html.MediaRecorder.isTypeSupported(mime)) return mime;
      } catch (_) {}
    }
    return null;
  }

  Iterable<String> _preferredMimeCandidates() {
    if (_isAppleWebKit) return _mimeCandidates;
    return [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/ogg',
      'audio/mp4;codecs=mp4a.40.2',
      'audio/mp4',
      'audio/aac',
    ];
  }

  bool get _isAppleWebKit {
    final ua = html.window.navigator.userAgent.toLowerCase();
    final isIOS = ua.contains('iphone') || ua.contains('ipad');
    final isSafari =
        ua.contains('safari') &&
        !ua.contains('chrome') &&
        !ua.contains('crios') &&
        !ua.contains('fxios');
    return isIOS || isSafari;
  }

  html.MediaRecorder _createRecorder(html.MediaStream stream, String? mime) {
    if (mime != null && mime.isNotEmpty) {
      try {
        _selectedMimeType = mime;
        return html.MediaRecorder(stream, {
          'mimeType': mime,
          'audioBitsPerSecond': _targetAudioBitsPerSecond,
        });
      } catch (_) {}
    }

    for (final candidate in _preferredMimeCandidates()) {
      try {
        _selectedMimeType = candidate;
        return html.MediaRecorder(stream, {
          'mimeType': candidate,
          'audioBitsPerSecond': _targetAudioBitsPerSecond,
        });
      } catch (_) {}
    }

    _selectedMimeType = null;
    return html.MediaRecorder(stream);
  }

  String _getRecorderMimeType(html.MediaRecorder r) {
    try {
      final mt = r.mimeType;
      if (mt is String && mt.trim().isNotEmpty) return mt;
    } catch (_) {}

    final selected = _selectedMimeType;
    if (selected != null && selected.trim().isNotEmpty) return selected;
    return _isAppleWebKit ? 'audio/mp4' : 'audio/webm';
  }

  Future<List<int>> _readBlobAsBytes(html.Blob blob) async {
    final reader = html.FileReader();
    final c = Completer<List<int>>();

    reader.onError.listen((_) {
      if (!c.isCompleted) {
        c.completeError(StateError('Blob read failed.'));
      }
    });

    reader.onLoadEnd.listen((_) {
      final res = reader.result;

      if (res is ByteBuffer) {
        c.complete(Uint8List.view(res).toList());
        return;
      }
      if (res is Uint8List) {
        c.complete(res.toList());
        return;
      }
      if (res is List<int>) {
        c.complete(res);
        return;
      }

      // last resort: try cast dynamic to ByteBuffer
      try {
        final bb = res as ByteBuffer;
        c.complete(Uint8List.view(bb).toList());
      } catch (_) {
        c.completeError(StateError('Unexpected blob read result.'));
      }
    });

    reader.readAsArrayBuffer(blob);
    return c.future;
  }

  String _extFromMime(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('mp4') || m.contains('m4a') || m.contains('mpeg4')) {
      return 'm4a';
    }
    if (m.contains('aac')) return 'aac';
    if (m.contains('ogg')) return 'ogg';
    if (m.contains('webm')) return 'webm';
    if (m.contains('wav')) return 'wav';
    return _isAppleWebKit ? 'm4a' : 'webm';
  }
}
