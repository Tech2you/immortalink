import 'web_audio_recorder_types.dart';

WebAudioRecorder createWebAudioRecorderImpl() => _StubRecorder();

class _StubRecorder implements WebAudioRecorder {
  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<void> start() async {
    throw UnsupportedError('Web audio recording is only supported on web.');
  }

  @override
  Future<RecordedAudio> stop() async {
    throw UnsupportedError('Web audio recording is only supported on web.');
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
