import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/indexing_service.dart';
import '../utils/web_audio_recorder.dart';

class CreateMemoryScreen extends StatefulWidget {
  final String vaultId;
  final String? initialLifeStage;
  final String initialMode;
  final String? displayName;
  final String? avatarUrl;

  const CreateMemoryScreen({
    super.key,
    required this.vaultId,
    this.initialLifeStage,
    this.initialMode = 'text',
    this.displayName,
    this.avatarUrl,
  });

  @override
  State<CreateMemoryScreen> createState() => _CreateMemoryScreenState();
}

class _CreateMemoryScreenState extends State<CreateMemoryScreen> {
  final _client = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _whenController = TextEditingController();
  final _peopleController = TextEditingController();
  final _locationController = TextEditingController();
  final WebAudioRecorder _recorder = createWebAudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();

  final List<_PendingPhoto> _photos = [];
  final List<_PendingVoice> _voices = [];
  int? _playingVoiceIndex;
  String? _selectedMood;
  bool _showDetails = false;
  bool _saving = false;
  bool _shareToFamilyFeed = true;

  static const _photoBucket = 'memory_photos';
  static const _voiceBucket = 'memory_voice';

  @override
  void initState() {
    super.initState();
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceIndex = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialMode == 'photo') _pickPhotos();
      if (widget.initialMode == 'voice') _recordVoice();
    });
  }

  @override
  void dispose() {
    if (_recorder.isRecording) unawaited(_recorder.cancel());
    _recorder.dispose();
    _previewPlayer.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _whenController.dispose();
    _peopleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  String _imageMime(String extension) => switch (extension) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    _ => 'image/jpeg',
  };

  Future<void> _pickPhotos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null) return;

      final selected = result.files
          .where((file) => file.bytes != null)
          .map(
            (file) => _PendingPhoto(
              name: file.name,
              bytes: file.bytes!,
              extension: _extension(file.name),
            ),
          )
          .toList();

      if (!mounted) return;
      final available = 10 - _photos.length;
      final accepted = selected.take(available).toList();
      setState(() {
        _photos.addAll(accepted);
      });
      if (selected.length > available) {
        _toast('You can add up to 10 photos to one memory.');
      }
    } catch (e) {
      _toast('Could not add photos: $e');
    }
  }

  Future<void> _recordVoice() async {
    if (!_recorder.isSupported) {
      _toast('Recording is not supported on this device yet.');
      return;
    }

    String? error;
    int seconds = 0;
    bool stopping = false;
    Timer? timer;

    final recorded =
        await showModalBottomSheet<({RecordedAudio audio, int seconds})>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> start() async {
                if (_recorder.isRecording || stopping || error != null) return;
                try {
                  await _recorder.start();
                  timer = Timer.periodic(const Duration(seconds: 1), (_) {
                    seconds += 1;
                    if (sheetContext.mounted) setSheetState(() {});
                  });
                } catch (e) {
                  if (sheetContext.mounted) {
                    setSheetState(() => error = e.toString());
                  }
                }
              }

              WidgetsBinding.instance.addPostFrameCallback((_) => start());
              final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
              final remaining = (seconds % 60).toString().padLeft(2, '0');

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    16,
                    22,
                    22 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Icon(
                        Icons.graphic_eq,
                        size: 54,
                        color: Color(0xFF76558F),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Recording your memory',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Speak naturally. You can listen before preserving it.',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$minutes:$remaining',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: stopping
                                  ? null
                                  : () async {
                                      timer?.cancel();
                                      await _recorder.cancel();
                                      if (sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
                                      }
                                    },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: stopping || !_recorder.isRecording
                                  ? null
                                  : () async {
                                      setSheetState(() => stopping = true);
                                      timer?.cancel();
                                      try {
                                        final audio = await _recorder.stop();
                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext, (
                                            audio: audio,
                                            seconds: seconds,
                                          ));
                                        }
                                      } catch (e) {
                                        setSheetState(() {
                                          error = e.toString();
                                          stopping = false;
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Stop and keep'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

    timer?.cancel();
    if (recorded == null || !mounted) return;
    setState(() {
      _voices.add(
        _PendingVoice(audio: recorded.audio, seconds: recorded.seconds),
      );
    });
  }

  String _voiceLength(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggleVoicePreview(int index) async {
    if (index < 0 || index >= _voices.length) return;
    try {
      if (_playingVoiceIndex == index) {
        await _previewPlayer.pause();
        if (mounted) setState(() => _playingVoiceIndex = null);
        return;
      }
      await _previewPlayer.stop();
      final audio = _voices[index].audio;
      final localPath = audio.localPath;
      await _previewPlayer.play(
        localPath == null
            ? BytesSource(Uint8List.fromList(audio.bytes))
            : DeviceFileSource(localPath),
      );
      if (mounted) setState(() => _playingVoiceIndex = index);
    } catch (e) {
      _toast('Could not play this voice note: $e');
    }
  }

  Future<void> _removeVoice(int index) async {
    if (index < 0 || index >= _voices.length) return;
    if (_playingVoiceIndex == index) await _previewPlayer.stop();
    if (!mounted) return;
    setState(() {
      _voices.removeAt(index);
      if (_playingVoiceIndex == index) {
        _playingVoiceIndex = null;
      } else if (_playingVoiceIndex != null && _playingVoiceIndex! > index) {
        _playingVoiceIndex = _playingVoiceIndex! - 1;
      }
    });
  }

  Future<void> _uploadPhotos(String userId, String memoryId) async {
    for (var index = 0; index < _photos.length; index++) {
      final photo = _photos[index];
      final stamp = DateTime.now().microsecondsSinceEpoch + index;
      final path =
          '$userId/${widget.vaultId}/memories/$memoryId/$stamp.${photo.extension}';
      await _client.storage
          .from(_photoBucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _imageMime(photo.extension),
            ),
          );
      await _client.from('memory_photos').insert({
        'vault_id': widget.vaultId,
        'memory_id': memoryId,
        'path': path,
      });
    }
  }

  Future<void> _uploadVoice(String userId, String memoryId) async {
    for (var index = 0; index < _voices.length; index++) {
      final audio = _voices[index].audio;
      final stamp = DateTime.now().microsecondsSinceEpoch + index;
      final path =
          '$userId/${widget.vaultId}/memories/$memoryId/voice/$stamp.${audio.extension}';
      await _client.storage
          .from(_voiceBucket)
          .uploadBinary(
            path,
            Uint8List.fromList(audio.bytes),
            fileOptions: FileOptions(
              upsert: false,
              contentType: audio.mimeType,
            ),
          );
      final inserted = await _client
          .from('memory_voice_notes')
          .insert({
            'vault_id': widget.vaultId,
            'memory_id': memoryId,
            'path': path,
            'title': 'Voice note',
          })
          .select('id')
          .maybeSingle();

      final voiceId = (inserted?['id'] ?? '').toString();
      if (voiceId.isEmpty) continue;
      final token = _client.auth.currentSession?.accessToken.trim();
      if (token == null || token.isEmpty) continue;
      unawaited(() async {
        try {
          await _client.functions.invoke(
            'index_voice_note',
            headers: {
              'Authorization': 'Bearer $token',
              'authorization': 'Bearer $token',
            },
            body: {'vault_id': widget.vaultId, 'memory_voice_note_id': voiceId},
          );
        } catch (_) {}
      }());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (body.isEmpty && _photos.isEmpty && _voices.isEmpty) {
      _toast('Write something, add a photo, or record your voice first.');
      return;
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _toast('Please sign in again.');
      return;
    }

    setState(() => _saving = true);
    String? memoryId;
    try {
      final fallbackTitle = title.isNotEmpty
          ? title
          : body.isNotEmpty
          ? ''
          : (_voices.isNotEmpty ? 'Voice memory' : 'Photo memory');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final inserted = await _client
          .from('memories')
          .insert({
            'vault_id': widget.vaultId,
            // Kept internally for compatibility with older memories. The new
            // composer no longer asks people to categorise their life.
            'life_stage': widget.initialLifeStage ?? 'mid',
            'prompt_key': 'social_memory_$stamp',
            'prompt_text': fallbackTitle,
            'body': body,
            'share_to_family_feed': _shareToFamilyFeed,
            'memory_date_label': _whenController.text.trim(),
            'people': _peopleController.text.trim(),
            'location': _locationController.text.trim(),
            'mood': _selectedMood,
          })
          .select('id')
          .single();
      memoryId = (inserted['id'] ?? '').toString();
      if (memoryId.isEmpty) throw Exception('The memory could not be created.');

      await _uploadPhotos(userId, memoryId);
      await _uploadVoice(userId, memoryId);

      unawaited(
        IndexingService.indexMemory(
          vaultId: widget.vaultId,
          memoryId: memoryId,
        ).catchError((_) => 0),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast('Could not preserve this memory: ${e.message}');
    } catch (e) {
      _toast(
        memoryId == null
            ? 'Could not preserve this memory: $e'
            : 'The memory was saved, but some media could not be added: $e',
      );
      if (memoryId != null && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _profileRow() {
    final avatar = (widget.avatarUrl ?? '').trim();
    final name = (widget.displayName ?? '').trim();
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          child: avatar.isEmpty ? const Icon(Icons.person_outline) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Your vault' : name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _shareToFamilyFeed
                    ? 'Sharing with family'
                    : 'Only in your vault',
                style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _photoPreview() {
    if (_photos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final photo = _photos[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Image.memory(
                  photo.bytes,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _photos.removeAt(index)),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New memory'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Preserving…' : 'Preserve',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _profileRow(),
                const SizedBox(height: 22),
                TextField(
                  controller: _titleController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: 'Title this memory (optional)',
                    counterText: '',
                    prefixIcon: const Icon(Icons.title),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.42),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  minLines: 7,
                  maxLines: 16,
                  autofocus: widget.initialMode == 'text',
                  enabled: !_saving,
                  style: const TextStyle(fontSize: 18, height: 1.45),
                  decoration: InputDecoration(
                    hintText: 'What would you like to remember?',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_photos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _photoPreview(),
                ],
                if (_voices.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...List.generate(_voices.length, (index) {
                    final voice = _voices[index];
                    final isPlaying = _playingVoiceIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        elevation: 0,
                        color: const Color(0xFFF2E7F5),
                        child: ListTile(
                          leading: IconButton.filled(
                            tooltip: isPlaying ? 'Pause' : 'Listen to take',
                            onPressed: _saving
                                ? null
                                : () => _toggleVoicePreview(index),
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          title: Text('Voice note ${index + 1}'),
                          subtitle: Text(
                            '${_voiceLength(voice.seconds)} · ${isPlaying ? 'Playing' : 'Tap play to check this take'}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove this take',
                            onPressed: _saving
                                ? null
                                : () => _removeVoice(index),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickPhotos,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _photos.isEmpty ? 'Add photos' : 'More photos',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _recordVoice,
                      icon: const Icon(Icons.mic_none),
                      label: Text(
                        _voices.isEmpty
                            ? 'Record voice'
                            : 'Add another voice note',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 0,
                  color: Colors.white.withValues(alpha: 0.38),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Add details'),
                        subtitle: const Text(
                          'Mood, when, where, or who was there',
                        ),
                        trailing: Icon(
                          _showDetails ? Icons.expand_less : Icons.expand_more,
                        ),
                        onTap: () =>
                            setState(() => _showDetails = !_showDetails),
                      ),
                      if (_showDetails)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'How did this memory feel?',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      const [
                                        'Happy',
                                        'Playful',
                                        'Proud',
                                        'Grateful',
                                        'Nostalgic',
                                        'Calm',
                                        'Surprised',
                                        'Sad',
                                        'Difficult',
                                        'Mixed feelings',
                                      ].map((mood) {
                                        return ChoiceChip(
                                          label: Text(mood),
                                          selected: _selectedMood == mood,
                                          onSelected: _saving
                                              ? null
                                              : (selected) => setState(() {
                                                  _selectedMood = selected
                                                      ? mood
                                                      : null;
                                                }),
                                        );
                                      }).toList(),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _whenController,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                  labelText: 'When was this?',
                                  hintText:
                                      'For example: Summer 2019 or when I was 10',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _peopleController,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.people_outline),
                                  labelText: 'Who was there?',
                                  hintText: 'Names or a short description',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _locationController,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                  labelText: 'Where did it happen?',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: _shareToFamilyFeed,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _shareToFamilyFeed = value),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Share to family feed'),
                  subtitle: Text(
                    _shareToFamilyFeed
                        ? 'Your family can discover this memory in their feed.'
                        : 'This memory will stay only in your vault.',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    _saving ? 'Preserving memory…' : 'Preserve memory',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingPhoto {
  final String name;
  final Uint8List bytes;
  final String extension;

  const _PendingPhoto({
    required this.name,
    required this.bytes,
    required this.extension,
  });
}

class _PendingVoice {
  final RecordedAudio audio;
  final int seconds;

  const _PendingVoice({required this.audio, required this.seconds});
}
