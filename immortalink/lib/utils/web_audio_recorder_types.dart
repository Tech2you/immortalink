class RecordedAudio {
  final List<int> bytes;
  final String mimeType;
  final String extension;

  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });
}

abstract class WebAudioRecorder {
  bool get isSupported;
  bool get isRecording;

  Future<void> start();
  Future<RecordedAudio> stop(); // stop + return bytes
  Future<void> cancel();        // stop + discard
  void dispose();
}
