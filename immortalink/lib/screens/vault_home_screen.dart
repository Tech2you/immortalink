// lib/screens/vault_home_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/web_audio_recorder.dart';
import '../widgets/logo_watermark.dart';
import 'create_memory_screen.dart';
import 'vault_companion_screen.dart';

class VaultHomeScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;

  const VaultHomeScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
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

  // --- Featured photos (highlights) ---
  bool _loadingPhotos = true;
  bool _uploadingPhoto = false;
  List<Map<String, String>> _featuredPhotos = []; // {path,url}

  // Netflix-style carousel state
  final PageController _highlightController = PageController();
  Timer? _autoSlideTimer;
  int _highlightIndex = 0;

  // --- Memory photos ---
  bool _loadingMemoryPhotos = true;
  String? _memoryPhotoError;
  final Map<String, List<_MemPhoto>> _memoryPhotosById = {};

  // --- Core voice note (one per vault) ---
  bool _loadingCoreVoice = true;
  String? _coreVoiceError;
  bool _savingCoreVoice = false;
  _VoiceNote? _coreVoice; // uses same model

  // --- Memory voice notes ---
  bool _loadingMemoryVoice = true;
  String? _memoryVoiceError;
  final Map<String, List<_VoiceNote>> _memoryVoiceById = {};

  // Playback
  final AudioPlayer _player = AudioPlayer();
  String? _playingKey; // e.g. "core:vaultId" OR "vault:<id>" OR "mem:<id>"
  bool _isPlaying = false;

  // Web recorder (safe on non-web)
  final WebAudioRecorder _recorder = createWebAudioRecorder();

  // Buckets
  static const String _avatarBucket = 'avatars';
  static const String _featuredPhotosBucket = 'vault_photos';
  static const String _memoryPhotosBucket = 'memory_photos';
  static const String _voiceBucket = 'vault_voice';
  static const String _memoryVoiceBucket = 'memory_voice';

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
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _highlightController.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _extFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.webp')) return 'webp';

    // audio
    if (lower.endsWith('.m4a')) return 'm4a';
    if (lower.endsWith('.mp3')) return 'mp3';
    if (lower.endsWith('.wav')) return 'wav';
    if (lower.endsWith('.aac')) return 'aac';
    if (lower.endsWith('.ogg')) return 'ogg';
    if (lower.endsWith('.webm')) return 'webm';

    return 'bin';
  }

  String _contentTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'png') return 'image/png';

    // audio mime types
    if (e == 'mp3') return 'audio/mpeg';
    if (e == 'm4a') return 'audio/mp4';
    if (e == 'wav') return 'audio/wav';
    if (e == 'aac') return 'audio/aac';
    if (e == 'ogg') return 'audio/ogg';
    if (e == 'webm') return 'audio/webm';

    return 'application/octet-stream';
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    try {
      final signed = await _client.storage.from(bucket).createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  /* =========================
     UNIVERSAL RECORD DIALOG
  ========================== */

  Future<void> _openRecordDialog({
    required String title,
    required String subtitle,
    required Future<void> Function(RecordedAudio rec) onSave,
  }) async {
    if (!_recorder.isSupported) {
      _toast('Recording not supported in this browser (use Upload for now).');
      return;
    }

    bool saving = false;
    String? err;
    int seconds = 0;
    Timer? t;

    Future<void> stopAndSave(StateSetter setInner) async {
      if (saving) return;
      setInner(() {
        saving = true;
        err = null;
      });

      try {
        final rec = await _recorder.stop();
        await onSave(rec);
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
                t?.cancel();
                t = Timer.periodic(const Duration(seconds: 1), (_) {
                  seconds += 1;
                  if (ctx.mounted) setInner(() {});
                });
              } catch (e) {
                setInner(() => err = e.toString());
              }
            }

            WidgetsBinding.instance.addPostFrameCallback((_) => startIfNeeded());

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
                          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black.withOpacity(0.08)),
                        color: Colors.white.withOpacity(0.45),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mic, color: Colors.black.withOpacity(0.65)),
                          const SizedBox(width: 10),
                          Text(
                            saving ? 'Saving…' : (_recorder.isRecording ? 'Recording…' : 'Starting…'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            mmss(seconds),
                            style: TextStyle(color: Colors.black.withOpacity(0.65), fontFeatures: const []),
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
                      style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
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

  /* =========================
     VAULT META (avatar/name)
  ========================== */

  Future<void> _loadVaultMeta() async {
    try {
      final res = await _client
          .from('vaults')
          .select('avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      if (!mounted) return;

      final path = (res?['avatar_path'] as String?)?.trim();
      final dn = (res?['display_name'] as String?) ?? (res?['name'] as String?) ?? _vaultName;

      String? signedUrl;
      if (path != null && path.isNotEmpty) {
        signedUrl = await _signedUrl(_avatarBucket, path);
      }

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
        _displayName = (dn ?? _vaultName).trim().isEmpty ? _vaultName : (dn ?? _vaultName).trim();
      });
    } catch (_) {
      // silent
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      setState(() => _savingAvatar = true);

      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final ext = _extFromName(file.name);
      final path = '$userId/${widget.vaultId}/avatar.$ext';

      await _client.storage.from(_avatarBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _client.from('vaults').update({'avatar_path': path}).eq('id', widget.vaultId);

      final signedUrl = await _signedUrl(_avatarBucket, path);

      if (!mounted) return;

      setState(() {
        _avatarPath = path;
        _avatarUrl = signedUrl;
      });

      _toast('Vault photo updated.');
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  void _openAskAI() {
    final name = (_displayName ?? _vaultName).trim().isEmpty ? 'Vault' : (_displayName ?? _vaultName).trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultCompanionScreen(
          vaultId: widget.vaultId,
          displayName: name,
        ),
      ),
    );
  }

  Widget _vaultAvatarHeader() {
    final name = (_displayName ?? _vaultName).trim().isEmpty ? 'Your vault' : (_displayName ?? _vaultName).trim();
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.35),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.black.withOpacity(0.06),
            backgroundImage: hasAvatar ? NetworkImage(_avatarUrl!) : null,
            child: !hasAvatar ? Icon(Icons.person, color: Colors.black.withOpacity(0.45), size: 28) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Text + Photos + Voice',
                  style: TextStyle(fontSize: 12.5, color: Colors.black.withOpacity(0.60)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _openAskAI,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Ask (AI)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _savingAvatar ? null : _pickAndUploadAvatar,
            child: Text(_savingAvatar ? 'Uploading…' : 'Change'),
          ),
        ],
      ),
    );
  }

  /* =========================
     FEATURED PHOTOS (Highlights)
  ========================== */

  String _featuredPrefix(String userId) => '$userId/${widget.vaultId}/featured';
  int get _highlightsCount => _featuredPhotos.length >= 3 ? 3 : _featuredPhotos.length;

  void _setupAutoSlide() {
    _autoSlideTimer?.cancel();
    final n = _highlightsCount;
    if (n <= 1) return;

    _highlightIndex = 0;
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
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

      final prefix = _featuredPrefix(userId);

      final list = await _client.storage.from(_featuredPhotosBucket).list(
            path: prefix,
            searchOptions: const SearchOptions(limit: 200, offset: 0),
          );

      final items = <Map<String, String>>[];
      for (final obj in list) {
        final name = obj.name.toString();
        if (name.trim().isEmpty) continue;

        final fullPath = '$prefix/$name';
        final url = await _signedUrl(_featuredPhotosBucket, fullPath);
        if (url == null || url.trim().isEmpty) continue;

        items.add({'path': fullPath, 'url': url});
      }

      if (!mounted) return;

      setState(() {
        _featuredPhotos = items;
        _loadingPhotos = false;
      });

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

      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received.');

      final ext = _extFromName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_featuredPrefix(userId)}/$ts.$ext';

      await _client.storage.from(_featuredPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _loadFeaturedPhotos();
      _toast('Added to highlights.');
    } catch (e) {
      _toast('Photo upload failed: $e');
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _client.storage.from(_featuredPhotosBucket).remove([fullPath]);
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

        return StatefulBuilder(
          builder: (ctx, setInner) {
            final total = _featuredPhotos.length;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('All photos', style: TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PageView.builder(
                          controller: pc,
                          itemCount: total,
                          onPageChanged: (v) => setInner(() => idx = v),
                          itemBuilder: (_, i) {
                            final url = _featuredPhotos[i]['url'] ?? '';
                            final path = _featuredPhotos[i]['path'] ?? '';
                            return Stack(
                              children: [
                                Positioned.fill(child: Image.network(url, fit: BoxFit.cover)),
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
                                      backgroundColor: Colors.black.withOpacity(0.55),
                                      child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('${idx + 1} / $total', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                        const Spacer(),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: _uploadingPhoto ? null : _uploadFeaturedPhoto,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: Text(_uploadingPhoto ? 'Uploading…' : 'Add'),
                          ),
                        ),
                      ],
                    ),
                  ],
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
              const Text('Your highlights', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                'Favourite photos / memories',
                style: TextStyle(fontSize: 12.5, color: Colors.black.withOpacity(0.55)),
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
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PageView.builder(
                        controller: _highlightController,
                        itemCount: _highlightsCount,
                        onPageChanged: (i) => setState(() => _highlightIndex = i),
                        itemBuilder: (_, i) {
                          final url = _featuredPhotos[i]['url'] ?? '';
                          final path = _featuredPhotos[i]['path'] ?? '';
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
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
                                    backgroundColor: Colors.black.withOpacity(0.55),
                                    child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                                  ),
                                ),
                              ),
                              const Positioned(
                                left: 12,
                                bottom: 12,
                                child: Text(
                                  'Tap to view all',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dots(
                    _highlightsCount,
                    _highlightIndex.clamp(0, (_highlightsCount - 1).clamp(0, 99)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /* =========================
     CORE VOICE NOTE
     Table: vault_core_voice_note (one row per vault)
  ========================== */

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
          title: title.isEmpty ? 'Core message' : title,
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
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_voicePrefix(userId)}/core_$ts.$ext';

      await _client.storage.from(_voiceBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _client.from('vault_core_voice_note').upsert(
        {
          'vault_id': widget.vaultId,
          'path': path,
          'title': 'Core message',
        },
        onConflict: 'vault_id',
      );

      await _loadCoreVoice();
      _toast('Core voice note saved.');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingCoreVoice = false);
    }
  }

  Future<void> _recordCoreVoice() async {
    await _openRecordDialog(
      title: 'Record your core message',
      subtitle: 'If they only hear one thing — what should they know about you?',
      onSave: (rec) async {
        setState(() => _savingCoreVoice = true);

        final userId = _client.auth.currentUser?.id;
        if (userId == null) throw Exception('Not signed in');

        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '${_voicePrefix(userId)}/core_$ts.${rec.extension}';

        await _client.storage.from(_voiceBucket).uploadBinary(
              path,
              Uint8List.fromList(rec.bytes),
              fileOptions: FileOptions(
                upsert: false,
                contentType: rec.mimeType,
              ),
            );

        await _client.from('vault_core_voice_note').upsert(
          {
            'vault_id': widget.vaultId,
            'path': path,
            'title': 'Core message',
          },
          onConflict: 'vault_id',
        );

        await _loadCoreVoice();
        if (mounted) setState(() => _savingCoreVoice = false);
        _toast('Core voice note saved.');
      },
    );
  }

  Future<void> _deleteCoreVoice() async {
    final v = _coreVoice;
    if (v == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete core message?'),
        content: const Text('This will permanently delete your core voice note.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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
      await _client.from('vault_core_voice_note').delete().eq('vault_id', widget.vaultId);
      await _loadCoreVoice();
      _toast('Core voice note deleted.');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _renameCoreVoice() async {
    final v = _coreVoice;
    if (v == null) return;

    final newTitle = await _promptRename(
      title: 'Rename core message',
      initial: v.title,
      hint: 'Core message title',
    );
    if (newTitle == null || newTitle.isEmpty) return;

    try {
      await _client.from('vault_core_voice_note').update({'title': newTitle}).eq('vault_id', widget.vaultId);
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
    final icon = isThis && _isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline;

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
        title: Text(
          v.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
              tooltip: 'Delete voice note',
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
          Row(
            children: [
              const Text('Core voice note', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _savingCoreVoice ? null : _uploadCoreVoiceFile,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_savingCoreVoice ? 'Saving…' : 'Upload'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: (_savingCoreVoice || !_recorder.isSupported) ? null : _recordCoreVoice,
                  icon: const Icon(Icons.mic_none),
                  label: const Text('Record'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'If they only look at one thing — this is what you want your family to know about you.',
            style: TextStyle(color: Colors.black.withOpacity(0.65)),
          ),
          const SizedBox(height: 10),
          if (_loadingCoreVoice)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_coreVoiceError != null)
            Text('Core voice load issue (MVP): $_coreVoiceError', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else if (_coreVoice == null)
            Text(
              'No core message yet. Record a short 30–90s clip.',
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

  /* =========================
     MEMORY PHOTOS
  ========================== */

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

        return _MemPhoto(
          id: id,
          memoryId: memoryId,
          path: path,
          url: url,
        );
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

      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes received');

      final ext = _extFromName(file.name);
      final ts = DateTime.now().millisecondsSinceEpoch;

      final path = '$userId/${widget.vaultId}/memories/$memoryId/$ts.$ext';

      await _client.storage.from(_memoryPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
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
      _toast('Add photo failed: $e');
    }
  }

  Future<void> _deleteMemoryPhoto(_MemPhoto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This will permanently delete this photo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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

        return StatefulBuilder(
          builder: (ctx, setInner) {
            final total = photos.length;

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('Memory photos', style: TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: PageView.builder(
                          controller: pc,
                          itemCount: total,
                          onPageChanged: (v) => setInner(() => idx = v),
                          itemBuilder: (_, i) {
                            final p = photos[i];
                            return Stack(
                              children: [
                                Positioned.fill(child: Image.network(p.url, fit: BoxFit.cover)),
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
                                      backgroundColor: Colors.black.withOpacity(0.55),
                                      child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('${idx + 1} / $total', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                        const Spacer(),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: () => _uploadMemoryPhoto(memoryId),
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Add'),
                          ),
                        ),
                      ],
                    ),
                  ],
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
        child: Text('Loading photos…', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
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
          separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                    Image.network(
                      p.url,
                      width: 92,
                      height: 66,
                      fit: BoxFit.cover,
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
                          child: const Icon(Icons.delete_outline, size: 14, color: Colors.white),
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

  /* =========================
     MEMORY VOICE NOTES
     Table: memory_voice_notes (many per memory)
  ========================== */

  String _memoryVoicePrefix(String userId, String memoryId) => '$userId/${widget.vaultId}/memories/$memoryId/voice';

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

        _memoryVoiceById.putIfAbsent(memoryId, () => []).add(
              _VoiceNote(
                id: id,
                path: path,
                title: title.isEmpty ? 'Voice note' : title,
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
      final ts = DateTime.now().millisecondsSinceEpoch;

      final path = '${_memoryVoicePrefix(userId, memoryId)}/$ts.$ext';

      await _client.storage.from(_memoryVoiceBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      await _client.from('memory_voice_notes').insert({
        'vault_id': widget.vaultId,
        'memory_id': memoryId,
        'path': path,
        'title': file.name,
      });

      await _loadMemoryVoiceForVault();
      _toast('Voice added to memory.');
    } catch (e) {
      _toast('Add voice failed: $e');
    }
  }

  Future<void> _recordMemoryVoice(String memoryId) async {
    await _openRecordDialog(
      title: 'Record memory voice',
      subtitle: 'Add a voice note that belongs to this memory.',
      onSave: (rec) async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) throw Exception('Not signed in');

        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = '${_memoryVoicePrefix(userId, memoryId)}/$ts.${rec.extension}';

        await _client.storage.from(_memoryVoiceBucket).uploadBinary(
              path,
              Uint8List.fromList(rec.bytes),
              fileOptions: FileOptions(
                upsert: false,
                contentType: rec.mimeType,
              ),
            );

        await _client.from('memory_voice_notes').insert({
          'vault_id': widget.vaultId,
          'memory_id': memoryId,
          'path': path,
          'title': 'Recorded $ts.${rec.extension}',
        });

        await _loadMemoryVoiceForVault();
        _toast('Voice added to memory.');
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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
      await _client.from('memory_voice_notes').update({'title': newTitle}).eq('id', v.id);
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
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
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
                          title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        child: Text('Loading voice…', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
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
                  onPressed: _recorder.isSupported ? () => _recordMemoryVoice(memoryId) : null,
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
                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
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
                    title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  /* =========================
     MEMORIES
  ========================== */

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _client
          .from('memories')
          .select('id, vault_id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      setState(() {
        _memories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });

      await _loadMemoryPhotosForVault();
      await _loadMemoryVoiceForVault();
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAddMemory({String? initialLifeStage}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(
          vaultId: widget.vaultId,
          initialLifeStage: initialLifeStage,
        ),
      ),
    );

    if (saved == true) {
      await _loadMemories();
      _toast('Memory saved.');
    }
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
          decoration: const InputDecoration(
            labelText: 'Vault name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await _client.from('vaults').update({'name': newName}).eq('id', widget.vaultId);

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

    final promptController = TextEditingController(text: (m['prompt_text'] ?? '').toString());
    final bodyController = TextEditingController(text: (m['body'] ?? '').toString());

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Prompt (question)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'prompt_text': promptController.text.trim(),
              'body': bodyController.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final newPromptText = (result['prompt_text'] ?? '').trim();
    final newBody = (result['body'] ?? '').trim();

    if (newPromptText.isEmpty) {
      _toast('Prompt cannot be empty.');
      return;
    }
    if (newBody.isEmpty) {
      _toast('Answer cannot be empty.');
      return;
    }

    try {
      await _client.from('memories').update({
        'prompt_text': newPromptText,
        'body': newBody,
      }).eq('id', memoryId);

      await _loadMemories();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update failed: $e');
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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

  @override
  Widget build(BuildContext context) {
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(_vaultName),
        actions: [
          IconButton(
            tooltip: 'Rename vault',
            icon: const Icon(Icons.edit),
            onPressed: _renameVault,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadVaultMeta();
              await _loadFeaturedPhotos();
              await _loadCoreVoice();
              await _loadMemories();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddMemory(initialLifeStage: 'early'),
        child: const Icon(Icons.add),
      ),
      body: LogoWatermark(
        opacity: 0.03,
        size: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Load failed: $_error'))
                  : ListView.separated(
                      itemCount: _memories.isEmpty ? 4 : _memories.length + 3,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        if (i == 0) return _vaultAvatarHeader();
                        if (i == 1) return _featuredPhotosSection();
                        if (i == 2) return _coreVoiceSection();

                        if (_memories.isEmpty && i == 3) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('No memories yet.'),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () => _openAddMemory(initialLifeStage: 'early'),
                                    child: const Text('Add your first memory'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final m = _memories[i - 3];
                        final memoryId = (m['id'] ?? '').toString();
                        final stage = (m['life_stage'] ?? '').toString();
                        final prompt = (m['prompt_text'] ?? '').toString();
                        final body = (m['body'] ?? '').toString();

                        return ListTile(
                          tileColor: tileBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Chip(label: Text(_prettyStage(stage))),
                          title: Text(prompt.isEmpty ? '(No prompt)' : prompt),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
                              _memoryPhotoStrip(memoryId),
                              _memoryVoiceStrip(memoryId, prompt),
                            ],
                          ),
                          onTap: () => _editMemory(m),
                          trailing: IconButton(
                            tooltip: 'Delete memory',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteMemory(m),
                          ),
                        );
                      },
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
