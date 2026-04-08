// lib/screens/vault_readonly_screen.dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';
import 'vault_companion_screen.dart';

class VaultReadOnlyScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;

  const VaultReadOnlyScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
  });

  @override
  State<VaultReadOnlyScreen> createState() => _VaultReadOnlyScreenState();
}

class _VaultReadOnlyScreenState extends State<VaultReadOnlyScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _memories = [];

  // --- ABOUT ME (read-only) ---
  String? _aboutMeText;
  bool _loadingAboutMeText = true;
  String? _aboutMeTextError;

  bool _loadingAboutPhotos = true;
  String? _aboutPhotoError;
  List<Map<String, String>> _aboutPhotos = []; // {path,url}
  final PageController _aboutController = PageController();
  int _aboutIndex = 0;
  String _vaultName = '';

  String? _avatarUrl; // signed url
  String? _displayName;

  String? _ownerId;

  static const String _avatarBucket = 'avatars';
  static const String _featuredPhotosBucket = 'vault_photos';
  static const String _memoryPhotosBucket = 'memory_photos';
  static const String _voiceBucket = 'vault_voice';
  static const String _memoryVoiceBucket = 'memory_voice';
  static const String _aboutPhotosBucket = 'vault_photos';
  String _aboutPrefix(String ownerId) => '$ownerId/${widget.vaultId}/about_me';
  int get _aboutCount => _aboutPhotos.length >= 3 ? 3 : _aboutPhotos.length;

  bool _loadingHighlights = true;
  String? _highlightsError;
  List<Map<String, String>> _featuredPhotos = []; // {path,url}

  final PageController _highlightController = PageController();
  Timer? _autoSlideTimer;
  int _highlightIndex = 0;

  bool _loadingCoreVoice = true;
  String? _coreVoiceError;
  _VoiceNote? _coreVoice;

  bool _loadingMemoryPhotos = true;
  String? _memoryPhotoError;
  final Map<String, List<_MemPhoto>> _memoryPhotosById = {};

  bool _loadingMemoryVoice = true;
  String? _memoryVoiceError;
  final Map<String, List<_VoiceNote>> _memoryVoiceById = {};

  // Debug: surfaces Storage/RLS failures
  String? _storageErrorHint;

  final AudioPlayer _player = AudioPlayer();
  String? _playingKey;
  bool _isPlaying = false;

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

    _loadAll();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _highlightController.dispose();
    _aboutController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    try {
      final signed = await _client.storage.from(bucket).createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      // NOTE: Storage policies/RLS failures show up here.
      // Keep it lightweight but leave a breadcrumb for debugging.
      _storageErrorHint = 'Signed URL failed for bucket="$bucket" path="$path" → $e';
      return null;
    }
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed = await _client.storage.from(_avatarBucket).createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      _storageErrorHint = 'Signed avatar URL failed for path="$path" → $e';
      return null;
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final meta = await _client
          .from('vaults')
          .select('owner_id, avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      final ownerId = (meta?['owner_id'] as String?)?.trim();
      final path = (meta?['avatar_path'] as String?)?.trim();
      final dn = (meta?['display_name'] as String?) ?? (meta?['name'] as String?) ?? _vaultName;

      String? signed;
      if (path != null && path.isNotEmpty) {
        signed = await _signedAvatarUrl(path);
      }

      final data = await _client
          .from('memories')
          .select('id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _ownerId = ownerId;
        _avatarUrl = signed;
        _displayName = (dn ?? _vaultName).toString();
        _memories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });

      unawaited(_loadHighlights());
      unawaited(_loadAboutMeText());
      unawaited(_loadAboutPhotos());
      unawaited(_loadCoreVoice());
      unawaited(_loadMemoryPhotosForVault());
      unawaited(_loadMemoryVoiceForVault());
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

  Future<void> _loadAboutMeText() async {
    if (!mounted) return;
    setState(() {
      _loadingAboutMeText = true;
      _aboutMeTextError = null;
      _aboutMeText = null;
    });

    try {
      final row = await _client
          .from('memories')
          .select('body')
          .eq('vault_id', widget.vaultId)
          .eq('prompt_key', 'about_me')
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _aboutMeText = (row?['body'] ?? '').toString();
        _loadingAboutMeText = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAboutMeText = false;
        _aboutMeTextError = e.toString();
      });
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
        if (url == null || url.trim().isEmpty) {
          _aboutPhotoError ??= 'Storage access blocked. Check Storage SELECT policy for bucket "$_aboutPhotosBucket".';
          continue;
        }
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
  Widget _aboutMeTextPhotosSection() {
    const double previewHeight = 220;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About me', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const SizedBox(height: 10),
          if (_loadingAboutMeText)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_aboutMeTextError != null)
            Text('About me load issue (MVP): $_aboutMeTextError', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                color: Colors.white.withOpacity(0.35),
              ),
              child: Text(
                (_aboutMeText ?? '').trim().isEmpty ? 'No About me text yet.' : (_aboutMeText ?? ''),
                style: TextStyle(color: Colors.black.withOpacity(0.85)),
              ),
            ),

          const SizedBox(height: 14),
          Row(
            children: [
              const Text('About me photos', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                'View only',
                style: TextStyle(fontSize: 12.5, color: Colors.black.withOpacity(0.55)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingAboutPhotos)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_aboutPhotoError != null)
            Text('Photo load issue (MVP): $_aboutPhotoError', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else if (_aboutPhotos.isEmpty)
            Row(
              children: [
                Icon(Icons.photo, color: Colors.black.withOpacity(0.45)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('No About me photos yet.', style: TextStyle(color: Colors.black.withOpacity(0.60))),
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
                                const Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Text('Tap to view all', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dots(_aboutCount, _aboutIndex.clamp(0, (_aboutCount - 1).clamp(0, 99))),
                ],
              ),
            ),
        ],
      ),
    );
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
                          const Text('About me photos', style: TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
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
                                return InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 4,
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                );
                              },
                            ),
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
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.check),
                              label: const Text('Done'),
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

  String _featuredPrefix(String ownerId) => '$ownerId/${widget.vaultId}/featured';

  int get _highlightsCount => _featuredPhotos.length >= 3 ? 3 : _featuredPhotos.length;

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

  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _highlightsError = null;
      _featuredPhotos = [];
    });

    try {
      final ownerId = _ownerId;
      if (ownerId == null || ownerId.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingHighlights = false);
        return;
      }

      final prefix = _featuredPrefix(ownerId);

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
        if (url == null || url.trim().isEmpty) {
          _highlightsError ??= 'Storage access blocked. Check Storage SELECT policy for bucket "$_featuredPhotosBucket".';
          continue;
        }

        items.add({'path': fullPath, 'url': url});
      }

      if (!mounted) return;
      setState(() {
        _featuredPhotos = items;
        _loadingHighlights = false;
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
        _loadingHighlights = false;
        _highlightsError = e.toString();
      });
    }
  }

  // ✅ FIX: overflow + no crop
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
                          const Text('Owner highlights', style: TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
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
                                return InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 4,
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain, // ✅ no crop
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                );
                              },
                            ),
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
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.check),
                              label: const Text('Done'),
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
          width: on ? 14 : 7,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.black.withOpacity(on ? 0.50 : 0.18),
          ),
        );
      }),
    );
  }

  Widget _highlightsSection() {
    const double previewHeight = 264;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
              const Text('Owner highlights', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                'Favourite photos / moments',
                style: TextStyle(fontSize: 12.5, color: Colors.black.withOpacity(0.55)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingHighlights)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_highlightsError != null)
            Text('Highlights load issue (MVP): $_highlightsError', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else if (_featuredPhotos.isEmpty)
            Row(
              children: [
                Icon(Icons.photo, color: Colors.black.withOpacity(0.45)),
                const SizedBox(width: 10),
                Expanded(child: Text('No highlights yet.', style: TextStyle(color: Colors.black.withOpacity(0.60)))),
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
                          onPageChanged: (i) => setState(() => _highlightIndex = i),
                          itemBuilder: (_, i) {
                            final url = _featuredPhotos[i]['url'] ?? '';
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain, // ✅ no crop
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                const Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Text('Tap to view all', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dots(_highlightsCount, _highlightIndex.clamp(0, (_highlightsCount - 1).clamp(0, 99))),
                ],
              ),
            ),
        ],
      ),
    );
  }

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
        setState(() {
          _loadingCoreVoice = false;
          _coreVoiceError ??= 'Storage access blocked. Check Storage SELECT policy for bucket "$_voiceBucket".';
        });
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
        if (url == null || url.trim().isEmpty) {
          _memoryPhotoError ??= 'Storage access blocked. Check Storage SELECT policy for bucket "$_memoryPhotosBucket".';
          return null;
        }

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

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        final title = (r['title'] ?? '').toString().trim();
        final createdAt = (r['created_at'] ?? '').toString();

        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(_memoryVoiceBucket, path);
        if (url == null || url.trim().isEmpty) {
          _memoryVoiceError ??= 'Storage access blocked. Check Storage SELECT policy for bucket "$_memoryVoiceBucket".';
          continue;
        }

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
    } catch (_) {
      // silent
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

  Widget _headerCard() {
    final name = (_displayName ?? _vaultName).trim().isEmpty ? _vaultName : (_displayName ?? _vaultName).trim();
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
                Text('View only', style: TextStyle(fontSize: 12.5, color: Colors.black.withOpacity(0.60))),
                const SizedBox(height: 10),
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
          ),
        ],
      ),
    );
  }

  // ✅ renamed title only
  Widget _aboutMeSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About me', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const SizedBox(height: 8),
          if (_loadingCoreVoice)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_coreVoiceError != null)
            Text('About me load issue (MVP): $_coreVoiceError', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else if (_coreVoice == null)
            Text('No voice yet.', style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else
            Builder(builder: (_) {
              final v = _coreVoice!;
              final key = 'core:${widget.vaultId}';
              final icon = (_playingKey == key && _isPlaying) ? Icons.pause_circle_outline : Icons.play_circle_outline;

              return Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                  color: Colors.white.withOpacity(0.35),
                ),
                child: ListTile(
                  leading: IconButton(
                    icon: Icon(icon),
                    onPressed: () => _togglePlay(v, playKey: key),
                  ),
                  title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================
  // Memory detail (photos + voice)
  // =========================

  void _openMemoryDetail(Map<String, dynamic> m) {
    final memoryId = (m['id'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();
    final body = (m['body'] ?? '').toString();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.88;
        final maxW = MediaQuery.of(ctx).size.width * 0.95;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          prompt.isEmpty ? 'Memory' : prompt,
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
                  Expanded(
                    child: ListView(
                      children: [
                        if (body.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black.withOpacity(0.08)),
                              color: Colors.white.withOpacity(0.35),
                            ),
                            child: Text(body),
                          )
                        else
                          Text('No answer text.', style: TextStyle(color: Colors.black.withOpacity(0.60))),

                        const SizedBox(height: 12),
                        Text('Photos', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.85))),
                        const SizedBox(height: 8),
                        _memoryPhotoStrip(memoryId),

                        const SizedBox(height: 14),
                        Text('Voice notes', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.85))),
                        const SizedBox(height: 8),
                        _memoryVoiceStrip(memoryId, prompt),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ FIX: overflow + no crop
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
                          const Text('Memory photos', style: TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
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
                                return InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 4,
                                  child: Image.network(
                                    p.url,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center,
                                    gaplessPlayback: true,
                                  ),
                                );
                              },
                            ),
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
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.check),
                              label: const Text('Done'),
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
      return Text('Loading photos…', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)));
    }

    if (_memoryPhotoError != null) {
      return Text(
        'Photo load issue (MVP): $_memoryPhotoError',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (photos.isEmpty) {
      return Text('No photos on this memory.', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)));
    }

    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: preview.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = preview[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openMemoryGallery(memoryId),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                p.url,
                width: 92,
                height: 66,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _memoryVoiceStrip(String memoryId, String prompt) {
    final notes = _memoryVoiceById[memoryId] ?? [];
    final preview = notes.take(3).toList();

    if (_loadingMemoryVoice) {
      return Text('Loading voice…', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)));
    }

    if (_memoryVoiceError != null) {
      return Text(
        'Voice load issue (MVP): $_memoryVoiceError',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (notes.isEmpty) {
      return Text('No voice notes on this memory yet.', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)));
    }

    return Column(
      children: preview.map((v) {
        final key = 'mem:${v.id}';
        final icon = (_playingKey == key && _isPlaying) ? Icons.pause_circle_outline : Icons.play_circle_outline;

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
              icon: Icon(icon),
              onPressed: () => _togglePlay(v, playKey: key),
            ),
            title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(v.createdAt.isEmpty ? '' : 'Added: ${v.createdAt}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(_vaultName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
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
                      // Base sections: header, highlights, about text/photos, about voice
                      // Optional: storage debug hint
                      // Then: either 1 empty-state row OR N memory rows
                      itemCount: () {
                        final hasHint = _storageErrorHint != null;
                        final base = 4 + (hasHint ? 1 : 0);
                        final mem = _memories.isEmpty ? 1 : _memories.length;
                        return base + mem;
                      }(),
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final hasHint = _storageErrorHint != null;

                        if (i == 0) return _headerCard();
                        if (i == 1) return _highlightsSection();
                        if (i == 2) return _aboutMeTextPhotosSection();
                        if (i == 3) return _aboutMeSection();

                        // Debug hint (only shows if Storage signed-URL creation failed)
                        if (hasHint && i == 4) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black.withOpacity(0.08)),
                              color: Colors.white.withOpacity(0.35),
                            ),
                            child: Text(
                              _storageErrorHint!,
                              style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.65)),
                            ),
                          );
                        }

                        // Where memory rows begin
                        final memStart = 4 + (hasHint ? 1 : 0);

                        // Empty state
                        if (_memories.isEmpty) {
                          if (i == memStart) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Center(child: Text('No memories yet.')),
                            );
                          }
                          return const SizedBox.shrink();
                        }

                        // Memory row
                        final idx = i - memStart;
                        if (idx < 0 || idx >= _memories.length) {
                          // Safety guard (should never hit)
                          return const SizedBox.shrink();
                        }

                        final m = _memories[idx];
                        final stage = (m['life_stage'] ?? '').toString();
                        final prompt = (m['prompt_text'] ?? '').toString();
                        final body = (m['body'] ?? '').toString();

                        return ListTile(
                          tileColor: tileBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Chip(label: Text(_prettyStage(stage))),
                          title: Text(prompt.isEmpty ? '(No prompt)' : prompt),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to open • photos + voice',
                                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Open memory',
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _openMemoryDetail(m),
                          ),
                          onTap: () => _openMemoryDetail(m),
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