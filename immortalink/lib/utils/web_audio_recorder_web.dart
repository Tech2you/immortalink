// Web-only implementation (safe via conditional export)
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class WebAudioRecorder {
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];

  static bool get isSupported =>
      html.window.navigator.mediaDevices != null &&
      html.MediaRecorder != null;

  Future<void> start() async {
    _chunks.clear();

    _stream = await html.window.navigator.mediaDevices!
        .getUserMedia({'audio': true});

    // Most browsers produce audio/webm;codecs=opus
    _recorder = html.MediaRecorder(_stream!);

    _recorder!.addEventListener('dataavailable', (event) {
      final e = event as html.BlobEvent;
      final blob = e.data;
      if (blob != null && blob.size > 0) _chunks.add(blob);
    });

    _recorder!.start();
  }

  Future<Uint8List> stop() async {
    final recorder = _recorder;
    if (recorder == null) throw StateError('Recorder not started.');

    final completer = Completer<Uint8List>();

    void onStop(_) async {
      recorder.removeEventListener('stop', onStop);

      try {
        final blob = html.Blob(_chunks, 'audio/webm');
        final reader = html.FileReader();

        reader.readAsArrayBuffer(blob);
        reader.onLoadEnd.listen((_) {
          final data = reader.result as ByteBuffer;
          completer.complete(Uint8List.view(data));
        });
      } catch (e) {
        completer.completeError(e);
      } finally {
        // stop tracks
        _stream?.getTracks().forEach((t) => t.stop());
        _stream = null;
        _recorder = null;
      }
    }

    recorder.addEventListener('stop', onStop);
    recorder.stop();

    return completer.future;
  }

  Future<void> dispose() async {
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _recorder = null;
    _chunks.clear();
  }
}
