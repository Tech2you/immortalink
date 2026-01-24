export 'web_audio_recorder_types.dart';

import 'web_audio_recorder_types.dart';

// Conditional import:
// - non-web uses stub
// - web uses web implementation
import 'web_audio_recorder_stub.dart'
    if (dart.library.html) 'web_audio_recorder_web.dart';

WebAudioRecorder createWebAudioRecorder() => createWebAudioRecorderImpl();
