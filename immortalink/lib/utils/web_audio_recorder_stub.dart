import 'dart:io';

import 'package:record/record.dart';

import 'web_audio_recorder_types.dart';

WebAudioRecorder createWebAudioRecorderImpl() => _DeviceAudioRecorder();

class _DeviceAudioRecorder implements WebAudioRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final List<String> _savedPaths = [];
  String? _path;
  bool _recording = false;

  @override
  bool get isSupported => true;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    if (_recording) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted.');
    }
    _path =
        '${Directory.systemTemp.path}/immortalink_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _path!,
    );
    _recording = true;
  }

  @override
  Future<RecordedAudio> stop() async {
    if (!_recording) throw StateError('Not recording.');
    final savedPath = await _recorder.stop() ?? _path;
    _recording = false;
    if (savedPath == null || savedPath.isEmpty) {
      throw StateError('The recording could not be saved.');
    }
    final file = File(savedPath);
    final bytes = await file.readAsBytes();
    _savedPaths.add(savedPath);
    _path = null;
    return RecordedAudio(
      bytes: bytes,
      mimeType: 'audio/mp4',
      extension: 'm4a',
      localPath: savedPath,
    );
  }

  @override
  Future<void> cancel() async {
    if (_recording) await _recorder.cancel();
    _recording = false;
    final path = _path;
    _path = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    for (final path in _savedPaths) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    _savedPaths.clear();
  }
}
