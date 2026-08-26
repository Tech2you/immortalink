// lib/screens/vault_home_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/indexing_service.dart';
import '../utils/everroot_upgrade_prompt.dart';
import '../utils/image_upload_optimizer.dart';
import '../utils/media_upload_policy.dart';
import '../utils/web_audio_recorder.dart';
import '../widgets/logo_watermark.dart';
import 'create_memory_screen.dart';
import 'family_branch_screen.dart';
import 'relationship_tree_screen.dart';
import 'vault_companion_screen.dart';

class VaultHomeScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;
  final String? familyId;

  const VaultHomeScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
    this.familyId,
  });

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _memories = [];
  String _vaultName = '';

  // --- Avatar / display meta ---
  String? _avatarUrl; // signed URL for display
  String? _avatarPath; // stored in DB (vaults.avatar_path)
  String? _displayName;
  bool _savingAvatar = false;

  String? _familyId;
  String? _slotKey;
  int _selectedVaultSection = 0;

  // --- Featured photos (highlights) ---
  bool _loadingPhotos = true;
  bool _uploadingPhoto = false;
  List<Map<String, String>> _featuredPhotos = []; // {path,url}

  // Netflix-style carousel state
  final PageController _highlightController = PageController();
  Timer? _autoSlideTimer;
  int _highlightIndex = 0;

  // --- ABOUT ME (Text + Photos) ---
  final TextEditingController _aboutMeController = TextEditingController();
  bool _loadingAboutMe = true;
  bool _savingAboutMe = false;
  String? _aboutMeError;
  String? _aboutMeMemoryId; // created by index_memory (prompt_key=about_me)

  bool _loadingAboutPhotos = true;
  bool _uploadingAboutPhoto = false;
  String? _aboutPhotoError;
  List<Map<String, String>> _aboutPhotos = []; // {path,url}
  final PageController _aboutController = PageController();
  int _aboutIndex = 0;

  // --- Memory photos ---
  bool _loadingMemoryPhotos = true;
  String? _memoryPhotoError;
  final Map<String, List<_MemPhoto>> _memoryPhotosById = {};

  // --- Core voice note (one per vault) ---
  bool _loadingCoreVoice = true;
  String? _coreVoiceError;
  bool _savingCoreVoice = false;
  _VoiceNote? _coreVoice;

  // --- Memory voice notes ---
  bool _loadingMemoryVoice = true;
  String? _memoryVoiceError;
  final Map<String, List<_VoiceNote>> _memoryVoiceById = {};

  // Playback
  final AudioPlayer _player = AudioPlayer();
  String? _playingKey; // e.g. "core:vaultId" OR "mem:<id>"
  bool _isPlaying = false;

  // Web recorder (safe on non-web)
  final WebAudioRecorder _recorder = createWebAudioRecorder();

  // Buckets
  static const String _avatarBucket = 'avatars';
  static const String _featuredPhotosBucket = 'vault_photos';
  static const String _memoryPhotosBucket = 'memory_photos';
  static const String _voiceBucket = 'vault_voice';
  static const String _memoryVoiceBucket = 'memory_voice';

  // About photos: use SAME bucket as highlights for MVP (keeps infra simple)
  static const String _aboutPhotosBucket = 'vault_photos';

  bool _reindexing = false;

  @override
  void initState() {
    super.initState();
    _vaultName = widget.vaultName;

    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = (s == PlayerState.playing));
    });

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playingKey = null;
      });
    });

    _loadVaultMeta();
    _loadMemories();
    _loadFeaturedPhotos();
    _loadCoreVoice();
    _loadAboutMe();
    _loadAboutPhotos();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _highlightController.dispose();
    _aboutController.dispose();
    _aboutMeController.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleUploadError(Object error, String fallback) async {
    if (!mounted) return;
    if (isEverRootFamilyUpgradeError(error)) {
      await showEverRootFamilyUpgradePrompt(
        context,
        message: everRootUploadErrorMessage(error, fallback: fallback),
      );
      return;
    }
    _toast('$fallback: $error');
  }

  Future<String?> _promptRename({
    required String title,
    required String initial,
    String hint = 'Voice note name',
  }) async {
    final c = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _extFromName(String name) {
    return MediaUploadPolicy.extensionForName(name);
  }

  String _contentTypeFromExt(String ext) {
    return MediaUploadPolicy.contentTypeForExtension(ext);
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    try {
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
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
    final familyId = (_familyId ?? '').trim();
    final slotKey = (_slotKey ?? '').trim();
    final direction = _branchDirectionForSlot(slotKey);

    if (familyId.isEmpty || slotKey.isEmpty || direction == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyBranchScreen(
          familyId: familyId,
          rootLabel: _branchLabelForSlot(slotKey),
          rootSlotKey: slotKey,
          direction: direction,
        ),
      ),
    );

    await _loadVaultMeta();
  }

  Future<void> _indexCoreVoiceNote() async {
    final token = _client.auth.currentSession?.accessToken.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Missing session token. Please sign in again.');
    }

    final res = await _client.functions.invoke(
      'index_voice_note',
      headers: {
        'Authorization': 'Bearer $token',
        'authorization': 'Bearer $token',
      },
      body: {'vault_id': widget.vaultId, 'core_voice': true},
    );

    if (res.status != 200) {
      throw Exception(
        'index_voice_note (core_voice) failed: HTTP ${res.status}: ${res.data}',
      );
    }
  }

  Future<void> _openRecordDialog({
    required String title,
    required String subtitle,
    required Future<void> Function(RecordedAudio rec, int seconds) onSave,
  }) async {
    if (!_recorder.isSupported) {
      _toast('Recording not supported in this browser (use Upload for now).');
      return;
    }

    bool saving = false;
    String? err;
    int seconds = 0;
    bool startScheduled = false;
    DateTime? startedAt;
    Timer? t;

    void updateElapsed() {
      final started = startedAt;
      if (started == null) return;
      seconds = DateTime.now().difference(started).inSeconds;
    }

    Future<void> stopAndSave(StateSetter setInner) async {
      if (saving) return;
      setInner(() {
        saving = true;
        err = null;
      });

      try {
        final rec = await _recorder.stop();
        updateElapsed();
        await onSave(rec, seconds <= 0 ? 1 : seconds);
        if (!mounted) return;
        Navigator.pop(context);
      } catch (e) {
        setInner(() {
          err = e.toString();
          saving = false;
        });
      } finally {
        t?.cancel();
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) {
            Future<void> startIfNeeded() async {
              if (_recorder.isRecording) return;
              try {
                await _recorder.start();
                startedAt = DateTime.now();
                seconds = 0;
                if (ctx.mounted) setInner(() {});
                t?.cancel();
                t = Timer.periodic(const Duration(seconds: 1), (_) {
                  updateElapsed();
                  if (ctx.mounted) setInner(() {});
                });
              } catch (e) {
                setInner(() => err = e.toString());
              }
            }

            if (!startScheduled) {
              startScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => startIfNeeded(),
              );
            }

            String mmss(int s) {
              final m = (s ~/ 60).toString().padLeft(2, '0');
              final ss = (s % 60).toString().padLeft(2, '0');
              return '$m:$ss';
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  try {
                                    await _recorder.cancel();
                                  } catch (_) {}
                                  t?.cancel();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: TextStyle(color: Colors.black.withOpacity(0.65)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                        color: Colors.white.withOpacity(0.45),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.mic,
                            color: Colors.black.withOpacity(0.65),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            saving
                                ? 'Saving…'
                                : (_recorder.isRecording
                                      ? 'Recording…'
                                      : 'Starting…'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            mmss(seconds),
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 10),
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saving ? null : () => stopAndSave(setInner),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop & save'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: speak naturally.',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    t?.cancel();
  }

  Future<void> _loadVaultMeta() async {
    try {
      final res = await _client
          .from('vaults')
          .select('avatar_path, display_name, name, family_id')
          .eq('id', widget.vaultId)
          .maybeSingle();

      if (!mounted) return;

      final path = (res?['avatar_path'] as String?)?.trim();
      final dn =
          (res?['display_name'] as String?) ??
          (res?['name'] as String?) ??
          _vaultName;
      // vaults.family_id is the account owner's selected home family.
      // Prefer it over the family the vault happened to be opened from.
      final homeFamilyId = (res?['family_id'] as String?)?.trim();
      final openedFromFamilyId = widget.familyId?.trim();
      final familyId = homeFamilyId != null && homeFamilyId.isNotEmpty
          ? homeFamilyId
          : openedFromFamilyId;

      String? slotKey;
      if (familyId != null && familyId.isNotEmpty) {
        try {
          final uid = _client.auth.currentUser?.id;
          if (uid != null && uid.isNotEmpty) {
            final member = await _client
                .from('family_members')
                .select('slot_key')
                .eq('family_id', familyId)
                .eq('user_id', uid)
                .maybeSingle();

            slotKey = (member?['slot_key'] as String?)?.trim();
          }
        } catch (_) {}
      }

      String? signedUrl;
      if (path != null && path.isNotEmpty) {
        signedUrl = await _signedUrl(_avatarBucket, path);
      }

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
        _familyId = familyId;
        _slotKey = slotKey;
        _displayName = dn.trim().isEmpty ? _vaultName : dn.trim();
      });
    } catch (_) {}
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      setState(() => _savingAvatar = true);

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final image = await ImageUploadOptimizer.optimize(
        bytes,
        kind: MediaUploadKind.avatarPhoto,
        fileName: file.name,
        contentType: _contentTypeFromExt(_extFromName(file.name)),
      );
      final path = '$userId/${widget.vaultId}/avatar.${image.extension}';

      await _client.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: image.contentType,
            ),
          );

      await _client
          .from('vaults')
          .update({'avatar_path': path})
          .eq('id', widget.vaultId);

      final signedUrl = await _signedUrl(_avatarBucket, path);

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
      });

      _toast('Vault photo updated.');
    } catch (e) {
      await _handleUploadError(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  void _openAskAI() {
    final name = (_displayName ?? _vaultName).trim().isNotEmpty
        ? (_displayName ?? _vaultName).trim()
        : 'Vault';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultCompanionScreen(
          vaultId: widget.vaultId,
          displayName: name,
          avatarUrl: _avatarUrl,
          familyId: _familyId,
        ),
      ),
    );
  }

  void _openHomeFamilyTree() {
    final familyId = (_familyId ?? widget.familyId ?? '').trim();
    if (familyId.isEmpty) {
      _toast('Join or create a family tree first.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelationshipTreeScreen(familyId: familyId),
      ),
    );
  }

  Widget _vaultAvatarHeader() {
    final name = (_displayName ?? _vaultName).trim().isNotEmpty
        ? (_displayName ?? _vaultName).trim()
        : 'Your vault';
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;
    final canOpenFamilyTree = (_familyId ?? widget.familyId ?? '')
        .trim()
        .isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
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
                backgroundImage: hasAvatar ? NetworkImage(_avatarUrl!) : null,
                child: !hasAvatar
                    ? const Icon(Icons.person_outline, size: 44)
                    : null,
              ),
              Positioned(
                right: -5,
                bottom: -4,
                child: Material(
                  color: const Color(0xFF76558F),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Change profile photo',
                    onPressed: _savingAvatar ? null : _pickAndUploadAvatar,
                    icon: _savingAvatar
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
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Your stories, voice and moments — kept together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black.withOpacity(0.58)),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openAskAI,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Ask my AI'),
              ),
              if (canOpenFamilyTree)
                OutlinedButton.icon(
                  onPressed: _openHomeFamilyTree,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Family tree'),
                ),
              OutlinedButton.icon(
                onPressed: _renameVault,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit profile'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _featuredPrefix(String userId) => '$userId/${widget.vaultId}/featured';

  int get _highlightsCount =>
      _featuredPhotos.length >= 3 ? 3 : _featuredPhotos.length;

  void _setupAutoSlide() {
    _autoSlideTimer?.cancel();
    final n = _highlightsCount;
    if (n <= 1) return;

    _highlightIndex = 0;

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (!_highlightController.hasClients) return;

      final nn = _highlightsCount;
      if (nn <= 1) return;

      _highlightIndex = (_highlightIndex + 1) % nn;
      _highlightController.animateToPage(
        _highlightIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _loadFeaturedPhotos() async {
    setState(() => _loadingPhotos = true);

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _featuredPhotos = [];
          _loadingPhotos = false;
        });
        return;
      }

      final rows = await _client
          .from('vault_highlight_photos')
          .select('path')
          .eq('vault_id', widget.vaultId)
          .order('created_at');

      final items = <Map<String, String>>[];
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final fullPath = (row['path'] ?? '').toString().trim();
        if (fullPath.isEmpty) continue;
        final url = await _signedUrl(_featuredPhotosBucket, fullPath);
        if (url == null || url.trim().isEmpty) continue;

        items.add({'path': fullPath, 'url': url});
      }

      if (!mounted) return;

      setState(() {
        _featuredPhotos = items;
        _loadingPhotos = false;
        _highlightIndex = 0;
      });

      if (_highlightController.hasClients) {
        _highlightController.jumpToPage(0);
      }

      _setupAutoSlide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _featuredPhotos = [];
        _loadingPhotos = false;
      });
      _toast('Photo load failed: $e');
    }
  }

  Future<void> _uploadFeaturedPhoto() async {
    try {
      setState(() => _uploadingPhoto = true);

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final image = await ImageUploadOptimizer.optimize(
        bytes,
        kind: MediaUploadKind.photo,
        fileName: file.name,
        contentType: _contentTypeFromExt(_extFromName(file.name)),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_featuredPrefix(userId)}/$ts.${image.extension}';

      await _client.storage
          .from(_featuredPhotosBucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: image.contentType,
            ),
          );

      await _client.from('vault_highlight_photos').insert({
        'vault_id': widget.vaultId,
        'path': path,
      });

      await _loadFeaturedPhotos();
      _toast('Added to highlights.');
    } catch (e) {
      await _handleUploadError(e, 'Photo upload failed');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _deleteFeaturedPhoto(String fullPath) async {
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
      await _client.storage.from(_featuredPhotosBucket).remove([fullPath]);
      await _client
          .from('vault_highlight_photos')
          .delete()
          .eq('vault_id', widget.vaultId)
          .eq('path', fullPath);
      await _loadFeaturedPhotos();
      _toast('Photo deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  void _openHighlightsGallery() {
    if (_featuredPhotos.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final pc = PageController();
        int idx = 0;

        final maxH = MediaQuery.of(ctx).size.height * 0.85;
        final maxW = MediaQuery.of(ctx).size.width * 0.95;

        return StatefulBuilder(
          builder: (ctx, setInner) {
            final total = _featuredPhotos.length;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text(
                            'All photos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.black,
                            child: PageView.builder(
                              controller: pc,
                              itemCount: total,
                              onPageChanged: (v) => setInner(() => idx = v),
                              itemBuilder: (_, i) {
                                final url = _featuredPhotos[i]['url'] ?? '';
                                final path = _featuredPhotos[i]['path'] ?? '';
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: InteractiveViewer(
                                        minScale: 1,
                                        maxScale: 4,
                                        child: Image.network(
                                          url,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.center,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: InkWell(
                                        onTap: () async {
                                          if (path.trim().isEmpty) return;
                                          await _deleteFeaturedPhoto(path);
                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx);
                                        },
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.black
                                              .withOpacity(0.55),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${idx + 1} / $total',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.65),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: _uploadingPhoto
                                  ? null
                                  : _uploadFeaturedPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text(
                                _uploadingPhoto ? 'Uploading…' : 'Add',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dots(int count, int active) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: on ? 16 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.black.withOpacity(on ? 0.50 : 0.18),
          ),
        );
      }),
    );
  }

  Widget _featuredPhotosSection() {
    const double previewHeight = 264;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Your highlights',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                'Favourite photos / memories',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploadingPhoto ? null : _uploadFeaturedPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_uploadingPhoto ? 'Uploading…' : 'Add photo'),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingPhotos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_featuredPhotos.isEmpty)
            Row(
              children: [
                Icon(Icons.photo, color: Colors.black.withOpacity(0.45)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No highlights yet. Add a few moments that represent you.',
                    style: TextStyle(color: Colors.black.withOpacity(0.60)),
                  ),
                ),
              ],
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openHighlightsGallery,
              child: Column(
                children: [
                  SizedBox(
                    height: previewHeight,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black,
                        child: PageView.builder(
                          controller: _highlightController,
                          itemCount: _highlightsCount,
                          onPageChanged: (i) =>
                              setState(() => _highlightIndex = i),
                          itemBuilder: (_, i) {
                            final url = _featuredPhotos[i]['url'] ?? '';
                            final path = _featuredPhotos[i]['path'] ?? '';
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: InkWell(
                                    onTap: () => _deleteFeaturedPhoto(path),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.black.withOpacity(
                                        0.55,
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Text(
                                    'Tap to view all',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dots(
                    _highlightsCount,
                    _highlightIndex.clamp(
                      0,
                      (_highlightsCount - 1).clamp(0, 99),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _aboutPrefix(String userId) => '$userId/${widget.vaultId}/about_me';

  int get _aboutCount => _aboutPhotos.length >= 3 ? 3 : _aboutPhotos.length;

  Future<void> _loadAboutMe() async {
    if (!mounted) return;
    setState(() {
      _loadingAboutMe = true;
      _aboutMeError = null;
      _aboutMeMemoryId = null;
    });

    try {
      final row = await _client
          .from('memories')
          .select('id, body')
          .eq('vault_id', widget.vaultId)
          .eq('prompt_key', 'about_me')
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      final id = (row?['id'] ?? '').toString().trim();
      final body = (row?['body'] ?? '').toString();

      _aboutMeMemoryId = id.isEmpty ? null : id;

      if (!_savingAboutMe) {
        _aboutMeController.text = body;
      }

      setState(() => _loadingAboutMe = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAboutMe = false;
        _aboutMeError = e.toString();
      });
    }
  }

  Future<void> _saveAboutMeText() async {
    final text = _aboutMeController.text.trim();
    if (text.isEmpty) {
      _toast('About me text can’t be empty.');
      return;
    }

    setState(() {
      _savingAboutMe = true;
      _aboutMeError = null;
    });

    try {
      final token = _client.auth.currentSession?.accessToken.trim();
      if (token == null || token.isEmpty) {
        throw Exception('Missing session token. Please sign in again.');
      }

      final res = await _client.functions.invoke(
        'index_memory',
        headers: {
          'Authorization': 'Bearer $token',
          'authorization': 'Bearer $token',
        },
        body: {
          'vault_id': widget.vaultId,
          'source': 'about_me',
          'about_me_text': text,
        },
      );

      if (res.status != 200) {
        throw Exception(
          'index_memory (about_me) failed: HTTP ${res.status}: ${res.data}',
        );
      }

      await _loadAboutMe();
      _toast('About me saved.');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() => _savingAboutMe = false);
      }
    }
  }

  Future<void> _loadAboutPhotos() async {
    if (!mounted) return;

    setState(() {
      _loadingAboutPhotos = true;
      _aboutPhotoError = null;
      _aboutPhotos = [];
      _aboutIndex = 0;
    });

    try {
      final rows = await _client
          .from('vault_about_photos')
          .select('id, path, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final items = <Map<String, String>>[];
      for (final r in list) {
        final path = (r['path'] ?? '').toString().trim();
        if (path.isEmpty) continue;
        final url = await _signedUrl(_aboutPhotosBucket, path);
        if (url == null || url.trim().isEmpty) continue;
        items.add({'path': path, 'url': url});
      }

      if (!mounted) return;
      setState(() {
        _aboutPhotos = items;
        _loadingAboutPhotos = false;
      });

      if (_aboutController.hasClients) {
        _aboutController.jumpToPage(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAboutPhotos = false;
        _aboutPhotoError = e.toString();
      });
    }
  }

  Future<void> _uploadAboutPhoto() async {
    try {
      setState(() => _uploadingAboutPhoto = true);

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final image = await ImageUploadOptimizer.optimize(
        bytes,
        kind: MediaUploadKind.photo,
        fileName: file.name,
        contentType: _contentTypeFromExt(_extFromName(file.name)),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_aboutPrefix(userId)}/$ts.${image.extension}';

      await _client.storage
          .from(_aboutPhotosBucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: image.contentType,
            ),
          );

      await _client.from('vault_about_photos').insert({
        'vault_id': widget.vaultId,
        'path': path,
      });

      await _loadAboutPhotos();
      _toast('Added to About me.');
    } catch (e) {
      await _handleUploadError(e, 'Upload failed');
    } finally {
      if (mounted) setState(() => _uploadingAboutPhoto = false);
    }
  }

  Future<void> _deleteAboutPhoto(String path) async {
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
      await _client.storage.from(_aboutPhotosBucket).remove([path]);
      await _client
          .from('vault_about_photos')
          .delete()
          .eq('vault_id', widget.vaultId)
          .eq('path', path);
      await _loadAboutPhotos();
      _toast('Photo deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  void _openAboutGallery() {
    if (_aboutPhotos.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final pc = PageController();
        int idx = 0;

        final maxH = MediaQuery.of(ctx).size.height * 0.85;
        final maxW = MediaQuery.of(ctx).size.width * 0.95;

        return StatefulBuilder(
          builder: (ctx, setInner) {
            final total = _aboutPhotos.length;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text(
                            'About me photos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.black,
                            child: PageView.builder(
                              controller: pc,
                              itemCount: total,
                              onPageChanged: (v) => setInner(() => idx = v),
                              itemBuilder: (_, i) {
                                final url = _aboutPhotos[i]['url'] ?? '';
                                final path = _aboutPhotos[i]['path'] ?? '';
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: InteractiveViewer(
                                        minScale: 1,
                                        maxScale: 4,
                                        child: Image.network(
                                          url,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.center,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: InkWell(
                                        onTap: () async {
                                          if (path.trim().isEmpty) return;
                                          await _deleteAboutPhoto(path);
                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx);
                                        },
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.black
                                              .withOpacity(0.55),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${idx + 1} / $total',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.65),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: _uploadingAboutPhoto
                                  ? null
                                  : _uploadAboutPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text(
                                _uploadingAboutPhoto ? 'Uploading…' : 'Add',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _aboutMeSection() {
    const double previewHeight = 220;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'About me (Text)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _savingAboutMe ? null : _saveAboutMeText,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_savingAboutMe ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Write details the AI should always know (birthdate, personality, values, fun facts, background).',
            style: TextStyle(color: Colors.black.withOpacity(0.65)),
          ),
          const SizedBox(height: 10),
          if (_loadingAboutMe)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_aboutMeError != null)
            Text(
              'About me load issue (MVP): $_aboutMeError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else
            TextField(
              controller: _aboutMeController,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                hintText:
                    'Example: I was born in… I value… People describe me as…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.35),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'About me photos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _uploadingAboutPhoto ? null : _uploadAboutPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _uploadingAboutPhoto ? 'Uploading…' : 'Add photo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingAboutPhotos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_aboutPhotoError != null)
            Text(
              'Photo load issue (MVP): $_aboutPhotoError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else if (_aboutPhotos.isEmpty)
            Row(
              children: [
                Icon(Icons.photo, color: Colors.black.withOpacity(0.45)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No About me photos yet. Add 1–3 that represent you (portrait, favourite place, milestone).',
                    style: TextStyle(color: Colors.black.withOpacity(0.60)),
                  ),
                ),
              ],
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openAboutGallery,
              child: Column(
                children: [
                  SizedBox(
                    height: previewHeight,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black,
                        child: PageView.builder(
                          controller: _aboutController,
                          itemCount: _aboutCount,
                          onPageChanged: (i) => setState(() => _aboutIndex = i),
                          itemBuilder: (_, i) {
                            final url = _aboutPhotos[i]['url'] ?? '';
                            final path = _aboutPhotos[i]['path'] ?? '';
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: InkWell(
                                    onTap: () => _deleteAboutPhoto(path),
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.black.withOpacity(
                                        0.55,
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Text(
                                    'Tap to view all',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dots(
                    _aboutCount,
                    _aboutIndex.clamp(0, (_aboutCount - 1).clamp(0, 99)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _voicePrefix(String userId) => '$userId/${widget.vaultId}/voice';

  Future<void> _loadCoreVoice() async {
    setState(() {
      _loadingCoreVoice = true;
      _coreVoiceError = null;
      _coreVoice = null;
    });

    try {
      final row = await _client
          .from('vault_core_voice_note')
          .select('id, path, title, created_at')
          .eq('vault_id', widget.vaultId)
          .maybeSingle();

      if (row == null) {
        if (!mounted) return;
        setState(() => _loadingCoreVoice = false);
        return;
      }

      final id = (row['id'] ?? '').toString();
      final path = (row['path'] ?? '').toString().trim();
      final title = (row['title'] ?? '').toString().trim();
      final createdAt = (row['created_at'] ?? '').toString();

      if (id.isEmpty || path.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingCoreVoice = false);
        return;
      }

      final url = await _signedUrl(_voiceBucket, path);
      if (url == null || url.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _loadingCoreVoice = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _coreVoice = _VoiceNote(
          id: id,
          path: path,
          title: title.isEmpty ? 'About me voice note' : title,
          url: url,
          createdAt: createdAt,
        );
        _loadingCoreVoice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCoreVoice = false;
        _coreVoiceError = e.toString();
      });
    }
  }

  Future<void> _uploadCoreVoiceFile() async {
    try {
      setState(() => _savingCoreVoice = true);

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'webm'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received');

      final ext = _extFromName(file.name);
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.voice,
        bytes,
        fileName: file.name,
        contentType: _contentTypeFromExt(ext),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_voicePrefix(userId)}/core_$ts.$ext';

      await _client.storage
          .from(_voiceBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _client.from('vault_core_voice_note').upsert({
        'vault_id': widget.vaultId,
        'path': path,
        'title': 'About me voice note',
      }, onConflict: 'vault_id');

      await _indexCoreVoiceNote();

      await _loadCoreVoice();
      _toast('Saved.');
    } catch (e) {
      await _handleUploadError(e, 'Save failed');
    } finally {
      if (mounted) setState(() => _savingCoreVoice = false);
    }
  }

  Future<void> _recordCoreVoice() async {
    await _openRecordDialog(
      title: 'Record “About me” voice',
      subtitle:
          'Optional: share a quick intro, fun fact, moral code, or biggest achievement.',
      onSave: (rec, _) async {
        setState(() => _savingCoreVoice = true);

        final userId = _client.auth.currentUser?.id;
        if (userId == null) throw Exception('Not signed in');

        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '${_voicePrefix(userId)}/core_$ts.${rec.extension}';
        MediaUploadPolicy.validateListOrThrow(
          MediaUploadKind.voice,
          rec.bytes,
          fileName: 'voice.${rec.extension}',
          contentType: rec.mimeType,
        );

        await _client.storage
            .from(_voiceBucket)
            .uploadBinary(
              path,
              Uint8List.fromList(rec.bytes),
              fileOptions: FileOptions(
                upsert: false,
                contentType: rec.mimeType,
              ),
            );

        await _client.from('vault_core_voice_note').upsert({
          'vault_id': widget.vaultId,
          'path': path,
          'title': 'About me voice note',
        }, onConflict: 'vault_id');

        await _indexCoreVoiceNote();

        await _loadCoreVoice();
        if (mounted) setState(() => _savingCoreVoice = false);
        _toast('Saved.');
      },
    );
  }

  Future<void> _deleteCoreVoice() async {
    final v = _coreVoice;
    if (v == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voice note?'),
        content: const Text('This will permanently delete this voice note.'),
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
      if (_playingKey == 'core:${widget.vaultId}') {
        await _player.stop();
        if (mounted) setState(() => _playingKey = null);
      }

      await _client.storage.from(_voiceBucket).remove([v.path]);
      await _client
          .from('vault_core_voice_note')
          .delete()
          .eq('vault_id', widget.vaultId);
      await _loadCoreVoice();
      _toast('Deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _renameCoreVoice() async {
    final v = _coreVoice;
    if (v == null) return;

    final newTitle = await _promptRename(
      title: 'Rename voice note',
      initial: v.title,
      hint: 'Voice note title',
    );
    if (newTitle == null || newTitle.isEmpty) return;

    try {
      await _client
          .from('vault_core_voice_note')
          .update({'title': newTitle})
          .eq('vault_id', widget.vaultId);
      await _loadCoreVoice();
      _toast('Renamed.');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _togglePlay(_VoiceNote v, {required String playKey}) async {
    try {
      if (_playingKey == playKey) {
        if (_isPlaying) {
          await _player.pause();
        } else {
          await _player.resume();
        }
        return;
      }

      await _player.stop();
      setState(() {
        _playingKey = playKey;
        _isPlaying = false;
      });

      await _player.play(UrlSource(v.url));
    } catch (e) {
      _toast('Playback failed: $e');
    }
  }

  Widget _voiceTile(
    _VoiceNote v, {
    required String playKey,
    required Future<void> Function() onDelete,
    Future<void> Function()? onRename,
  }) {
    final isThis = _playingKey == playKey;
    final icon = isThis && _isPlaying
        ? Icons.pause_circle_outline
        : Icons.play_circle_outline;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.35),
      ),
      child: ListTile(
        leading: IconButton(
          icon: Icon(icon),
          onPressed: () => _togglePlay(v, playKey: playKey),
        ),
        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          v.createdAt.isEmpty ? '' : 'Added: ${v.createdAt}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _coreVoiceSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'About me (Voice)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _savingCoreVoice ? null : _uploadCoreVoiceFile,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_savingCoreVoice ? 'Saving…' : 'Upload VN'),
                ),
              ),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: (_savingCoreVoice || !_recorder.isSupported)
                      ? null
                      : _recordCoreVoice,
                  icon: const Icon(Icons.mic_none),
                  label: const Text('Record VN'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Optional: a short 20–60s voice intro helps the AI sound more “real”.',
            style: TextStyle(color: Colors.black.withOpacity(0.65)),
          ),
          const SizedBox(height: 10),
          if (_loadingCoreVoice)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_coreVoiceError != null)
            Text(
              'About me load issue (MVP): $_coreVoiceError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else if (_coreVoice == null)
            Text(
              'No voice yet. Record a short 20–60s intro.',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else
            _voiceTile(
              _coreVoice!,
              playKey: 'core:${widget.vaultId}',
              onDelete: _deleteCoreVoice,
              onRename: _renameCoreVoice,
            ),
        ],
      ),
    );
  }

  Future<void> _loadMemoryPhotosForVault() async {
    setState(() {
      _loadingMemoryPhotos = true;
      _memoryPhotoError = null;
      _memoryPhotosById.clear();
    });

    try {
      if (_memories.isEmpty) {
        setState(() => _loadingMemoryPhotos = false);
        return;
      }

      final rows = await _client
          .from('memory_photos')
          .select('id, memory_id, path, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final futures = list.map((r) async {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) return null;

        final url = await _signedUrl(_memoryPhotosBucket, path);
        if (url == null || url.trim().isEmpty) return null;

        return _MemPhoto(id: id, memoryId: memoryId, path: path, url: url);
      }).toList();

      final resolved = await Future.wait(futures);
      for (final p in resolved) {
        if (p == null) continue;
        _memoryPhotosById.putIfAbsent(p.memoryId, () => []).add(p);
      }

      if (!mounted) return;
      setState(() => _loadingMemoryPhotos = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMemoryPhotos = false;
        _memoryPhotoError = e.toString();
      });
    }
  }

  Future<void> _uploadMemoryPhoto(String memoryId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received');

      final image = await ImageUploadOptimizer.optimize(
        bytes,
        kind: MediaUploadKind.photo,
        fileName: file.name,
        contentType: _contentTypeFromExt(_extFromName(file.name)),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path =
          '$userId/${widget.vaultId}/memories/$memoryId/$ts.${image.extension}';

      await _client.storage
          .from(_memoryPhotosBucket)
          .uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: image.contentType,
            ),
          );

      await _client.from('memory_photos').insert({
        'vault_id': widget.vaultId,
        'memory_id': memoryId,
        'path': path,
      });

      await _loadMemoryPhotosForVault();
      _toast('Photo added to memory.');
    } catch (e) {
      await _handleUploadError(e, 'Add photo failed');
    }
  }

  Future<void> _deleteMemoryPhoto(_MemPhoto p) async {
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
      await _client.storage.from(_memoryPhotosBucket).remove([p.path]);
      await _client.from('memory_photos').delete().eq('id', p.id);
      await _loadMemoryPhotosForVault();
      _toast('Photo deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  void _openMemoryGallery(String memoryId) {
    final photos = _memoryPhotosById[memoryId] ?? [];
    if (photos.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final pc = PageController();
        int idx = 0;

        final maxH = MediaQuery.of(ctx).size.height * 0.85;
        final maxW = MediaQuery.of(ctx).size.width * 0.95;

        return StatefulBuilder(
          builder: (ctx, setInner) {
            final total = photos.length;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Memory photos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.black,
                            child: PageView.builder(
                              controller: pc,
                              itemCount: total,
                              onPageChanged: (v) => setInner(() => idx = v),
                              itemBuilder: (_, i) {
                                final p = photos[i];
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: InteractiveViewer(
                                        minScale: 1,
                                        maxScale: 4,
                                        child: Image.network(
                                          p.url,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.center,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: InkWell(
                                        onTap: () async {
                                          await _deleteMemoryPhoto(p);
                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx);
                                        },
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.black
                                              .withOpacity(0.55),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${idx + 1} / $total',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.65),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: () => _uploadMemoryPhoto(memoryId),
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Add'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
        ),
      );
    }

    if (_memoryPhotoError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Photo load issue (MVP): $_memoryPhotoError',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
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
          separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                    border: Border.all(color: Colors.black.withOpacity(0.10)),
                    color: Colors.white.withOpacity(0.35),
                  ),
                  child: Icon(Icons.add, color: Colors.black.withOpacity(0.65)),
                ),
              );
            }

            final p = preview[i - 1];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openMemoryGallery(memoryId),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    _memoryPhotoImage(
                      p.url,
                      width: 92,
                      height: 66,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: InkWell(
                        onTap: () => _deleteMemoryPhoto(p),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black.withOpacity(0.55),
                          child: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: Colors.white,
                          ),
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

  String _memoryVoicePrefix(String userId, String memoryId) =>
      '$userId/${widget.vaultId}/memories/$memoryId/voice';

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

  Future<void> _loadMemoryVoiceForVault() async {
    setState(() {
      _loadingMemoryVoice = true;
      _memoryVoiceError = null;
      _memoryVoiceById.clear();
    });

    try {
      if (_memories.isEmpty) {
        setState(() => _loadingMemoryVoice = false);
        return;
      }

      final rows = await _client
          .from('memory_voice_notes')
          .select('id, memory_id, path, title, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();

      _memoryVoiceById.clear();
      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        final title = (r['title'] ?? '').toString().trim();
        final createdAt = (r['created_at'] ?? '').toString();
        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_memoryVoiceBucket, path);
        if (url == null || url.trim().isEmpty) continue;

        _memoryVoiceById
            .putIfAbsent(memoryId, () => [])
            .add(
              _VoiceNote(
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMemoryVoice = false;
        _memoryVoiceError = e.toString();
      });
    }
  }

  Future<void> _uploadMemoryVoice(String memoryId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'webm'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received');

      final ext = _extFromName(file.name);
      MediaUploadPolicy.validateUint8ListOrThrow(
        MediaUploadKind.voice,
        bytes,
        fileName: file.name,
        contentType: _contentTypeFromExt(ext),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_memoryVoicePrefix(userId, memoryId)}/$ts.$ext';

      await _client.storage
          .from(_memoryVoiceBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      final inserted = await _client
          .from('memory_voice_notes')
          .insert({
            'vault_id': widget.vaultId,
            'memory_id': memoryId,
            'path': path,
            'title': file.name,
          })
          .select('id')
          .maybeSingle();

      final memoryVoiceNoteId = (inserted?['id'] ?? '').toString().trim();

      if (memoryVoiceNoteId.isNotEmpty) {
        final token = _client.auth.currentSession?.accessToken.trim();
        if (token == null || token.isEmpty) {
          throw Exception('Missing session token. Please sign in again.');
        }

        final res = await _client.functions.invoke(
          'index_voice_note',
          headers: {
            'Authorization': 'Bearer $token',
            'authorization': 'Bearer $token',
          },
          body: {
            'vault_id': widget.vaultId,
            'memory_voice_note_id': memoryVoiceNoteId,
          },
        );

        if (res.status != 200) {
          throw Exception(
            'index_voice_note failed: HTTP ${res.status}: ${res.data}',
          );
        }
      }

      await _loadMemoryVoiceForVault();
      _toast('Voice added to memory.');
    } catch (e) {
      await _handleUploadError(e, 'Add voice failed');
    }
  }

  Future<void> _recordMemoryVoice(String memoryId) async {
    await _openRecordDialog(
      title: 'Record memory voice',
      subtitle: 'Add a voice note that belongs to this memory.',
      onSave: (rec, seconds) async {
        try {
          final userId = _client.auth.currentUser?.id;
          if (userId == null) throw Exception('Not signed in');

          final ts = DateTime.now().millisecondsSinceEpoch;
          final path =
              '${_memoryVoicePrefix(userId, memoryId)}/$ts.${rec.extension}';
          MediaUploadPolicy.validateListOrThrow(
            MediaUploadKind.voice,
            rec.bytes,
            fileName: 'voice.${rec.extension}',
            contentType: rec.mimeType,
          );

          await _client.storage
              .from(_memoryVoiceBucket)
              .uploadBinary(
                path,
                Uint8List.fromList(rec.bytes),
                fileOptions: FileOptions(
                  upsert: false,
                  contentType: rec.mimeType,
                ),
              );

          final inserted = await _client
              .from('memory_voice_notes')
              .insert({
                'vault_id': widget.vaultId,
                'memory_id': memoryId,
                'path': path,
                'title': 'Voice note',
                'duration_seconds': seconds,
              })
              .select('id')
              .maybeSingle();

          final memoryVoiceNoteId = (inserted?['id'] ?? '').toString().trim();

          if (memoryVoiceNoteId.isNotEmpty) {
            final token = _client.auth.currentSession?.accessToken.trim();
            if (token == null || token.isEmpty) {
              throw Exception('Missing session token. Please sign in again.');
            }

            final res = await _client.functions.invoke(
              'index_voice_note',
              headers: {
                'Authorization': 'Bearer $token',
                'authorization': 'Bearer $token',
              },
              body: {
                'vault_id': widget.vaultId,
                'memory_voice_note_id': memoryVoiceNoteId,
              },
            );

            if (res.status != 200) {
              throw Exception(
                'index_voice_note failed: HTTP ${res.status}: ${res.data}',
              );
            }
          }

          await _loadMemoryVoiceForVault();
          _toast('Voice added to memory.');
        } catch (e) {
          await _handleUploadError(e, 'Add voice failed');
        }
      },
    );
  }

  Future<void> _deleteMemoryVoice(String memoryId, _VoiceNote v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voice note?'),
        content: const Text('This will permanently delete this voice note.'),
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
      final key = 'mem:${v.id}';
      if (_playingKey == key) {
        await _player.stop();
        if (mounted) setState(() => _playingKey = null);
      }

      await _client.storage.from(_memoryVoiceBucket).remove([v.path]);
      await _client.from('memory_voice_notes').delete().eq('id', v.id);
      await _loadMemoryVoiceForVault();
      await IndexingService.indexMemory(
        vaultId: widget.vaultId,
        memoryId: memoryId,
      );
      _toast('Voice note deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _renameMemoryVoice(String memoryId, _VoiceNote v) async {
    final newTitle = await _promptRename(
      title: 'Rename voice note',
      initial: v.title,
      hint: 'Voice note title',
    );
    if (newTitle == null || newTitle.isEmpty) return;

    try {
      await _client
          .from('memory_voice_notes')
          .update({'title': newTitle})
          .eq('id', v.id);
      await _loadMemoryVoiceForVault();
      _toast('Renamed.');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  void _openAllMemoryVoiceNotes(String memoryId, String prompt) {
    final notes = _memoryVoiceById[memoryId] ?? [];
    if (notes.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Voice notes • $prompt',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: notes.length,
                    itemBuilder: (_, i) {
                      final v = notes[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.08),
                          ),
                          color: Colors.white.withOpacity(0.35),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: IconButton(
                            icon: Icon(
                              (_playingKey == 'mem:${v.id}' && _isPlaying)
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                            onPressed: () =>
                                _togglePlay(v, playKey: 'mem:${v.id}'),
                          ),
                          title: Text(
                            v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Rename',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  await _renameMemoryVoice(memoryId, v);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await _deleteMemoryVoice(memoryId, v);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _memoryVoiceStrip(String memoryId, String prompt) {
    final notes = _memoryVoiceById[memoryId] ?? [];
    final preview = notes.take(2).toList();

    if (_loadingMemoryVoice) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Loading voice…',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
        ),
      );
    }

    if (_memoryVoiceError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Voice load issue (MVP): $_memoryVoiceError',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => _uploadMemoryVoice(memoryId),
                  icon: const Icon(Icons.mic_none, size: 18),
                  label: const Text('Add voice'),
                ),
              ),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _recorder.isSupported
                      ? () => _recordMemoryVoice(memoryId)
                      : null,
                  icon: const Icon(Icons.fiber_manual_record, size: 18),
                  label: const Text('Record'),
                ),
              ),
              if (notes.length > 2)
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () => _openAllMemoryVoiceNotes(memoryId, prompt),
                    icon: const Icon(Icons.library_music_outlined, size: 18),
                    label: Text('View all (${notes.length})'),
                  ),
                ),
            ],
          ),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No voice on this memory yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            )
          else
            Column(
              children: preview.map((v) {
                return Container(
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                    color: Colors.white.withOpacity(0.35),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: IconButton(
                      icon: Icon(
                        (_playingKey == 'mem:${v.id}' && _isPlaying)
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                      ),
                      onPressed: () => _togglePlay(v, playKey: 'mem:${v.id}'),
                    ),
                    title: Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _renameMemoryVoice(memoryId, v),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteMemoryVoice(memoryId, v),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        throw Exception('No active session. Please sign in again.');
      }

      final data = await _client
          .from('memories')
          .select(
            'id, vault_id, life_stage, prompt_key, prompt_text, body, created_at, share_to_family_feed, memory_date_label, people, location, mood',
          )
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      setState(() {
        _memories = List<Map<String, dynamic>>.from(data);
      });

      unawaited(_loadMemoryPhotosForVault());
      unawaited(_loadMemoryVoiceForVault());
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _error =
            'Timed out loading memories. Check internet / Supabase URL / auth.',
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Postgrest: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openAddMemory({
    String? initialLifeStage,
    String initialMode = 'text',
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(
          vaultId: widget.vaultId,
          initialLifeStage: initialLifeStage,
          initialMode: initialMode,
          displayName: _displayName ?? _vaultName,
          avatarUrl: _avatarUrl,
        ),
      ),
    );

    if (saved == true) {
      await _loadMemories();
      _toast('Memory saved.');
    }
  }

  Widget _memoryComposerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openAddMemory(),
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
                      'What memory would you like to preserve next?',
                      style: TextStyle(color: Colors.black.withOpacity(0.68)),
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
              _composerAction(Icons.edit_note, 'Write a memory', 'text'),
              _composerAction(
                Icons.photo_camera_outlined,
                'Add photos',
                'photo',
              ),
              _composerAction(Icons.mic_none, 'Record voice', 'voice'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composerAction(IconData icon, String label, String mode) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: const Color(0xFF76558F)),
      label: Text(label),
      onPressed: () => _openAddMemory(initialMode: mode),
    );
  }

  Widget _socialHighlightsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
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
                onPressed: _uploadingPhoto ? null : _uploadFeaturedPhoto,
                icon: const Icon(Icons.add, size: 18),
                label: Text(_uploadingPhoto ? 'Adding…' : 'Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingPhotos)
            const Center(child: CircularProgressIndicator())
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _featuredPhotos.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == _featuredPhotos.length) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _uploadingPhoto ? null : _uploadFeaturedPhoto,
                      child: Container(
                        width: 104,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2E7F5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF76558F).withOpacity(0.18),
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 30),
                            SizedBox(height: 8),
                            Text('New highlight'),
                          ],
                        ),
                      ),
                    );
                  }
                  final photo = _featuredPhotos[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openHighlightsGallery,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        photo['url'] ?? '',
                        width: 104,
                        height: 132,
                        fit: BoxFit.cover,
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

  Widget _vaultSectionPicker() {
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
        selected: {_selectedVaultSection},
        onSelectionChanged: (selection) {
          setState(() => _selectedVaultSection = selection.first);
        },
      ),
    );
  }

  Future<void> _setMemoryFeedVisibility(
    Map<String, dynamic> memory,
    bool share,
  ) async {
    final id = (memory['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await _client
          .from('memories')
          .update({'share_to_family_feed': share})
          .eq('id', id);
      await _loadMemories();
      _toast(
        share ? 'Shared to your family feed.' : 'Removed from the family feed.',
      );
    } catch (e) {
      _toast('Could not update sharing: $e');
    }
  }

  Widget _socialMemoryCard(Map<String, dynamic> memory) {
    final memoryId = (memory['id'] ?? '').toString();
    final prompt = (memory['prompt_text'] ?? '').toString();
    final body = (memory['body'] ?? '').toString();
    final stage = (memory['life_stage'] ?? '').toString();
    final promptKey = (memory['prompt_key'] ?? '').toString();
    final isSocialMemory = promptKey.startsWith('social_memory_');
    final when = (memory['memory_date_label'] ?? '').toString().trim();
    final people = (memory['people'] ?? '').toString().trim();
    final location = (memory['location'] ?? '').toString().trim();
    final shared = memory['share_to_family_feed'] != false;
    final photos = _memoryPhotosById[memoryId] ?? const <_MemPhoto>[];
    final notes = _memoryVoiceById[memoryId] ?? const <_VoiceNote>[];
    final name = (_displayName ?? _vaultName).trim();
    final hasAvatar = (_avatarUrl ?? '').trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white.withOpacity(0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
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
                  backgroundImage: hasAvatar ? NetworkImage(_avatarUrl!) : null,
                  child: hasAvatar ? null : const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'My vault' : name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${isSocialMemory ? 'Memory' : _prettyStage(stage)} · ${shared ? 'Shared with family' : 'Not in family feed'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Memory options',
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editMemory(memory);
                    }
                    if (value == 'share') {
                      _setMemoryFeedVisibility(memory, !shared);
                    }
                    if (value == 'delete') {
                      _deleteMemory(memory);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit memory'),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Text(
                        shared
                            ? 'Remove from family feed'
                            : 'Share to family feed',
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
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
            if (when.isNotEmpty ||
                people.isNotEmpty ||
                location.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (when.isNotEmpty)
                    Chip(
                      avatar: const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                      ),
                      label: Text(when),
                    ),
                  if (people.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.people_outline, size: 16),
                      label: Text(people),
                    ),
                  if (location.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(location),
                    ),
                ],
              ),
            ],
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => InkWell(
                    onTap: () => _openMemoryGallery(memoryId),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _memoryPhotoImage(
                        photos[index].url,
                        width: photos.length == 1 ? 520 : 260,
                        height: 230,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...notes
                  .take(2)
                  .map(
                    (note) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        icon: Icon(
                          _playingKey == 'mem:${note.id}' && _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                        ),
                        onPressed: () =>
                            _togglePlay(note, playKey: 'mem:${note.id}'),
                      ),
                      title: Text(note.title),
                      subtitle: const Text('Voice memory'),
                    ),
                  ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _uploadMemoryPhoto(memoryId),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Photo'),
                ),
                TextButton.icon(
                  onPressed: _recorder.isSupported
                      ? () => _recordMemoryVoice(memoryId)
                      : null,
                  icon: const Icon(Icons.mic_none),
                  label: const Text('Record'),
                ),
                const Spacer(),
                Icon(
                  shared
                      ? Icons.family_restroom
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Colors.black.withOpacity(0.46),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaSection() {
    final media = [..._featuredPhotos, ..._aboutPhotos];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your media',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (media.isEmpty)
            const Text('Photos and recordings you add will appear here.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: media.length,
              itemBuilder: (_, index) => ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  media[index]['url'] ?? '',
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _renameVault() async {
    final controller = TextEditingController(text: _vaultName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(
            labelText: 'Vault name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await _client
          .from('vaults')
          .update({'name': newName})
          .eq('id', widget.vaultId);

      setState(() => _vaultName = newName);

      if ((_displayName == null || _displayName!.trim().isEmpty) && mounted) {
        setState(() => _displayName = newName);
      }

      _toast('Vault renamed.');
    } on PostgrestException catch (e) {
      _toast('Rename failed: ${e.message}');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _editMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();
    final isSocialMemory = (m['prompt_key'] ?? '').toString().startsWith(
      'social_memory_',
    );

    final promptController = TextEditingController(
      text: (m['prompt_text'] ?? '').toString(),
    );
    final bodyController = TextEditingController(
      text: (m['body'] ?? '').toString(),
    );
    final whenController = TextEditingController(
      text: (m['memory_date_label'] ?? '').toString(),
    );
    final peopleController = TextEditingController(
      text: (m['people'] ?? '').toString(),
    );
    final locationController = TextEditingController(
      text: (m['location'] ?? '').toString(),
    );
    String? selectedMood = (m['mood'] ?? '').toString().trim();
    if (selectedMood.isEmpty) selectedMood = null;
    var showDetails =
        selectedMood != null ||
        whenController.text.trim().isNotEmpty ||
        peopleController.text.trim().isNotEmpty ||
        locationController.text.trim().isNotEmpty;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final photos = _memoryPhotosById[memoryId] ?? const <_MemPhoto>[];
          final notes = _memoryVoiceById[memoryId] ?? const <_VoiceNote>[];

          return AlertDialog(
            title: const Text('Edit memory'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: promptController,
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        labelText: isSocialMemory
                            ? 'Title (optional)'
                            : 'Prompt (question)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Memory',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
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
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: whenController,
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
                                    controller: peopleController,
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
                                    controller: locationController,
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Photos',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await _uploadMemoryPhoto(memoryId);
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    if (photos.isEmpty)
                      const Text(
                        'No photos on this memory.',
                        style: TextStyle(color: Colors.black54),
                      )
                    else
                      SizedBox(
                        height: 126,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, index) {
                            final photo = photos[index];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _memoryPhotoImage(
                                    photo.url,
                                    width: 126,
                                    height: 126,
                                  ),
                                ),
                                Positioned(
                                  top: 5,
                                  right: 5,
                                  child: IconButton.filledTonal(
                                    tooltip: 'Remove photo',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      await _deleteMemoryPhoto(photo);
                                      if (dialogContext.mounted) {
                                        setDialogState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Voice notes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _recorder.isSupported
                              ? () async {
                                  await _recordMemoryVoice(memoryId);
                                  if (dialogContext.mounted) {
                                    setDialogState(() {});
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.mic_none),
                          label: const Text('Record'),
                        ),
                      ],
                    ),
                    if (notes.isEmpty)
                      const Text(
                        'No voice notes on this memory.',
                        style: TextStyle(color: Colors.black54),
                      )
                    else
                      ...notes.map(
                        (note) => Card(
                          elevation: 0,
                          child: ListTile(
                            leading: IconButton(
                              tooltip: 'Play voice note',
                              onPressed: () =>
                                  _togglePlay(note, playKey: 'mem:${note.id}'),
                              icon: Icon(
                                _playingKey == 'mem:${note.id}' && _isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                              ),
                            ),
                            title: Text(note.title),
                            subtitle: const Text('Voice note'),
                            trailing: IconButton(
                              tooltip: 'Remove voice note',
                              onPressed: () async {
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'prompt_text': promptController.text.trim(),
                  'body': bodyController.text.trim(),
                  'memory_date_label': whenController.text.trim(),
                  'people': peopleController.text.trim(),
                  'location': locationController.text.trim(),
                  'mood': selectedMood ?? '',
                }),
                child: const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;

    final newPromptText = (result['prompt_text'] ?? '').trim();
    final newBody = (result['body'] ?? '').trim();
    final newWhen = (result['memory_date_label'] ?? '').trim();
    final newPeople = (result['people'] ?? '').trim();
    final newLocation = (result['location'] ?? '').trim();
    final newMood = (result['mood'] ?? '').trim();

    if (!isSocialMemory && newPromptText.isEmpty) {
      _toast('Prompt cannot be empty.');
      return;
    }
    final hasMedia =
        (_memoryPhotosById[memoryId]?.isNotEmpty ?? false) ||
        (_memoryVoiceById[memoryId]?.isNotEmpty ?? false);
    if (newBody.isEmpty && !hasMedia) {
      _toast('Add some text, a photo, or a voice note first.');
      return;
    }

    try {
      await _client
          .from('memories')
          .update({
            'prompt_text': newPromptText,
            'body': newBody,
            'memory_date_label': newWhen,
            'people': newPeople,
            'location': newLocation,
            'mood': newMood.isEmpty ? null : newMood,
          })
          .eq('id', memoryId);

      await IndexingService.indexMemory(
        vaultId: widget.vaultId,
        memoryId: memoryId,
      );

      await _loadMemories();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update/index failed: $e');
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete memory?'),
        content: Text('Delete this memory permanently?\n\n$prompt'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _client.from('memories').delete().eq('id', memoryId);
      await _loadMemories();
      _toast('Memory deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
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

  Future<void> _reindexVaultNow() async {
    if (_reindexing) return;
    setState(() => _reindexing = true);
    try {
      final n = await IndexingService.backfillVault(vaultId: widget.vaultId);
      _toast('AI index updated: $n memories indexed');
    } catch (e) {
      _toast('Re-index failed: $e');
    } finally {
      if (mounted) setState(() => _reindexing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Vault'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadVaultMeta();
              await _loadFeaturedPhotos();
              await _loadAboutMe();
              await _loadAboutPhotos();
              await _loadCoreVoice();
              await _loadMemories();
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'rename') _renameVault();
              if (value == 'index') _reindexVaultNow();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit vault name'),
                ),
              ),
              PopupMenuItem(
                value: 'index',
                enabled: !_reindexing,
                child: ListTile(
                  leading: Icon(
                    _reindexing ? Icons.hourglass_top : Icons.auto_fix_high,
                  ),
                  title: Text(_reindexing ? 'Updating AI…' : 'Update AI index'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddMemory(),
        icon: const Icon(Icons.add),
        label: const Text('Memory'),
      ),
      body: LogoWatermark(
        opacity: 0.03,
        size: 760,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Load failed: $_error'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _vaultAvatarHeader(),
                      _memoryComposerCard(),
                      _socialHighlightsSection(),
                      _vaultSectionPicker(),
                      if (_selectedVaultSection == 0) ...[
                        if (_memories.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.auto_stories_outlined,
                                  size: 42,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your story starts here',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Preserve a moment for the people you love.',
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: () => _openAddMemory(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Share your first memory'),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._memories.map(_socialMemoryCard),
                      ],
                      if (_selectedVaultSection == 1) ...[
                        _aboutMeSection(),
                        _coreVoiceSection(),
                      ],
                      if (_selectedVaultSection == 2) _mediaSection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _MemPhoto {
  final String id;
  final String memoryId;
  final String path;
  final String url;

  const _MemPhoto({
    required this.id,
    required this.memoryId,
    required this.path,
    required this.url,
  });
}

class _VoiceNote {
  final String id;
  final String path;
  final String title;
  final String url;
  final String createdAt;

  const _VoiceNote({
    required this.id,
    required this.path,
    required this.title,
    required this.url,
    required this.createdAt,
  });
}
