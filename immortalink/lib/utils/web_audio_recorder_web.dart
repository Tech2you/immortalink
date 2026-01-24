import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js';
import 'dart:js_util' as js_util;

import 'web_audio_recorder_types.dart';

WebAudioRecorder createWebAudioRecorderImpl() => _WebAudioRecorder();

class _WebAudioRecorder implements WebAudioRecorder {
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;

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
    final hasMediaRecorder = js_util.hasProperty(html.window, 'MediaRecorder');
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

    // Request mic
    _stream = await html.window.navigator.mediaDevices!.getUserMedia({'audio': true});

    // Pick a mime type Edge supports
    final mime = _pickMimeType();

    // Create recorder (some browsers throw if mime unsupported)
    _recorder = _createRecorder(_stream!, mime);

    // dataavailable event
    _dataHandler = allowInterop((dynamic event) {
      try {
        final blob = event?.data as html.Blob?;
        if (blob != null) {
          // ignore empty chunks
          final size = js_util.getProperty(blob, 'size') as int?;
          if (size != null && size > 0) _chunks.add(blob);
        }
      } catch (_) {
        // ignore
      }
    });

    // stop event
    _stopHandler = allowInterop((dynamic _) {
      if (_stopCompleter != null && !_stopCompleter!.isCompleted) {
        _stopCompleter!.complete();
      }
    });

    _recorder!.addEventListener('dataavailable', _dataHandler as dynamic);
    _recorder!.addEventListener('stop', _stopHandler as dynamic);

    // timeslice helps ensure we get dataavailable chunks
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
        if (_dataHandler != null) _recorder!.removeEventListener('dataavailable', _dataHandler as dynamic);
        if (_stopHandler != null) _recorder!.removeEventListener('stop', _stopHandler as dynamic);
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
  }

  String _pickMimeType() {
    // We can’t rely on isTypeSupported being exposed by dart:html in all versions,
    // so we choose a common-safe default.
    // Edge usually supports audio/webm;codecs=opus
    return 'audio/webm;codecs=opus';
  }

  html.MediaRecorder _createRecorder(html.MediaStream stream, String mime) {
    try {
      return html.MediaRecorder(stream, {'mimeType': mime});
    } catch (_) {
      // fallback
      return html.MediaRecorder(stream);
    }
  }

  String _getRecorderMimeType(html.MediaRecorder r) {
    try {
      final mt = js_util.getProperty(r, 'mimeType');
      if (mt is String && mt.trim().isNotEmpty) return mt;
    } catch (_) {}
    // fallback to typical webm
    return 'audio/webm';
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
    if (m.contains('ogg')) return 'ogg';
    if (m.contains('webm')) return 'webm';
    return 'webm';
  }
}
