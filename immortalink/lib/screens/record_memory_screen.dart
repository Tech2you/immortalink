import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../utils/public_error.dart';
import '../utils/web_audio_recorder.dart';
import '../widgets/heiro_surface.dart';

class RecordedMemoryVoice {
  const RecordedMemoryVoice({
    required this.audio,
    required this.seconds,
    required this.title,
  });
  final RecordedAudio audio;
  final int seconds;
  final String title;
}

/// Keeps the take local. Uploading still belongs to Preserve memory.
class RecordMemoryScreen extends StatefulWidget {
  const RecordMemoryScreen({
    super.key,
    required this.recorder,
    required this.defaultTitle,
  });
  final WebAudioRecorder recorder;
  final String defaultTitle;

  @override
  State<RecordMemoryScreen> createState() => _RecordMemoryScreenState();
}

class _RecordMemoryScreenState extends State<RecordMemoryScreen>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final _elapsed = Stopwatch();
  late final TextEditingController _title;
  Timer? _timer;
  StreamSubscription<void>? _completion;
  StreamSubscription<Duration>? _positionSubscription;
  RecordedAudio? _take;
  Duration _position = Duration.zero;
  bool _busy = true;
  bool _paused = false;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.defaultTitle);
    WidgetsBinding.instance.addObserver(this);
    _completion = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        widget.recorder.isRecording &&
        !_paused &&
        !_busy) {
      unawaited(_togglePause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _completion?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    _title.dispose();
    if (widget.recorder.isRecording) unawaited(widget.recorder.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _player.stop();
      await widget.recorder.start();
      if (!mounted) {
        await widget.recorder.cancel();
        return;
      }
      _elapsed
        ..reset()
        ..start();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && !_paused) setState(() {});
      });
      setState(() {
        _take = null;
        _paused = false;
        _playing = false;
        _position = Duration.zero;
      });
    } catch (e) {
      if (mounted) setState(() => _error = publicErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePause() async {
    if (_busy || !widget.recorder.isRecording) return;
    setState(() => _busy = true);
    try {
      if (_paused) {
        await widget.recorder.resume();
        _elapsed.start();
      } else {
        await widget.recorder.pause();
        _elapsed.stop();
      }
      if (mounted) {
        setState(() {
          _paused = !_paused;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = publicErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !widget.recorder.isRecording) return;
    setState(() => _busy = true);
    try {
      final audio = await widget.recorder.stop();
      _elapsed.stop();
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _take = audio;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = publicErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final audio = _take;
    if (audio == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_playing) {
        await _player.pause();
      } else if (_position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(
          audio.localPath == null
              ? BytesSource(Uint8List.fromList(audio.bytes))
              : DeviceFileSource(audio.localPath!),
        );
      }
      if (mounted) {
        setState(() {
          _playing = !_playing;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = publicErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _timer?.cancel();
      await widget.recorder.cancel();
      await _player.stop();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = publicErrorMessage(e);
        });
      }
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final review = _take != null;
    final recording = widget.recorder.isRecording;
    return PopScope<RecordedMemoryVoice>(
      canPop: !_busy && !recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _discard();
      },
      child: HeiroSurface(
        child: Scaffold(
          appBar: AppBar(
            title: Text(review ? 'Review recording' : 'Record voice'),
            leading: IconButton(
              tooltip: 'Cancel recording',
              onPressed: _busy ? null : _discard,
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 32),
                    Icon(
                      review
                          ? Icons.mic_none
                          : (_paused ? Icons.pause_circle_outline : Icons.mic),
                      size: 64,
                      color: heiroBlue,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      review
                          ? _time(_playing ? _position : _elapsed.elapsed)
                          : _time(_elapsed.elapsed),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      review
                          ? 'Recorded'
                          : (_busy
                                ? 'Please wait'
                                : (_paused
                                      ? 'Paused'
                                      : (recording
                                            ? 'Recording'
                                            : 'Not recording'))),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 32),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    if (review) ...[
                      TextField(
                        controller: _title,
                        maxLength: 100,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Recording name',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _preview,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        label: Text(_playing ? 'Pause playback' : 'Listen'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(
                                  context,
                                  RecordedMemoryVoice(
                                    audio: _take!,
                                    seconds: _elapsed.elapsed.inSeconds.clamp(
                                      1,
                                      86400,
                                    ),
                                    title: _title.text.trim().isEmpty
                                        ? widget.defaultTitle
                                        : _title.text.trim(),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Use recording'),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Record again'),
                      ),
                    ] else ...[
                      if (recording) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _togglePause,
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          label: Text(
                            _paused ? 'Resume recording' : 'Pause recording',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _stop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop and review'),
                        ),
                      ] else if (!_busy)
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.mic),
                          label: const Text('Try again'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
