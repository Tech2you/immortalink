class RecordedAudio {
  final List<int> bytes;
  final String mimeType;
  final String extension;
  final String? localPath;

  const RecordedAudio({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    this.localPath,
  });
}

abstract class WebAudioRecorder {
  bool get isSupported;
  bool get isRecording;

  Future<void> start();
  Future<RecordedAudio> stop(); // stop + return bytes
  Future<void> cancel(); // stop + discard
  void dispose();
}
