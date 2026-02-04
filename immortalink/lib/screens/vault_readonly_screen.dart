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
  String _vaultName = '';

  String? _avatarUrl; // signed url
  String? _displayName;

  // Buckets (same as VaultHomeScreen)
  static const String _avatarBucket = 'avatars';
  static const String _memoryPhotosBucket = 'memory_photos';
  static const String _voiceBucket = 'vault_voice';
  static const String _memoryVoiceBucket = 'memory_voice';

  // Core voice note
  bool _loadingCoreVoice = true;
  String? _coreVoiceError;
  _VoiceNote? _coreVoice;

  // Memory photos
  bool _loadingMemoryPhotos = true;
  String? _memoryPhotoError;
  final Map<String, List<_MemPhoto>> _memoryPhotosById = {};

  // Memory voice notes
  bool _loadingMemoryVoice = true;
  String? _memoryVoiceError;
  final Map<String, List<_VoiceNote>> _memoryVoiceById = {};

  // Playback
  final AudioPlayer _player = AudioPlayer();
  String? _playingKey; // "core:vaultId" or "mem:<voiceId>"
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
    _player.dispose();
    super.dispose();
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

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed = await _client.storage.from(_avatarBucket).createSignedUrl(path, 60 * 60);
      return '$signed&t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Meta
      final meta = await _client
          .from('vaults')
          .select('avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      final path = (meta?['avatar_path'] as String?)?.trim();
      final dn = (meta?['display_name'] as String?) ??
          (meta?['name'] as String?) ??
          _vaultName;

      String? signed;
      if (path != null && path.isNotEmpty) {
        signed = await _signedAvatarUrl(path);
      }

      // Memories (read only)
      final data = await _client
          .from('memories')
          .select('id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _avatarUrl = signed;
        _displayName = (dn ?? _vaultName).toString();
        _memories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });

      // Load extras (don’t block UI)
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
      // silent for MVP
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
                            return Positioned.fill(child: Image.network(p.url, fit: BoxFit.cover));
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
        child: Text('Photo load issue (MVP): $_memoryPhotoError',
            style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
      );
    }

    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('No photos on this memory.', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
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
                child: Image.network(p.url, width: 92, height: 66, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _memoryVoiceStrip(String memoryId) {
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
        child: Text('Voice load issue (MVP): $_memoryVoiceError',
            style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
      );
    }

    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('No voice notes on this memory.', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55))),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: preview.map((v) {
          final key = 'mem:${v.id}';
          final icon = (_playingKey == key && _isPlaying) ? Icons.pause_circle_outline : Icons.play_circle_outline;

          return Container(
            margin: const EdgeInsets.only(top: 8),
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
            ),
          );
        }).toList(),
      ),
    );
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
            child: !hasAvatar
                ? Icon(Icons.person, color: Colors.black.withOpacity(0.45), size: 28)
                : null,
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

  Widget _coreVoiceSection() {
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
          const Text('Core voice note', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_loadingCoreVoice)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_coreVoiceError != null)
            Text('Core voice load issue (MVP): $_coreVoiceError',
                style: TextStyle(color: Colors.black.withOpacity(0.60)))
          else if (_coreVoice == null)
            Text('No core message yet.', style: TextStyle(color: Colors.black.withOpacity(0.60)))
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
                      itemCount: _memories.isEmpty ? 3 : _memories.length + 2,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        if (i == 0) return _headerCard();
                        if (i == 1) return _coreVoiceSection();

                        if (_memories.isEmpty && i == 2) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Center(child: Text('No memories yet.')),
                          );
                        }

                        final m = _memories[i - 2];
                        final memoryId = (m['id'] ?? '').toString();
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
                              Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
                              _memoryPhotoStrip(memoryId),
                              _memoryVoiceStrip(memoryId),
                            ],
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
