import 'dart:async';
import 'record_memory_screen.dart';
import '../widgets/heiro_surface.dart';
import '../widgets/ai_processing_consent.dart';
import '../services/connection_status.dart';
import '../utils/public_error.dart';
import '../utils/vault_media_upload.dart';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/indexing_service.dart';
import '../services/push_notification_service.dart';
import '../services/memory_media_batch.dart';
import '../widgets/memory_media_upload_screen.dart';
import '../utils/everroot_upgrade_prompt.dart';
import '../utils/media_upload_policy.dart';
import '../utils/web_audio_recorder.dart';
import '../widgets/vault_media.dart';
import '../widgets/content_screening_permission.dart';
import '../widgets/memory_sharing_status.dart';

class CreateMemoryScreen extends StatefulWidget {
  final String vaultId;
  final String? initialLifeStage;
  final String initialMode;
  final String? displayName;
  final String? avatarUrl;
  final WebAudioRecorder? recorder;

  const CreateMemoryScreen({
    super.key,
    required this.vaultId,
    this.initialLifeStage,
    this.initialMode = 'text',
    this.displayName,
    this.avatarUrl,
    this.recorder,
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
  late final WebAudioRecorder _recorder =
      widget.recorder ?? createWebAudioRecorder();
  final AudioPlayer _previewPlayer = AudioPlayer();

  final List<_PendingPhoto> _photos = [];
  final List<_PendingVoice> _voices = [];
  int? _playingVoiceIndex;
  String? _selectedMood;
  bool _showDetails = false;
  bool _saving = false;
  bool _pickingPhotos = false;
  bool _recordingVoice = false;
  final _connection = ConnectionStatus.instance;
  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  bool _shareToFamilyFeed = true;

  static const _voiceBucket = 'memory_voice';

  @override
  void initState() {
    super.initState();
    _connection.addListener(_connectionChanged);
    _connection.attach();
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
    _connection.removeListener(_connectionChanged);
    _connection.detach();
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

  Future<bool> _showQuotaPromptIfNeeded(Object error) async {
    if (!isEverRootFamilyUpgradeError(error) || !mounted) return false;

    await showEverRootFamilyUpgradePrompt(
      context,
      message: everRootUploadErrorMessage(error),
    );
    return true;
  }

  String _extension(String name) {
    return MediaUploadPolicy.extensionForName(name, fallback: 'jpg');
  }

  String _imageMime(String extension) =>
      MediaUploadPolicy.contentTypeForExtension(extension);

  Future<void> _pickPhotos() async {
    if (_pickingPhotos || _saving) return;
    final available = MediaUploadPolicy.photoBatchMaxCount - _photos.length;
    if (available <= 0) {
      _toast('This batch has 20 items. Remove one before selecting more.');
      return;
    }
    setState(() => _pickingPhotos = true);
    try {
      final result = await pickVaultMedia(
        context,
        allowMultiple: true,
        maxFiles: available,
        remainingBytes:
            MediaUploadPolicy.pendingMediaMaxBytes -
            _photos.fold<int>(0, (sum, p) => sum + p.bytes.length),
      );
      if (result == null) return;

      final selected = <_PendingPhoto>[];
      String? rejectedMessage;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;

        try {
          final image = await VaultMediaUpload.prepare(
            bytes,
            fileName: file.name,
            contentType: _imageMime(_extension(file.name)),
          );
          selected.add(
            _PendingPhoto(
              name: file.name,
              bytes: image.bytes,
              extension: image.extension,
              contentType: image.contentType,
            ),
          );
        } on MediaUploadException catch (e) {
          rejectedMessage ??= e.message;
        }
      }

      if (!mounted) return;
      setState(() {
        _photos.addAll(selected);
      });
      if (rejectedMessage != null) {
        _toast(rejectedMessage);
      }
    } catch (e) {
      _toast(e is MediaUploadException ? e.message : publicErrorMessage(e));
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _recordVoice() async {
    if (_saving || _recordingVoice || !_recorder.isSupported) {
      if (!_recorder.isSupported) {
        _toast('Recording is not supported on this device yet.');
      }
      return;
    }
    setState(() => _recordingVoice = true);
    try {
      final userId = _client.auth.currentUser?.id;
      await _previewPlayer.stop();
      if (!mounted) return;
      setState(() => _playingVoiceIndex = null);
      final recorded = await Navigator.push<RecordedMemoryVoice>(
        context,
        MaterialPageRoute(
          builder: (_) => RecordMemoryScreen(
            recorder: _recorder,
            defaultTitle: 'Voice note ${_voices.length + 1}',
          ),
        ),
      );
      if (recorded == null ||
          !mounted ||
          userId != _client.auth.currentUser?.id) {
        return;
      }
      final voiceError = MediaUploadPolicy.validateBytes(
        MediaUploadKind.voice,
        recorded.audio.bytes.length,
        fileName: 'voice.${recorded.audio.extension}',
        contentType: recorded.audio.mimeType,
      );
      if (voiceError != null) {
        _toast(voiceError);
        return;
      }
      setState(
        () => _voices.add(
          _PendingVoice(
            audio: recorded.audio,
            seconds: recorded.seconds,
            title: recorded.title,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _recordingVoice = false);
    }
  }

  Future<void> _renamePendingVoice(int index) async {
    final voice = _voices[index];
    final controller = TextEditingController(text: voice.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Recording name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The route transition can still be using the field after the result resolves.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (name != null && mounted && _voices.contains(voice)) {
      setState(() => voice.title = name);
    }
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
      _toast(publicErrorMessage(e));
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
    if (_photos.isEmpty || !mounted) return;
    if (_client.auth.currentUser?.id != userId) {
      throw const AuthException('Account changed.');
    }
    await showMemoryMediaUpload(
      context,
      autoStart: true,
      batch: MemoryMediaBatch(
        client: _client,
        target: MemoryMediaTarget.personal(
          vaultId: widget.vaultId,
          memoryId: memoryId,
        ),
        media: _photos
            .map(
              (p) => PendingMemoryMedia(
                name: p.name,
                bytes: p.bytes,
                extension: p.extension,
                contentType: p.contentType,
              ),
            )
            .toList(),
      ),
    );
    if (_client.auth.currentUser?.id != userId || !mounted) {
      throw const AuthException('Account changed.');
    }
  }

  Future<void> _uploadVoice(String userId, String memoryId) async {
    final transcribe =
        _voices.isNotEmpty &&
        mounted &&
        await requestAiProcessingConsent(context) &&
        mounted;
    for (var index = 0; index < _voices.length; index++) {
      final audio = _voices[index].audio;
      MediaUploadPolicy.validateListOrThrow(
        MediaUploadKind.voice,
        audio.bytes,
        fileName: 'voice.${audio.extension}',
        contentType: audio.mimeType,
      );
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
            'title': _voices[index].title,
            'duration_seconds': _voices[index].seconds,
          })
          .select('id')
          .maybeSingle();

      final voiceId = (inserted?['id'] ?? '').toString();
      if (voiceId.isEmpty || !transcribe) continue;
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
    if (_saving || _pickingPhotos || _recordingVoice) return;
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
      if (!await _connection.check() || !mounted) {
        _toast('Reconnect to preserve this memory. Your text is still here.');
        return;
      }
      final fallbackTitle = title.isNotEmpty
          ? title
          : body.isNotEmpty
          ? ''
          : (_voices.isNotEmpty ? 'Voice memory' : 'Media memory');
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
      if (_shareToFamilyFeed && !contentScreeningControlsEnabled) {
        unawaited(PushNotificationService.notifyFamilyMemoryAdded(memoryId));
      }

      if (!mounted) return;
      if (contentScreeningControlsEnabled && _shareToFamilyFeed) {
        await showMemorySharingStatus(
          context,
          kind: 'memory',
          targetId: memoryId,
          client: _client,
          expectedUserId: userId,
          requestAfterSave: true,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!await _showQuotaPromptIfNeeded(e)) {
        _toast(publicErrorMessage(e));
      }
    } catch (e) {
      _connection.report(e);
      if (await _showQuotaPromptIfNeeded(e)) {
        if (memoryId != null && mounted) Navigator.pop(context, true);
        return;
      }
      _toast(
        memoryId == null
            ? publicErrorMessage(e)
            : 'The memory was saved, but some media could not be added. Reconnect and check it before trying again.',
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
                    ? (contentScreeningControlsEnabled
                          ? 'Sharing requested'
                          : 'Sharing with family')
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
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  width: 150,
                  height: 150,
                  color: Colors.black.withValues(alpha: 0.04),
                  child: MediaUploadPolicy.isVideo(photo.name)
                      ? PendingVideoPreview(
                          bytes: photo.bytes,
                          name: photo.name,
                        )
                      : Image.memory(
                          photo.bytes,
                          width: 150,
                          height: 150,
                          cacheWidth: 360,
                          fit: BoxFit.contain,
                        ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove media ${index + 1}',
                    onPressed: _saving || _pickingPhotos
                        ? null
                        : () => setState(() => _photos.removeAt(index)),
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
    return HeiroSurface(
      child: Scaffold(
        appBar: AppBar(title: const Text('New memory')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  if (_connection.offline)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'You are offline. Reconnect to preserve this memory. Your text stays here while this screen is open.',
                      ),
                    ),
                  _profileRow(),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _titleController,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onEditingComplete: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    maxLength: 100,
                    decoration: InputDecoration(
                      hintText: 'Title this memory (optional)',
                      counterText: '',
                      prefixIcon: const Icon(Icons.title),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.42),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyController,
                    minLines: 4,
                    maxLines: 16,
                    autofocus: widget.initialMode == 'text',
                    enabled: !_saving,
                    style: const TextStyle(fontSize: 18, height: 1.45),
                    decoration: InputDecoration(
                      hintText: 'What would you like to remember?',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.55),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      '${_photos.length} / ${MediaUploadPolicy.photoBatchMaxCount} selected',
                    ),
                    const SizedBox(height: 8),
                    _photoPreview(),
                  ],
                  if (_pickingPhotos)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(
                        semanticsLabel: 'Preparing selected media',
                      ),
                    ),
                  if (_voices.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ...List.generate(_voices.length, (index) {
                      final voice = _voices[index];
                      final isPlaying = _playingVoiceIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          elevation: 0,
                          color: heiroIce,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            title: Text(voice.title),
                            subtitle: Text(
                              '${_voiceLength(voice.seconds)}${isPlaying ? ' · Playing' : ''}',
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Recording options',
                              enabled: !_saving,
                              onSelected: (action) {
                                if (action == 'rename') {
                                  _renamePendingVoice(index);
                                }
                                if (action == 'remove') _removeVoice(index);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove'),
                                ),
                              ],
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
                        onPressed: _saving || _pickingPhotos
                            ? null
                            : _pickPhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _photos.isEmpty ? 'Add media' : 'More media',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving || _recordingVoice
                            ? null
                            : _recordVoice,
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
                          trailing: Icon(
                            _showDetails
                                ? Icons.expand_less
                                : Icons.expand_more,
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
                                  textInputAction: TextInputAction.done,
                                  onEditingComplete: () => FocusManager
                                      .instance
                                      .primaryFocus
                                      ?.unfocus(),
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
                                  textInputAction: TextInputAction.done,
                                  onEditingComplete: () => FocusManager
                                      .instance
                                      .primaryFocus
                                      ?.unfocus(),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.people_outline),
                                    labelText: 'Who was there?',
                                    hintText: 'Names or a short description',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _locationController,
                                  textInputAction: TextInputAction.done,
                                  onEditingComplete: () => FocusManager
                                      .instance
                                      .primaryFocus
                                      ?.unfocus(),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.location_on_outlined,
                                    ),
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
                    onPressed:
                        _saving ||
                            _pickingPhotos ||
                            _recordingVoice ||
                            _connection.offline
                        ? null
                        : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      _saving ? 'Preserving memory…' : 'Preserve memory',
                    ),
                  ),
                ],
              ),
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
  final String contentType;

  const _PendingPhoto({
    required this.name,
    required this.bytes,
    required this.extension,
    required this.contentType,
  });
}

class _PendingVoice {
  final RecordedAudio audio;
  final int seconds;

  String title;

  _PendingVoice({
    required this.audio,
    required this.seconds,
    required this.title,
  });
}
