import 'dart:typed_data';

class WebAudioRecorder {
  static bool get isSupported => false;

  Future<void> start() async {
    throw UnsupportedError('WebAudioRecorder is only supported on Flutter Web.');
  }

  Future<Uint8List> stop() async {
    throw UnsupportedError('WebAudioRecorder is only supported on Flutter Web.');
  }

  Future<void> dispose() async {}
}
