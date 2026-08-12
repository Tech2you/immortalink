import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_branch_screen.dart';
import 'vault_companion_screen.dart';
import '../utils/media_upload_policy.dart';
import '../utils/web_audio_recorder.dart';

class LegacyVaultScreen extends StatefulWidget {
  final String legacyMemberId;
  final String familyId;

  const LegacyVaultScreen({
    super.key,
    required this.legacyMemberId,
    required this.familyId,
  });

  @override
  State<LegacyVaultScreen> createState() => _LegacyVaultScreenState();
}

class _LegacyVaultScreenState extends State<LegacyVaultScreen> {
  final _supabase = Supabase.instance.client;
  final WebAudioRecorder _recorder = createWebAudioRecorder();
  final AudioPlayer _voicePlayer = AudioPlayer();

  static const String _photosBucket = 'vault_photos';
  static const String _memoryVoiceBucket = 'memory_voice';

  bool _loading = true;
  bool _savingProfile = false;
  bool _deletingProfile = false;
  bool _uploadingPhoto = false;
  bool _uploadingProfilePhoto = false;
  bool _loadingPhotos = true;
  bool _loadingMemories = true;
  bool _loadingMemoryPhotos = true;
  bool _loadingMemoryVoice = true;
  bool _showExtraDetails = false;
  int _selectedLegacySection = 0;

  String? _error;
  String? _photoError;
  String? _memoryError;
  String? _memoryPhotoError;
  String? _memoryVoiceError;
  String? _playingVoiceKey;

  Map<String, dynamic>? _row;

  String? _profilePhotoId;
  String? _profilePhotoPath;
  String? _profilePhotoUrl;

  List<Map<String, String>> _photos = [];
  List<Map<String, dynamic>> _memories = [];
  final Map<String, List<Map<String, String>>> _memoryPhotosById = {};
  final Map<String, List<_LegacyVoiceNote>> _memoryVoiceById = {};

  final _nameController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _deathYearController = TextEditingController();
  final _aboutController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _voicePlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceKey = null);
    });
    _load();
  }

  @override
  void dispose() {
    if (_recorder.isRecording) unawaited(_recorder.cancel());
    _recorder.dispose();
    _voicePlayer.dispose();
    _nameController.dispose();
    _birthYearController.dispose();
    _deathYearController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openLegacyAi() async {
    final row = _row;
    if (row == null) {
      _toast('Legacy profile is not loaded yet.');
      return;
    }

    final displayName = _titleFromRow(row);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultCompanionScreen(
          legacyMemberId: widget.legacyMemberId,
          familyId: widget.familyId,
          displayName: displayName,
        ),
      ),
    );
  }

  bool _canOpenAncestorBranch(String slotKey) {
    return slotKey == 'mother' ||
        slotKey == 'father' ||
        slotKey == 'maternal_gm' ||
        slotKey == 'maternal_gf' ||
        slotKey == 'paternal_gm' ||
        slotKey == 'paternal_gf' ||
        slotKey == 'maternal_ggm' ||
        slotKey == 'maternal_ggf' ||
        slotKey == 'paternal_ggm' ||
        slotKey == 'paternal_ggf';
  }

  bool _canOpenDescendantBranch(String slotKey) {
    return slotKey == 'child_1' ||
        slotKey == 'child_2' ||
        slotKey == 'child_3' ||
        slotKey == 'child_4' ||
        slotKey == 'grandchild_1' ||
        slotKey == 'grandchild_2' ||
        slotKey == 'grandchild_3' ||
        slotKey == 'grandchild_4' ||
        slotKey == 'greatgrandchild_1' ||
        slotKey == 'greatgrandchild_2' ||
        slotKey == 'greatgrandchild_3' ||
        slotKey == 'greatgrandchild_4';
  }

  String? _branchDirectionForSlot(String slotKey) {
    if (_canOpenAncestorBranch(slotKey)) return 'ancestor';
    if (_canOpenDescendantBranch(slotKey)) return 'descendant';
    return null;
  }

  String _branchLabelForSlot(String slotKey) {
    switch (slotKey) {
      case 'mother':
        return 'Mother';
      case 'father':
        return 'Father';
      case 'maternal_gm':
      case 'paternal_gm':
        return 'Grandmother';
      case 'maternal_gf':
      case 'paternal_gf':
        return 'Grandfather';
      case 'maternal_ggm':
      case 'paternal_ggm':
        return 'Great-grandmother';
      case 'maternal_ggf':
      case 'paternal_ggf':
        return 'Great-grandfather';
      case 'child_1':
      case 'child_2':
      case 'child_3':
      case 'child_4':
        return 'Child';
      case 'grandchild_1':
      case 'grandchild_2':
      case 'grandchild_3':
      case 'grandchild_4':
        return 'Grandchild';
      case 'greatgrandchild_1':
      case 'greatgrandchild_2':
      case 'greatgrandchild_3':
      case 'greatgrandchild_4':
        return 'Great-grandchild';
      default:
        return 'Branch';
    }
  }

  Future<void> _openBranch() async {
    final row = _row;
    if (row == null) {
      _toast('Profile is not loaded yet.');
      return;
    }

    final slotKey = (row['slot_key'] ?? '').toString().trim();
    final direction = _branchDirectionForSlot(slotKey);

    if (slotKey.isEmpty || direction == null) {
      _toast('This profile does not have a deeper branch view yet.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyBranchScreen(
          familyId: widget.familyId,
          rootLabel: _branchLabelForSlot(slotKey),
          rootSlotKey: slotKey,
          direction: direction,
        ),
      ),
    );

    await _load();
  }

  int? _parseYear(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  String _titleFromRow(Map<String, dynamic>? row) {
    final name = (row?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final display = (row?['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    return 'Legacy predecessor';
  }

  String _subtitleFromRow(Map<String, dynamic>? row) {
    final birth = row?['birth_year'];
    final b = birth == null ? '' : birth.toString();
    if (b.isNotEmpty) return 'Born $b';
    return 'Family-owned predecessor profile';
  }

  String _detailsLabel(Map<String, dynamic>? row) {
    final birth = row?['birth_year'];
    final death = row?['death_year'];

    final b = birth == null ? '' : birth.toString();
    final d = death == null ? '' : death.toString();

    if (b.isEmpty && d.isEmpty) return 'No extra details yet';
    if (b.isNotEmpty && d.isEmpty) return 'Birth year: $b';
    if (b.isEmpty && d.isNotEmpty) return 'Death year: $d';
    return 'Birth year: $b   •   Death year: $d';
  }

  String _prettyStage(String s) {
    switch (s) {
      case 'early':
        return 'Early life';
      case 'mid':
        return 'Mid life';
      case 'late':
        return 'Late life';
      default:
        return s;
    }
  }

  String _extFromName(String name) {
    return MediaUploadPolicy.extensionForName(name, fallback: 'jpg');
  }

  String _contentTypeFromExt(String ext) {
    return MediaUploadPolicy.contentTypeForExtension(ext);
  }

  bool _isProfilePhotoPath(String path) {
    final p = path.toLowerCase();
    return p.contains('/profile_picture/');
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    try {
      final signed = await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _supabase
          .from('legacy_family_members')
          .select(
            'id, family_id, slot_key, name, display_name, birth_year, death_year, about_me_text, avatar_path, created_by, created_at, updated_at, replaced_by_vault_id',
          )
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .maybeSingle();

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _row = null;
          _error = 'Legacy predecessor not found.';
          _loading = false;
        });
        return;
      }

      final row = Map<String, dynamic>.from(res);
      _row = row;

      _nameController.text = (row['name'] ?? '').toString();
      _birthYearController.text = row['birth_year'] == null
          ? ''
          : row['birth_year'].toString();
      _deathYearController.text = row['death_year'] == null
          ? ''
          : row['death_year'].toString();
      _aboutController.text = (row['about_me_text'] ?? '').toString();

      setState(() {
        _loading = false;
      });

      await _loadPhotos();
      await _loadMemories();
      await _loadMemoryPhotos();
      await _loadMemoryVoice();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
    if (!mounted) return;

    setState(() {
      _loadingPhotos = true;
      _photoError = null;
      _photos = [];
      _profilePhotoId = null;
      _profilePhotoPath = null;
      _profilePhotoUrl = null;
    });

    try {
      final currentRow = _row;
      final dbAvatarPath = (currentRow?['avatar_path'] ?? '').toString().trim();

      final rows = await _supabase
          .from('legacy_member_photos')
          .select('id, path, created_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();
      final items = <Map<String, String>>[];

      String? profileId;
      String? profilePath;
      String? profileUrl;

      if (dbAvatarPath.isNotEmpty) {
        final url = await _signedUrl(_photosBucket, dbAvatarPath);
        if (url != null && url.trim().isNotEmpty) {
          profilePath = dbAvatarPath;
          profileUrl = url;

          for (final r in list) {
            final candidateId = (r['id'] ?? '').toString();
            final candidatePath = (r['path'] ?? '').toString().trim();
            if (candidatePath == dbAvatarPath) {
              profileId = candidateId;
              break;
            }
          }
        }
      }

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        if (id.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_photosBucket, path);
        if (url == null || url.trim().isNotEmpty == false) continue;

        final isProfile = path == profilePath || _isProfilePhotoPath(path);
        if (isProfile) {
          if (profilePath == null) {
            profileId = id;
            profilePath = path;
            profileUrl = url;
          }
          continue;
        }

        items.add({'id': id, 'path': path, 'url': url});
      }

      if (!mounted) return;
      setState(() {
        _profilePhotoId = profileId;
        _profilePhotoPath = profilePath;
        _profilePhotoUrl = profileUrl;
        _photos = items;
        _loadingPhotos = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _photoError = e.message;
        _loadingPhotos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoError = e.toString();
        _loadingPhotos = false;
      });
    }
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;

    setState(() {
      _loadingMemories = true;
      _memoryError = null;
      _memories = [];
    });

    try {
      final rows = await _supabase
          .from('legacy_memories')
          .select(
            'id, life_stage, prompt_key, prompt_text, body, created_at, updated_at, memory_date_label, people, location, mood',
          )
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _memories = (rows as List).cast<Map<String, dynamic>>();
        _loadingMemories = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryError = e.message;
        _loadingMemories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryError = e.toString();
        _loadingMemories = false;
      });
    }
  }

  Future<void> _loadMemoryPhotos() async {
    if (!mounted) return;

    setState(() {
      _loadingMemoryPhotos = true;
      _memoryPhotoError = null;
      _memoryPhotosById.clear();
    });

    try {
      final rows = await _supabase
          .from('legacy_memory_photos')
          .select('id, legacy_memory_id, path, created_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['legacy_memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();

        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_photosBucket, path);
        if (url == null || url.trim().isEmpty) continue;

        _memoryPhotosById.putIfAbsent(memoryId, () => []).add({
          'id': id,
          'path': path,
          'url': url,
        });
      }

      if (!mounted) return;
      setState(() {
        _loadingMemoryPhotos = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryPhotoError = e.message;
        _loadingMemoryPhotos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryPhotoError = e.toString();
        _loadingMemoryPhotos = false;
      });
    }
  }

  String _memoryVoicePrefix(String userId, String memoryId) =>
      '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/memories/$memoryId/voice';

  String _friendlyVoiceTitle(String storedTitle) {
    final title = storedTitle.trim();
    if (title.isEmpty ||
        RegExp(
          r'^Recorded \d+\.(webm|m4a|mp3|wav|aac|ogg)$',
          caseSensitive: false,
        ).hasMatch(title)) {
      return 'Voice note';
    }
    return title;
  }

  Future<void> _loadMemoryVoice() async {
    if (!mounted) return;

    setState(() {
      _loadingMemoryVoice = true;
      _memoryVoiceError = null;
      _memoryVoiceById.clear();
    });

    try {
      final rows = await _supabase
          .from('legacy_memory_voice_notes')
          .select('id, legacy_memory_id, path, title, created_at')
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['legacy_memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        final title = (r['title'] ?? '').toString().trim();
        final createdAt = (r['created_at'] ?? '').toString();

        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_memoryVoiceBucket, path);
        if (url == null || url.trim().isEmpty) continue;

        _memoryVoiceById
            .putIfAbsent(memoryId, () => [])
            .add(
              _LegacyVoiceNote(
                id: id,
                path: path,
                title: _friendlyVoiceTitle(title),
                url: url,
                createdAt: createdAt,
              ),
            );
      }

      if (!mounted) return;
      setState(() => _loadingMemoryVoice = false);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryVoiceError = e.message;
        _loadingMemoryVoice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memoryVoiceError = e.toString();
        _loadingMemoryVoice = false;
      });
    }
  }

  String _voiceLength(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggleVoice(_LegacyVoiceNote note) async {
    final key = 'legacy_voice:${note.id}';
    try {
      if (_playingVoiceKey == key) {
        await _voicePlayer.pause();
        if (mounted) setState(() => _playingVoiceKey = null);
        return;
      }

      await _voicePlayer.stop();
      await _voicePlayer.play(UrlSource(note.url));
      if (mounted) setState(() => _playingVoiceKey = key);
    } catch (e) {
      _toast('Could not play voice note: $e');
    }
  }

  Future<void> _togglePendingVoice(
    List<_LegacyPendingVoice> voices,
    int index,
    VoidCallback refresh,
  ) async {
    if (index < 0 || index >= voices.length) return;

    final key = 'pending_voice:$index';
    try {
      if (_playingVoiceKey == key) {
        await _voicePlayer.pause();
        _playingVoiceKey = null;
        refresh();
        return;
      }

      await _voicePlayer.stop();
      final audio = voices[index].audio;
      final localPath = audio.localPath;
      await _voicePlayer.play(
        localPath == null
            ? BytesSource(Uint8List.fromList(audio.bytes))
            : DeviceFileSource(localPath),
      );
      _playingVoiceKey = key;
      refresh();
    } catch (e) {
      _toast('Could not play this voice take: $e');
    }
  }

  Future<_LegacyPendingVoice?> _recordLegacyVoiceTake() async {
    if (!_recorder.isSupported) {
      _toast('Recording is not supported on this device yet.');
      return null;
    }

    String? error;
    int seconds = 0;
    bool stopping = false;
    bool startScheduled = false;
    DateTime? startedAt;
    Timer? timer;

    final recorded =
        await showModalBottomSheet<({RecordedAudio audio, int seconds})>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              void updateElapsed() {
                final started = startedAt;
                if (started == null) return;
                seconds = DateTime.now().difference(started).inSeconds;
              }

              Future<void> start() async {
                if (_recorder.isRecording || stopping || error != null) return;
                try {
                  await _recorder.start();
                  startedAt = DateTime.now();
                  seconds = 0;
                  if (sheetContext.mounted) setSheetState(() {});
                  timer?.cancel();
                  timer = Timer.periodic(const Duration(seconds: 1), (_) {
                    updateElapsed();
                    if (sheetContext.mounted) setSheetState(() {});
                  });
                } catch (e) {
                  if (sheetContext.mounted) {
                    setSheetState(() => error = e.toString());
                  }
                }
              }

              if (!startScheduled) {
                startScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) => start());
              }
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
                        'Recording voice note',
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
                                        updateElapsed();
                                        final audio = await _recorder.stop();
                                        if (sheetContext.mounted) {
                                          Navigator.pop(sheetContext, (
                                            audio: audio,
                                            seconds: seconds <= 0 ? 1 : seconds,
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
    if (recorded == null) return null;
    final voiceError = MediaUploadPolicy.validateBytes(
      MediaUploadKind.voice,
      recorded.audio.bytes.length,
      fileName: 'voice.${recorded.audio.extension}',
      contentType: recorded.audio.mimeType,
    );
    if (voiceError != null) {
      _toast(voiceError);
      return null;
    }
    return _LegacyPendingVoice(
      audio: recorded.audio,
      seconds: recorded.seconds,
    );
  }

  Future<void> _uploadPhoto() async {
    try {
      setState(() => _uploadingPhoto = true);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      final ext = _extFromName(file.name);
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.photo,
        bytes,
        fileName: file.name,
        contentType: _contentTypeFromExt(ext),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/gallery/$ts.$ext';

      await _supabase.storage
          .from(_photosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase.from('legacy_member_photos').insert({
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });

      await _loadPhotos();
      _toast('Photo added.');
    } catch (e) {
      _toast('Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _uploadOrReplaceProfilePhoto() async {
    try {
      setState(() => _uploadingProfilePhoto = true);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      final oldProfilePath = (_profilePhotoPath ?? '').trim();
      final oldProfileId = (_profilePhotoId ?? '').trim();

      final ext = _extFromName(file.name);
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.avatarPhoto,
        bytes,
        fileName: file.name,
        contentType: _contentTypeFromExt(ext),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final newPath =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/profile_picture/$ts.$ext';

      await _supabase.storage
          .from(_photosBucket)
          .uploadBinary(
            newPath,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase
          .from('legacy_family_members')
          .update({
            'avatar_path': newPath,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      if (oldProfileId.isNotEmpty) {
        await _supabase
            .from('legacy_member_photos')
            .delete()
            .eq('id', oldProfileId)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      await _supabase.from('legacy_member_photos').insert({
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': newPath,
      });

      if (oldProfilePath.isNotEmpty && oldProfilePath != newPath) {
        await _supabase.storage.from(_photosBucket).remove([oldProfilePath]);
      }

      await _load();
      _toast('Profile picture updated.');
    } catch (e) {
      _toast('Profile picture upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingProfilePhoto = false);
    }
  }

  Future<void> _deletePhoto(Map<String, String> photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This will permanently delete this photo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final id = (photo['id'] ?? '').trim();
      final path = (photo['path'] ?? '').trim();

      if (path.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove([path]);
      }

      if (id.isNotEmpty) {
        await _supabase
            .from('legacy_member_photos')
            .delete()
            .eq('id', id)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      await _loadPhotos();
      _toast('Photo deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final birthYear = _parseYear(_birthYearController.text);
    final deathYear = _parseYear(_deathYearController.text);
    final about = _aboutController.text.trim();

    if (name.isEmpty) {
      _toast('Name is required.');
      return;
    }

    if (_birthYearController.text.trim().isNotEmpty && birthYear == null) {
      _toast('Birth year must be a valid number.');
      return;
    }

    if (_deathYearController.text.trim().isNotEmpty && deathYear == null) {
      _toast('Death year must be a valid number.');
      return;
    }

    setState(() => _savingProfile = true);

    try {
      await _supabase
          .from('legacy_family_members')
          .update({
            'name': name,
            'birth_year': birthYear,
            'death_year': deathYear,
            'about_me_text': about.isEmpty ? null : about,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _load();
      _toast('Legacy profile saved.');
    } on PostgrestException catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _deleteProfile() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete legacy predecessor?'),
        content: const Text(
          'This removes the family-owned predecessor profile from the tree. Use this if the real person later joins and creates their own vault.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deletingProfile = true);

    try {
      final photoPaths = <String>[
        ..._photos
            .map((p) => (p['path'] ?? '').trim())
            .where((p) => p.isNotEmpty),
        if ((_profilePhotoPath ?? '').trim().isNotEmpty)
          _profilePhotoPath!.trim(),
      ];

      if (photoPaths.isNotEmpty) {
        await _supabase.storage
            .from(_photosBucket)
            .remove(photoPaths.toSet().toList());
      }

      await _supabase
          .from('legacy_family_members')
          .delete()
          .eq('id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _deletingProfile = false);
    }
  }

  Future<void> _openAddMemory() async {
    final result = await _showLegacyMemoryEditor(
      title: 'New memory',
      actionLabel: 'Preserve memory',
    );

    if (result == null) return;

    final promptText = result.promptText.trim();
    final body = result.body.trim();
    final lifeStage = result.lifeStage.trim();
    final mood = result.mood.trim();
    final when = result.memoryDateLabel.trim();
    final people = result.people.trim();
    final location = result.location.trim();

    if (body.isEmpty && result.photos.isEmpty && result.voices.isEmpty) {
      _toast('Write something, add a photo, or record a voice note first.');
      return;
    }

    try {
      final inserted = await _supabase
          .from('legacy_memories')
          .insert({
            'legacy_member_id': widget.legacyMemberId,
            'family_id': widget.familyId,
            'life_stage': lifeStage,
            'prompt_key': 'legacy_memory',
            'prompt_text': promptText,
            'body': body,
            'memory_date_label': when.isEmpty ? null : when,
            'people': people.isEmpty ? null : people,
            'location': location.isEmpty ? null : location,
            'mood': mood.isEmpty ? null : mood,
          })
          .select('id')
          .single();

      final memoryId = (inserted['id'] ?? '').toString();
      if (memoryId.isEmpty) throw Exception('The memory could not be created.');

      await _uploadPendingMemoryPhotos(memoryId, result.photos);
      await _uploadPendingMemoryVoice(memoryId, result.voices);

      await _loadMemories();
      await _loadMemoryPhotos();
      await _loadMemoryVoice();
      _toast('Memory added.');
    } on PostgrestException catch (e) {
      _toast('Add memory failed: ${e.message}');
    } catch (e) {
      _toast('Add memory failed: $e');
    }
  }

  Future<void> _editMemory(Map<String, dynamic> memory) async {
    final memoryId = (memory['id'] ?? '').toString();
    if (memoryId.isEmpty) return;

    final result = await _showLegacyMemoryEditor(
      title: 'Edit memory',
      actionLabel: 'Save changes',
      memoryId: memoryId,
      initialStage: (memory['life_stage'] ?? 'mid').toString(),
      initialPrompt: (memory['prompt_text'] ?? '').toString(),
      initialBody: (memory['body'] ?? '').toString(),
      initialMood: (memory['mood'] ?? '').toString(),
      initialWhen: (memory['memory_date_label'] ?? '').toString(),
      initialPeople: (memory['people'] ?? '').toString(),
      initialLocation: (memory['location'] ?? '').toString(),
    );

    if (result == null) return;

    final promptText = result.promptText.trim();
    final body = result.body.trim();
    final lifeStage = result.lifeStage.trim();
    final mood = result.mood.trim();
    final when = result.memoryDateLabel.trim();
    final people = result.people.trim();
    final location = result.location.trim();

    final existingPhotos = _memoryPhotosById[memoryId] ?? [];
    final existingVoices = _memoryVoiceById[memoryId] ?? [];
    if (body.isEmpty &&
        existingPhotos.isEmpty &&
        existingVoices.isEmpty &&
        result.photos.isEmpty &&
        result.voices.isEmpty) {
      _toast('Write something, add a photo, or record a voice note first.');
      return;
    }

    try {
      await _supabase
          .from('legacy_memories')
          .update({
            'life_stage': lifeStage,
            'prompt_text': promptText,
            'body': body,
            'memory_date_label': when.isEmpty ? null : when,
            'people': people.isEmpty ? null : people,
            'location': location.isEmpty ? null : location,
            'mood': mood.isEmpty ? null : mood,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', memoryId)
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _uploadPendingMemoryPhotos(memoryId, result.photos);
      await _uploadPendingMemoryVoice(memoryId, result.voices);

      await _loadMemories();
      await _loadMemoryPhotos();
      await _loadMemoryVoice();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<_LegacyMemoryEditResult?> _showLegacyMemoryEditor({
    required String title,
    required String actionLabel,
    String? memoryId,
    String initialStage = 'mid',
    String initialPrompt = '',
    String initialBody = '',
    String initialMood = '',
    String initialWhen = '',
    String initialPeople = '',
    String initialLocation = '',
  }) async {
    final promptController = TextEditingController(text: initialPrompt);
    final bodyController = TextEditingController(text: initialBody);
    final whenController = TextEditingController(text: initialWhen);
    final peopleController = TextEditingController(text: initialPeople);
    final locationController = TextEditingController(text: initialLocation);
    final pendingPhotos = <_LegacyPendingPhoto>[];
    final pendingVoices = <_LegacyPendingVoice>[];
    var stage = initialStage.trim().isEmpty ? 'mid' : initialStage.trim();
    String? selectedMood = initialMood.trim().isEmpty
        ? null
        : initialMood.trim();
    var showDetails =
        selectedMood != null ||
        stage != 'mid' ||
        whenController.text.trim().isNotEmpty ||
        peopleController.text.trim().isNotEmpty ||
        locationController.text.trim().isNotEmpty;
    final displayName = _titleFromRow(_row);
    final hasPhoto = (_profilePhotoUrl ?? '').trim().isNotEmpty;

    final result = await showDialog<_LegacyMemoryEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final existingPhotos = memoryId == null
              ? const <Map<String, String>>[]
              : _memoryPhotosById[memoryId] ?? const <Map<String, String>>[];
          final existingVoices = memoryId == null
              ? const <_LegacyVoiceNote>[]
              : _memoryVoiceById[memoryId] ?? const <_LegacyVoiceNote>[];

          _LegacyMemoryEditResult memoryResult() => _LegacyMemoryEditResult(
            lifeStage: stage,
            promptText: promptController.text.trim(),
            body: bodyController.text.trim(),
            mood: selectedMood ?? '',
            memoryDateLabel: whenController.text.trim(),
            people: peopleController.text.trim(),
            location: locationController.text.trim(),
            photos: List.unmodifiable(pendingPhotos),
            voices: List.unmodifiable(pendingVoices),
          );

          Future<void> pickPendingPhotos() async {
            try {
              final picked = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: true,
                withData: true,
              );
              if (picked == null) return;

              final selected = <_LegacyPendingPhoto>[];
              String? rejectedMessage;
              for (final file in picked.files) {
                final bytes = file.bytes;
                if (bytes == null) continue;

                final message = MediaUploadPolicy.validateBytes(
                  MediaUploadKind.photo,
                  bytes.length,
                  fileName: file.name,
                );
                if (message != null) {
                  rejectedMessage ??= message;
                  continue;
                }

                selected.add(
                  _LegacyPendingPhoto(
                    name: file.name,
                    bytes: bytes,
                    extension: _extFromName(file.name),
                  ),
                );
              }

              final available =
                  10 - existingPhotos.length - pendingPhotos.length;
              final accepted = selected.take(available).toList();
              setDialogState(() => pendingPhotos.addAll(accepted));

              if (selected.length > available) {
                _toast('You can add up to 10 photos to one memory.');
              }
              if (rejectedMessage != null) {
                _toast(rejectedMessage);
              }
            } catch (e) {
              _toast('Could not add photos: $e');
            }
          }

          Future<void> recordPendingVoice() async {
            final voice = await _recordLegacyVoiceTake();
            if (voice == null || !dialogContext.mounted) return;
            setDialogState(() => pendingVoices.add(voice));
          }

          Future<void> submitMemory() async {
            if (promptController.text.trim().isNotEmpty) {
              Navigator.pop(dialogContext, memoryResult());
              return;
            }

            final keepUntitled = await showDialog<bool>(
              context: dialogContext,
              builder: (confirmContext) => AlertDialog(
                title: const Text('Preserve without a title?'),
                content: const Text(
                  'You can add this memory without a title and let the story speak for itself.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(confirmContext, false),
                    child: const Text('Add title'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(confirmContext, true),
                    child: const Text('Preserve without title'),
                  ),
                ],
              ),
            );

            if (keepUntitled == true && dialogContext.mounted) {
              Navigator.pop(dialogContext, memoryResult());
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            backgroundColor: const Color(0xFFFFF8FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.88,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: submitMemory,
                          child: Text(
                            actionLabel == 'Preserve memory'
                                ? 'Preserve'
                                : 'Save',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundImage: hasPhoto
                              ? NetworkImage(_profilePhotoUrl!)
                              : null,
                          child: hasPhoto
                              ? null
                              : const Icon(Icons.person_outline),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Saving to this legacy profile',
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.58),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: promptController,
                      maxLines: 1,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.title),
                        hintText: 'Title this memory',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.62),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: bodyController,
                      minLines: 7,
                      maxLines: 12,
                      autofocus: initialBody.trim().isEmpty,
                      decoration: InputDecoration(
                        hintText:
                            'What would you like this profile to remember?',
                        filled: true,
                        fillColor: const Color(0xFFF4EEF5),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: pickPendingPhotos,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            pendingPhotos.isEmpty && existingPhotos.isEmpty
                                ? 'Add photos'
                                : 'More photos',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _recorder.isSupported
                              ? recordPendingVoice
                              : null,
                          icon: const Icon(Icons.mic_none),
                          label: Text(
                            pendingVoices.isEmpty && existingVoices.isEmpty
                                ? 'Record voice'
                                : 'Add another voice note',
                          ),
                        ),
                      ],
                    ),
                    if (existingPhotos.isNotEmpty ||
                        pendingPhotos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Photos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 116,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              existingPhotos.length + pendingPhotos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, index) {
                            if (index < existingPhotos.length) {
                              final photo = existingPhotos[index];
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _memoryPhotoImage(
                                      photo['url'] ?? '',
                                      width: 116,
                                      height: 116,
                                    ),
                                  ),
                                  Positioned(
                                    top: 5,
                                    right: 5,
                                    child: IconButton.filledTonal(
                                      tooltip: 'Remove photo',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: memoryId == null
                                          ? null
                                          : () async {
                                              await _deleteMemoryPhoto(
                                                memoryId,
                                                photo,
                                              );
                                              if (dialogContext.mounted) {
                                                setDialogState(() {});
                                              }
                                            },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ),
                                ],
                              );
                            }

                            final pendingIndex = index - existingPhotos.length;
                            final photo = pendingPhotos[pendingIndex];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    width: 116,
                                    height: 116,
                                    color: Colors.black.withValues(alpha: 0.04),
                                    child: Image.memory(
                                      photo.bytes,
                                      width: 116,
                                      height: 116,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 5,
                                  right: 5,
                                  child: IconButton.filledTonal(
                                    tooltip: 'Remove photo',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setDialogState(
                                      () =>
                                          pendingPhotos.removeAt(pendingIndex),
                                    ),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    if (existingVoices.isNotEmpty ||
                        pendingVoices.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Voice notes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...existingVoices.map(
                        (note) => Card(
                          elevation: 0,
                          color: const Color(0xFFF4EEF5),
                          child: ListTile(
                            leading: IconButton.filled(
                              tooltip: 'Play voice note',
                              onPressed: () async {
                                await _toggleVoice(note);
                                if (dialogContext.mounted) {
                                  setDialogState(() {});
                                }
                              },
                              icon: Icon(
                                _playingVoiceKey == 'legacy_voice:${note.id}'
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            title: Text(note.title),
                            subtitle: const Text('Voice note'),
                            trailing: IconButton(
                              tooltip: 'Remove voice note',
                              onPressed: memoryId == null
                                  ? null
                                  : () async {
                                      await _deleteMemoryVoice(memoryId, note);
                                      if (dialogContext.mounted) {
                                        setDialogState(() {});
                                      }
                                    },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(pendingVoices.length, (index) {
                        final voice = pendingVoices[index];
                        final key = 'pending_voice:$index';
                        return Card(
                          elevation: 0,
                          color: const Color(0xFFF4EEF5),
                          child: ListTile(
                            leading: IconButton.filled(
                              tooltip: 'Listen to take',
                              onPressed: () => _togglePendingVoice(
                                pendingVoices,
                                index,
                                () => setDialogState(() {}),
                              ),
                              icon: Icon(
                                _playingVoiceKey == key
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            title: Text('Voice note ${index + 1}'),
                            subtitle: Text(
                              '${_voiceLength(voice.seconds)} - Tap play to check this take',
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove this take',
                              onPressed: () async {
                                if (_playingVoiceKey == key) {
                                  await _voicePlayer.stop();
                                  _playingVoiceKey = null;
                                }
                                setDialogState(
                                  () => pendingVoices.removeAt(index),
                                );
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.tune),
                            title: const Text('Add details'),
                            subtitle: const Text(
                              'How it seemed, when, where, or who was there',
                            ),
                            trailing: Icon(
                              showDetails
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                            ),
                            onTap: () => setDialogState(
                              () => showDetails = !showDetails,
                            ),
                          ),
                          if (showDetails)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'How did they seem to find this experience?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
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
                                            selected: selectedMood == mood,
                                            onSelected: (selected) {
                                              setDialogState(() {
                                                selectedMood = selected
                                                    ? mood
                                                    : null;
                                              });
                                            },
                                          );
                                        }).toList(),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: whenController,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                      labelText: 'When was this?',
                                      hintText:
                                          'For example: Summer 1984 or when they were young',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: peopleController,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.people_outline),
                                      labelText: 'Who was there?',
                                      hintText: 'Names or a short description',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: locationController,
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
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: submitMemory,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(actionLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    promptController.dispose();
    bodyController.dispose();
    whenController.dispose();
    peopleController.dispose();
    locationController.dispose();
    return result;
  }

  Future<void> _deleteMemory(Map<String, dynamic> memory) async {
    final memoryId = (memory['id'] ?? '').toString();
    if (memoryId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memory?'),
        content: const Text('This will permanently delete this memory.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final photos = _memoryPhotosById[memoryId] ?? [];
      final voiceNotes = _memoryVoiceById[memoryId] ?? [];
      final photoPaths = photos
          .map((p) => (p['path'] ?? '').trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final voicePaths = voiceNotes
          .map((v) => v.path.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (photoPaths.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove(photoPaths);
      }
      if (voicePaths.isNotEmpty) {
        await _supabase.storage.from(_memoryVoiceBucket).remove(voicePaths);
      }

      await _supabase
          .from('legacy_memories')
          .delete()
          .eq('id', memoryId)
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _loadMemories();
      await _loadMemoryPhotos();
      await _loadMemoryVoice();
      _toast('Memory deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _uploadMemoryPhoto(String memoryId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No image bytes received.');

      final ext = _extFromName(file.name);
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.photo,
        bytes,
        fileName: file.name,
        contentType: _contentTypeFromExt(ext),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/memories/$memoryId/$ts.$ext';

      await _supabase.storage
          .from(_photosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _supabase.from('legacy_memory_photos').insert({
        'legacy_memory_id': memoryId,
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });

      await _loadMemoryPhotos();
      _toast('Photo added to memory.');
    } on PostgrestException catch (e) {
      _toast('Add photo failed: ${e.message}');
    } catch (e) {
      _toast('Add photo failed: $e');
    }
  }

  Future<void> _uploadPendingMemoryPhotos(
    String memoryId,
    List<_LegacyPendingPhoto> photos,
  ) async {
    if (photos.isEmpty) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.photo,
        photo.bytes,
        fileName: photo.name,
        contentType: _contentTypeFromExt(photo.extension),
      );
      final ts = DateTime.now().microsecondsSinceEpoch + index;
      final path =
          '$userId/${widget.familyId}/legacy/${widget.legacyMemberId}/memories/$memoryId/$ts.${photo.extension}';

      await _supabase.storage
          .from(_photosBucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(photo.extension),
            ),
          );

      await _supabase.from('legacy_memory_photos').insert({
        'legacy_memory_id': memoryId,
        'legacy_member_id': widget.legacyMemberId,
        'family_id': widget.familyId,
        'path': path,
      });
    }
  }

  Future<void> _uploadPendingMemoryVoice(
    String memoryId,
    List<_LegacyPendingVoice> voices,
  ) async {
    if (voices.isEmpty) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    for (var index = 0; index < voices.length; index++) {
      final audio = voices[index].audio;
      MediaUploadPolicy.validateListOrThrow(
        MediaUploadKind.voice,
        audio.bytes,
        fileName: 'voice.${audio.extension}',
        contentType: audio.mimeType,
      );
      final ts = DateTime.now().microsecondsSinceEpoch + index;
      final path =
          '${_memoryVoicePrefix(userId, memoryId)}/$ts.${audio.extension}';

      await _supabase.storage
          .from(_memoryVoiceBucket)
          .uploadBinary(
            path,
            Uint8List.fromList(audio.bytes),
            fileOptions: FileOptions(
              upsert: false,
              contentType: audio.mimeType,
            ),
          );

      final inserted = await _supabase
          .from('legacy_memory_voice_notes')
          .insert({
            'legacy_memory_id': memoryId,
            'legacy_member_id': widget.legacyMemberId,
            'family_id': widget.familyId,
            'path': path,
            'title': 'Voice note',
          })
          .select('id')
          .maybeSingle();

      final voiceId = (inserted?['id'] ?? '').toString().trim();
      if (voiceId.isNotEmpty) {
        unawaited(_indexLegacyMemoryVoice(voiceId));
      }
    }
  }

  Future<void> _indexLegacyMemoryVoice(String voiceId) async {
    final token = _supabase.auth.currentSession?.accessToken.trim();
    if (token == null || token.isEmpty) return;

    try {
      final res = await _supabase.functions.invoke(
        'index_voice_note',
        headers: {
          'Authorization': 'Bearer $token',
          'authorization': 'Bearer $token',
        },
        body: {
          'legacy_memory_voice_note_id': voiceId,
          'legacyMemberId': widget.legacyMemberId,
          'legacy_member_id': widget.legacyMemberId,
          'familyId': widget.familyId,
          'family_id': widget.familyId,
        },
      );

      if (res.status != 200) {
        throw Exception('HTTP ${res.status}: ${res.data}');
      }

      await _loadMemoryVoice();
    } catch (e) {
      _toast('Voice saved, but AI indexing failed: $e');
    }
  }

  Future<void> _deleteMemoryPhoto(
    String memoryId,
    Map<String, String> photo,
  ) async {
    try {
      final id = (photo['id'] ?? '').trim();
      final path = (photo['path'] ?? '').trim();

      if (path.isNotEmpty) {
        await _supabase.storage.from(_photosBucket).remove([path]);
      }

      if (id.isNotEmpty) {
        await _supabase
            .from('legacy_memory_photos')
            .delete()
            .eq('id', id)
            .eq('legacy_memory_id', memoryId)
            .eq('legacy_member_id', widget.legacyMemberId)
            .eq('family_id', widget.familyId);
      }

      await _loadMemoryPhotos();
      _toast('Photo deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _deleteMemoryVoice(
    String memoryId,
    _LegacyVoiceNote note,
  ) async {
    try {
      final key = 'legacy_voice:${note.id}';
      if (_playingVoiceKey == key) {
        await _voicePlayer.stop();
        if (mounted) setState(() => _playingVoiceKey = null);
      }

      if (note.path.trim().isNotEmpty) {
        await _supabase.storage.from(_memoryVoiceBucket).remove([note.path]);
      }

      await _supabase
          .from('legacy_memory_voice_notes')
          .delete()
          .eq('id', note.id)
          .eq('legacy_memory_id', memoryId)
          .eq('legacy_member_id', widget.legacyMemberId)
          .eq('family_id', widget.familyId);

      await _loadMemoryVoice();
      _toast('Voice note deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Widget _fieldCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        color: Colors.white.withValues(alpha: 0.58),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _headerCard() {
    final title = _titleFromRow(_row);
    final subtitle = _subtitleFromRow(_row);
    final slotKey = (_row?['slot_key'] ?? '').toString().trim();
    final canOpenBranch = _branchDirectionForSlot(slotKey) != null;
    final hasPhoto = (_profilePhotoUrl ?? '').trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2E5F6), Color(0xFFFFFBFF)],
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                backgroundImage: hasPhoto
                    ? NetworkImage(_profilePhotoUrl!)
                    : null,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.person_outline, size: 44),
              ),
              Positioned(
                right: -5,
                bottom: -4,
                child: Material(
                  color: const Color(0xFF76558F),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Change profile photo',
                    onPressed: _uploadingProfilePhoto
                        ? null
                        : _uploadOrReplaceProfilePhoto,
                    icon: _uploadingProfilePhoto
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.58)),
          ),
          const SizedBox(height: 4),
          Text(
            'Family profile - memories, photos and stories kept together.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.50),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openLegacyAi,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Ask their AI'),
              ),
              if (canOpenBranch)
                OutlinedButton.icon(
                  onPressed: _openBranch,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Branch'),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _selectedLegacySection = 1),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit profile'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legacyComposerCard() {
    return _fieldCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openAddMemory,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F0F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'What story should this profile remember next?',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 18),
                label: const Text('Write memory'),
                onPressed: _openAddMemory,
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Add photos'),
                onPressed: _uploadingPhoto ? null : _uploadPhoto,
              ),
              ActionChip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: const Text('About'),
                onPressed: () => setState(() => _selectedLegacySection = 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.view_stream_outlined),
            label: Text('Memories'),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.person_outline),
            label: Text('About'),
          ),
          ButtonSegment(
            value: 2,
            icon: Icon(Icons.photo_library_outlined),
            label: Text('Media'),
          ),
        ],
        selected: {_selectedLegacySection},
        onSelectionChanged: (selection) {
          setState(() => _selectedLegacySection = selection.first);
        },
      ),
    );
  }

  Widget _legacyTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    IconData? icon,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool alignLabelWithHint = false,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: maxLines == 1 ? TextInputAction.done : null,
      onEditingComplete: maxLines == 1
          ? () => FocusManager.instance.primaryFocus?.unfocus()
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        alignLabelWithHint: alignLabelWithHint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF7B5B8E), width: 1.8),
        ),
      ),
    );
  }

  Widget _savePill({bool compact = false}) {
    return OutlinedButton.icon(
      onPressed: (_savingProfile || _deletingProfile) ? null : _saveProfile,
      icon: const Icon(Icons.save_outlined, size: 18),
      label: Text(_savingProfile ? 'Saving...' : 'Save'),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 24,
          vertical: compact ? 12 : 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _profileActions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: (_savingProfile || _deletingProfile)
                  ? null
                  : _deleteProfile,
              icon: const Icon(Icons.delete_outline),
              label: Text(_deletingProfile ? 'Deleting...' : 'Delete'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _savePill()),
        ],
      ),
    );
  }

  Widget _activeSection() {
    switch (_selectedLegacySection) {
      case 1:
        return Column(
          children: [
            _aboutCard(),
            const SizedBox(height: 12),
            _identityCard(),
            const SizedBox(height: 12),
            _extraDetailsCard(),
            const SizedBox(height: 12),
            _profileActions(),
          ],
        );
      case 2:
        return _mediaCard();
      default:
        return _memoriesCard();
    }
  }

  Widget _emptyPhotoTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _uploadingPhoto ? null : _uploadPhoto,
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: const Color(0xFFF2E7F5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF76558F).withValues(alpha: 0.18),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 30),
            SizedBox(height: 8),
            Text('New photo'),
          ],
        ),
      ),
    );
  }

  Widget _mediaCard() {
    return _fieldCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Their media',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _uploadingPhoto ? null : _uploadPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_uploadingPhoto ? 'Adding...' : 'Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingPhotos)
            const Center(child: CircularProgressIndicator())
          else if (_photoError != null)
            Text(
              'Photo load issue: $_photoError',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.60)),
            )
          else if (_photos.isEmpty)
            const Text('Photos added to this profile will appear here.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _photos.length,
              itemBuilder: (_, index) {
                final photo = _photos[index];
                final url = (photo['url'] ?? '').trim();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      url.isEmpty
                          ? Container(
                              color: Colors.black.withValues(alpha: 0.05),
                            )
                          : Image.network(url, fit: BoxFit.cover),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          onTap: () => _deletePhoto(photo),
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.58,
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'About them',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              _savePill(compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Add the details family should remember: personality, values, places, stories.',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.58)),
          ),
          const SizedBox(height: 12),
          _legacyTextField(
            controller: _aboutController,
            minLines: 6,
            maxLines: 12,
            label: 'About them',
            hintText: 'Family notes, memories, personality, stories',
            icon: Icons.auto_stories_outlined,
            alignLabelWithHint: true,
          ),
        ],
      ),
    );
  }

  Widget _photosCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Highlights',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _uploadingPhoto ? null : _uploadPhoto,
                icon: const Icon(Icons.add, size: 18),
                label: Text(_uploadingPhoto ? 'Adding...' : 'Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingPhotos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_photoError != null)
            Text(
              'Photo load issue: $_photoError',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.60)),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == _photos.length) return _emptyPhotoTile();
                  final photo = _photos[index];
                  final url = (photo['url'] ?? '').trim();
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onLongPress: () => _deletePhoto(photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: url.isEmpty
                          ? Container(
                              width: 104,
                              height: 132,
                              color: Colors.black.withValues(alpha: 0.05),
                            )
                          : Image.network(
                              url,
                              width: 104,
                              height: 132,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _identityCard() {
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _legacyTextField(
            controller: _nameController,
            label: 'Name *',
            icon: Icons.person_outline,
          ),
        ],
      ),
    );
  }

  Widget _extraDetailsCard() {
    return _fieldCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _showExtraDetails,
          onExpansionChanged: (v) => setState(() => _showExtraDetails = v),
          title: const Text(
            'Extra details',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _detailsLabel(_row),
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            Row(
              children: [
                Expanded(
                  child: _legacyTextField(
                    controller: _birthYearController,
                    keyboardType: TextInputType.number,
                    label: 'Birth year',
                    icon: Icons.cake_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _legacyTextField(
                    controller: _deathYearController,
                    keyboardType: TextInputType.number,
                    label: 'Death year',
                    icon: Icons.favorite_border,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _memoryPhotoStrip(String memoryId) {
    final photos = _memoryPhotosById[memoryId] ?? [];
    final preview = photos.take(4).toList();

    if (_loadingMemoryPhotos) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Loading photos…',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    if (_memoryPhotoError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Photo load issue: $_memoryPhotoError',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _uploadMemoryPhoto(memoryId),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add photo'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: preview.length + 1,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _uploadMemoryPhoto(memoryId),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  child: Icon(
                    Icons.add,
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                ),
              );
            }

            final p = preview[i - 1];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _deleteMemoryPhoto(memoryId, p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    _memoryPhotoImage(
                      p['url'] ?? '',
                      width: 92,
                      height: 66,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _memoryPhotoImage(
    String url, {
    required double width,
    required double height,
    bool gaplessPlayback = false,
  }) {
    return Container(
      width: width,
      height: height,
      color: Colors.black.withValues(alpha: 0.04),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: gaplessPlayback,
      ),
    );
  }

  Widget _memoryVoiceStrip(String memoryId) {
    final notes = _memoryVoiceById[memoryId] ?? [];

    if (_loadingMemoryVoice) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Loading voice…',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    if (_memoryVoiceError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Voice load issue: $_memoryVoiceError',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    if (notes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: notes.take(2).map((note) {
          return Card(
            elevation: 0,
            color: const Color(0xFFF4EEF5),
            child: ListTile(
              dense: true,
              leading: IconButton(
                tooltip: 'Play voice note',
                onPressed: () => _toggleVoice(note),
                icon: Icon(
                  _playingVoiceKey == 'legacy_voice:${note.id}'
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                ),
              ),
              title: Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Voice memory'),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _memoryCard(Map<String, dynamic> m) {
    final memoryId = (m['id'] ?? '').toString();
    final stage = (m['life_stage'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    final mood = (m['mood'] ?? '').toString().trim();
    final when = (m['memory_date_label'] ?? '').toString().trim();
    final people = (m['people'] ?? '').toString().trim();
    final location = (m['location'] ?? '').toString().trim();
    final title = _titleFromRow(_row);
    final hasPhoto = (_profilePhotoUrl ?? '').trim().isNotEmpty;
    final details = <Widget>[
      if (mood.isNotEmpty) _legacyDetailChip(Icons.favorite_border, mood),
      if (when.isNotEmpty) _legacyDetailChip(Icons.event_outlined, when),
      if (people.isNotEmpty) _legacyDetailChip(Icons.people_outline, people),
      if (location.isNotEmpty)
        _legacyDetailChip(Icons.location_on_outlined, location),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: hasPhoto
                      ? NetworkImage(_profilePhotoUrl!)
                      : null,
                  child: hasPhoto ? null : const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_prettyStage(stage)} - Legacy memory',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Memory options',
                  onSelected: (value) {
                    if (value == 'edit') _editMemory(m);
                    if (value == 'delete') _deleteMemory(m);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit memory')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete memory'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (prompt.isNotEmpty)
              Text(
                prompt,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (prompt.isNotEmpty && body.isNotEmpty) const SizedBox(height: 7),
            if (body.isNotEmpty)
              Text(body, style: const TextStyle(fontSize: 15, height: 1.42)),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: details),
            ],
            _memoryPhotoStrip(memoryId),
            _memoryVoiceStrip(memoryId),
            const Divider(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _uploadMemoryPhoto(memoryId),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Photo'),
                ),
                const Spacer(),
                Icon(
                  Icons.family_restroom,
                  size: 18,
                  color: Colors.black.withValues(alpha: 0.46),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legacyDetailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F0F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF76558F)),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }

  Widget _memoriesCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Memories',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _openAddMemory,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingMemories)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_memoryError != null)
          _fieldCard(
            child: Text(
              'Memory load issue: $_memoryError',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.60)),
            ),
          )
        else if (_memories.isEmpty)
          _fieldCard(
            child: Text(
              'No memories yet. Add a story, family memory, or important moment.',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.60)),
            ),
          )
        else
          Column(children: _memories.map(_memoryCard).toList()),
      ],
    );
  }

  Widget _legacyPageContent() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _headerCard(),
            _legacyComposerCard(),
            const SizedBox(height: 14),
            _photosCard(),
            const SizedBox(height: 14),
            _sectionPicker(),
            _activeSection(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleFromRow(_row);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: (_loading || _deletingProfile) ? null : _deleteProfile,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.05,
                  child: Image.asset(
                    'assets/images/immortalink_logo.png',
                    width: 520,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _legacyPageContent(),
        ],
      ),
    );
  }
}

class _LegacyMemoryEditResult {
  final String lifeStage;
  final String promptText;
  final String body;
  final String mood;
  final String memoryDateLabel;
  final String people;
  final String location;
  final List<_LegacyPendingPhoto> photos;
  final List<_LegacyPendingVoice> voices;

  const _LegacyMemoryEditResult({
    required this.lifeStage,
    required this.promptText,
    required this.body,
    required this.mood,
    required this.memoryDateLabel,
    required this.people,
    required this.location,
    required this.photos,
    required this.voices,
  });
}

class _LegacyPendingPhoto {
  final String name;
  final Uint8List bytes;
  final String extension;

  const _LegacyPendingPhoto({
    required this.name,
    required this.bytes,
    required this.extension,
  });
}

class _LegacyPendingVoice {
  final RecordedAudio audio;
  final int seconds;

  const _LegacyPendingVoice({required this.audio, required this.seconds});
}

class _LegacyVoiceNote {
  final String id;
  final String path;
  final String title;
  final String url;
  final String createdAt;

  const _LegacyVoiceNote({
    required this.id,
    required this.path,
    required this.title,
    required this.url,
    required this.createdAt,
  });
}
