import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'relationship_tree_screen.dart';
import 'join_family_screen.dart';

class VaultsScreen extends StatefulWidget {
  const VaultsScreen({super.key});

  @override
  State<VaultsScreen> createState() => _VaultsScreenState();
}

class _VaultsScreenState extends State<VaultsScreen> {
  void _openJoinFamilyScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const JoinFamilyScreen()),
    ).then((_) => _loadVault());
  }

  final _supabase = Supabase.instance.client;
  final AudioPlayer _player = AudioPlayer();

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _vault;
  String? _vaultAvatarUrl;

  bool _loadingFeed = false;
  String? _feedError;
  List<_FeedItem> _familyFeed = [];

  final Map<String, String?> _avatarUrlCache = {};
  final Map<String, List<_MemPhoto>> _feedPhotosByMemoryId = {};
  final Map<String, List<_VoiceNote>> _feedVoiceByMemoryId = {};

  String? _playingKey;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

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

    _loadVault();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be signed out of ImmortaLink.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      setState(() {
        _vault = null;
        _vaultAvatarUrl = null;
        _error = null;
        _familyFeed = [];
        _feedError = null;
      });
    } catch (e) {
      _toast('Sign out failed: $e');
    }
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

  Future<String?> _signedAvatarUrl(String path) async {
    return _signedUrl('avatars', path);
  }

  String _formatCreatedAt(dynamic rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty) return 'Created recently';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'Created recently';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final local = parsed.toLocal();
    final month = months[local.month - 1];
    return 'Created on ${local.day} $month ${local.year}';
  }

  String _timeAgo(dynamic rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';

    final now = DateTime.now();
    final diff = now.difference(parsed.toLocal());

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return _formatCreatedAt(raw).replaceFirst('Created on ', '');
  }

  String _feedSubtitle(_FeedItem item) {
    if (item.photoCount > 0 && item.voiceCount > 0) {
      return 'shared a memory';
    }
    if (item.photoCount > 0) {
      return item.body.trim().isNotEmpty ? 'added a memory' : 'shared photos';
    }
    if (item.voiceCount > 0) {
      return item.body.trim().isNotEmpty
          ? 'added a memory'
          : 'added a voice note';
    }
    return 'added a memory';
  }

  Future<void> _loadVault() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _vault = null;
          _vaultAvatarUrl = null;
          _familyFeed = [];
        });
        return;
      }

      final data = await _supabase
          .from('vaults')
          .select('id, name, created_at, family_id, avatar_path')
          .eq('owner_id', user.id)
          .order('created_at', ascending: false)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));

      String? signedUrl;
      final path = (data?['avatar_path'] as String?)?.trim();
      if (path != null && path.isNotEmpty) {
        signedUrl = await _signedAvatarUrl(
          path,
        ).timeout(const Duration(seconds: 12));
      }

      if (!mounted) return;
      setState(() {
        _vault = data;
        _vaultAvatarUrl = signedUrl;
      });

      await _loadFamilyFeed();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error =
            'Timed out loading vault. Check internet / Supabase URL/keys / blocked requests.';
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Postgrest: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadFamilyFeed() async {
    final familyId = (_vault?['family_id'] as String?)?.trim();

    if (familyId == null || familyId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _familyFeed = [];
        _feedError = null;
        _loadingFeed = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loadingFeed = true;
      _feedError = null;
      _familyFeed = [];
      _avatarUrlCache.clear();
      _feedPhotosByMemoryId.clear();
      _feedVoiceByMemoryId.clear();
    });

    try {
      final vaultRows = await _supabase
          .from('vaults')
          .select('id, name, display_name, avatar_path')
          .eq('family_id', familyId)
          .timeout(const Duration(seconds: 12));
      final currentVaultId = (_vault?['id'] ?? '').toString();
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 30));

      final vaultList = List<Map<String, dynamic>>.from(vaultRows);
      if (vaultList.isEmpty) {
        if (!mounted) return;
        setState(() {
          _familyFeed = [];
          _loadingFeed = false;
        });
        return;
      }

      final vaultMap = <String, Map<String, dynamic>>{};
      final vaultIds = <String>[];

      for (final v in vaultList) {
        final id = (v['id'] ?? '').toString();
        if (id.isEmpty || id == currentVaultId) continue;
        vaultMap[id] = v;
        vaultIds.add(id);

        final avatarPath = (v['avatar_path'] ?? '').toString().trim();
        if (avatarPath.isNotEmpty) {
          _avatarUrlCache[id] = await _signedAvatarUrl(avatarPath);
        } else {
          _avatarUrlCache[id] = null;
        }
      }

      if (vaultIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _familyFeed = [];
          _loadingFeed = false;
        });
        return;
      }

      final memoryRows = await _supabase
          .from('memories')
          .select(
            'id, vault_id, life_stage, prompt_text, prompt_key, body, created_at',
          )
          .inFilter('vault_id', vaultIds)
          .neq('prompt_key', 'about_me')
          .order('created_at', ascending: false)
          .limit(12)
          .timeout(const Duration(seconds: 12));

      final allMemories = List<Map<String, dynamic>>.from(memoryRows);
      final memories = allMemories.where((m) {
        final createdRaw = (m['created_at'] ?? '').toString().trim();
        final created = DateTime.tryParse(createdRaw)?.toLocal();
        if (created == null) return false;
        return !created.isBefore(cutoff);
      }).toList();
      final memoryIds = memories
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (memoryIds.isNotEmpty) {
        final photoRows = await _supabase
            .from('memory_photos')
            .select('id, memory_id, path, created_at')
            .inFilter('memory_id', memoryIds)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 12));

        for (final row in List<Map<String, dynamic>>.from(photoRows)) {
          final id = (row['id'] ?? '').toString();
          final memoryId = (row['memory_id'] ?? '').toString();
          final path = (row['path'] ?? '').toString().trim();
          if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

          final url = await _signedUrl('memory_photos', path);
          if (url == null || url.trim().isEmpty) continue;

          _feedPhotosByMemoryId
              .putIfAbsent(memoryId, () => [])
              .add(_MemPhoto(id: id, memoryId: memoryId, path: path, url: url));
        }

        final voiceRows = await _supabase
            .from('memory_voice_notes')
            .select('id, memory_id, path, title, created_at')
            .inFilter('memory_id', memoryIds)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 12));

        for (final row in List<Map<String, dynamic>>.from(voiceRows)) {
          final id = (row['id'] ?? '').toString();
          final memoryId = (row['memory_id'] ?? '').toString();
          final path = (row['path'] ?? '').toString().trim();
          final title = (row['title'] ?? '').toString().trim();
          final createdAt = (row['created_at'] ?? '').toString();

          if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

          final url = await _signedUrl('memory_voice', path);
          if (url == null || url.trim().isEmpty) continue;

          _feedVoiceByMemoryId
              .putIfAbsent(memoryId, () => [])
              .add(
                _VoiceNote(
                  id: id,
                  path: path,
                  title: title.isEmpty ? 'Voice note' : title,
                  url: url,
                  createdAt: createdAt,
                ),
              );
        }
      }

      final items = <_FeedItem>[];
      for (final m in memories) {
        final vaultId = (m['vault_id'] ?? '').toString();
        final memoryId = (m['id'] ?? '').toString();
        final vaultMeta = vaultMap[vaultId];

        if (vaultId.isEmpty || memoryId.isEmpty || vaultMeta == null) continue;

        final displayName =
            ((vaultMeta['display_name'] ?? '').toString().trim().isNotEmpty)
            ? (vaultMeta['display_name'] ?? '').toString().trim()
            : (vaultMeta['name'] ?? 'Family member').toString();

        final photos = _feedPhotosByMemoryId[memoryId] ?? const <_MemPhoto>[];
        final voices = _feedVoiceByMemoryId[memoryId] ?? const <_VoiceNote>[];

        items.add(
          _FeedItem(
            memory: m,
            vaultId: vaultId,
            vaultName: (vaultMeta['name'] ?? '').toString(),
            displayName: displayName,
            avatarUrl: _avatarUrlCache[vaultId],
            photos: photos,
            voiceNotes: voices,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _familyFeed = items;
        _loadingFeed = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedError = e.message;
        _loadingFeed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedError = e.toString();
        _loadingFeed = false;
      });
    }
  }

  void _openVaultHome() {
    if (_vault == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          vaultId: (_vault!['id'] ?? '').toString(),
          vaultName: (_vault!['name'] ?? '').toString(),
        ),
      ),
    ).then((_) => _loadVault());
  }

  Future<void> _renameVault(String vaultId, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Vault name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty) return;

    try {
      await _supabase
          .from('vaults')
          .update({'name': newName})
          .eq('id', vaultId)
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault renamed.');
    } on TimeoutException {
      _toast('Rename timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Rename failed: ${e.message}');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _deleteVault(String vaultId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vault?'),
        content: const Text(
          'This will permanently delete the vault and its memories.',
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

    try {
      await _supabase
          .from('vaults')
          .delete()
          .eq('id', vaultId)
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault deleted.');
    } on TimeoutException {
      _toast('Delete timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _createVault() async {
    final controller = TextEditingController(text: 'My Vault');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create your vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Vault name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      await _supabase
          .from('vaults')
          .insert({'name': name})
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault created.');
    } on TimeoutException {
      _toast('Create timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Create failed: ${e.message}');
    } catch (e) {
      _toast('Create failed: $e');
    }
  }

  Future<void> _ensureFamilyAndOpenTree() async {
    final familyId = (_vault?['family_id'] as String?)?.trim();
    if (familyId != null && familyId.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RelationshipTreeScreen(familyId: familyId),
        ),
      );
      return;
    }

    final controller = TextEditingController(text: 'My Family');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite your family'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create your family group first. Next we’ll do slot invites.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Family name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (_vault == null) return;

    final familyName = controller.text.trim().isEmpty
        ? 'My Family'
        : controller.text.trim();

    try {
      final newFamilyId = await _supabase
          .rpc(
            'create_family_group_and_link_vault',
            params: {'p_family_name': familyName},
          )
          .timeout(const Duration(seconds: 12));

      final newFamilyIdStr = (newFamilyId ?? '').toString();
      if (newFamilyIdStr.isEmpty) {
        throw Exception('Failed to create family id');
      }

      await _loadVault();

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RelationshipTreeScreen(familyId: newFamilyIdStr),
        ),
      );
    } on TimeoutException {
      _toast('Family setup timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Family setup failed: ${e.message}');
    } catch (e) {
      _toast('Family setup failed: $e');
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
      _toast('Playback failed.');
    }
  }

  void _openFeedMemory(_FeedItem item) {
    final memoryId = item.memoryId;
    final prompt = item.promptText;
    final body = item.body;
    final photos = item.photos;
    final notes = item.voiceNotes;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.black.withOpacity(0.06),
                        backgroundImage: item.hasAvatar
                            ? NetworkImage(item.avatarUrl!)
                            : null,
                        child: !item.hasAvatar
                            ? Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.black.withOpacity(0.55),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _timeAgo(item.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.08),
                            ),
                            color: Colors.white.withOpacity(0.58),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prompt.isEmpty ? 'Memory' : prompt,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (body.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(body),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Photos',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (photos.isEmpty)
                          Text(
                            'No photos on this memory.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withOpacity(0.55),
                            ),
                          )
                        else
                          SizedBox(
                            height: 80,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: photos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) {
                                final p = photos[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _openPhotoGallery(photos, i),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      p.url,
                                      width: 110,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          'Voice notes',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (notes.isEmpty)
                          Text(
                            'No voice notes on this memory yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withOpacity(0.55),
                            ),
                          )
                        else
                          Column(
                            children: notes.map((v) {
                              final key = 'feed:$memoryId:${v.id}';
                              return StreamBuilder<PlayerState>(
                                stream: _player.onPlayerStateChanged,
                                builder: (context, snapshot) {
                                  final isThisPlaying =
                                      _playingKey == key && _isPlaying;
                                  final icon = isThisPlaying
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.black.withOpacity(0.08),
                                      ),
                                      color: Colors.white.withOpacity(0.52),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      onTap: () => _togglePlay(v, playKey: key),
                                      leading: IconButton(
                                        icon: Icon(icon),
                                        onPressed: () =>
                                            _togglePlay(v, playKey: key),
                                      ),
                                      title: Text(
                                        v.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        v.createdAt.isEmpty
                                            ? ''
                                            : _timeAgo(v.createdAt),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
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

  void _openPhotoGallery(List<_MemPhoto> photos, int initialIndex) {
    if (photos.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final pc = PageController(initialPage: initialIndex);
        int idx = initialIndex;

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

  Widget _buildFeedSection(bool inFamily) {
    if (!inFamily) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          color: Colors.white.withOpacity(0.18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Family Feed',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Recent memories from your family will appear here once you join or create a family.',
              style: TextStyle(color: Colors.black.withOpacity(0.62)),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Family Feed',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Recent memories from your family',
            style: TextStyle(color: Colors.black.withOpacity(0.62)),
          ),
          const SizedBox(height: 14),
          if (_loadingFeed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_feedError != null)
            Text(
              'Family feed load failed: $_feedError',
              style: TextStyle(color: Colors.black.withOpacity(0.62)),
            )
          else if (_familyFeed.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                color: Colors.white.withOpacity(0.36),
              ),
              child: Text(
                'No family memories yet.',
                style: TextStyle(color: Colors.black.withOpacity(0.62)),
              ),
            )
          else
            Column(
              children: List.generate(_familyFeed.length, (i) {
                final item = _familyFeed[i];
                final previewPhoto = item.photos.isNotEmpty
                    ? item.photos.first
                    : null;
                final showBody = item.body.trim().isNotEmpty;

                return Container(
                  margin: EdgeInsets.only(
                    bottom: i == _familyFeed.length - 1 ? 0 : 12,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openFeedMemory(item),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.08),
                        ),
                        color: Colors.white.withOpacity(0.42),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 19,
                                backgroundColor: Colors.black.withOpacity(0.06),
                                backgroundImage: item.hasAvatar
                                    ? NetworkImage(item.avatarUrl!)
                                    : null,
                                child: !item.hasAvatar
                                    ? Icon(
                                        Icons.person,
                                        size: 18,
                                        color: Colors.black.withOpacity(0.55),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_feedSubtitle(item)}  •  ${_timeAgo(item.createdAt)}',
                                      style: TextStyle(
                                        color: Colors.black.withOpacity(0.58),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _typeChip(item),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (previewPhoto != null || showBody)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (previewPhoto != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      previewPhoto.url,
                                      width: 96,
                                      height: 76,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                if (previewPhoto != null && showBody)
                                  const SizedBox(width: 12),
                                if (showBody)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.promptText.isEmpty
                                              ? 'Memory'
                                              : item.promptText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.body,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.black.withOpacity(
                                              0.72,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            )
                          else
                            Text(
                              item.promptText.isEmpty
                                  ? 'Tap to open memory'
                                  : item.promptText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (item.photoCount > 0)
                                _metaBadge(
                                  Icons.photo_library_outlined,
                                  '${item.photoCount} photo${item.photoCount == 1 ? '' : 's'}',
                                ),
                              if (item.voiceCount > 0)
                                _metaBadge(
                                  Icons.mic_none,
                                  '${item.voiceCount} voice',
                                ),
                              _metaBadge(Icons.chevron_right, 'Tap to open'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _typeChip(_FeedItem item) {
    String label = 'Memory';
    if (item.photoCount > 0 &&
        item.voiceCount == 0 &&
        item.body.trim().isEmpty) {
      label = 'Photos';
    } else if (item.voiceCount > 0 &&
        item.photoCount == 0 &&
        item.body.trim().isEmpty) {
      label = 'Voice';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFEAE2F3).withOpacity(0.95),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF6E5A93),
        ),
      ),
    );
  }

  Widget _metaBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.52),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.black.withOpacity(0.62)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: Colors.black.withOpacity(0.68))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyId = (_vault?['family_id'] as String?)?.trim();
    final inFamily = familyId != null && familyId.isNotEmpty;

    final hasAvatar =
        _vaultAvatarUrl != null && _vaultAvatarUrl!.trim().isNotEmpty;
    final createdLabel = _formatCreatedAt(_vault?['created_at']);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F0F7),
      appBar: AppBar(
        title: const Text('Your Vault'),
        backgroundColor: const Color(0xFFF7F0F7),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadVault,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Join family',
            onPressed: _openJoinFamilyScreen,
            icon: const Icon(Icons.group_add),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.08,
                  child: Image.asset(
                    'assets/images/immortalink_logo.png',
                    width: 520,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                ? Center(child: Text('Load failed: $_error'))
                : (_vault == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'No vault yet',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _createVault,
                                icon: const Icon(Icons.add),
                                label: const Text('Create your vault'),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _ensureFamilyAndOpenTree,
                                icon: Icon(
                                  inFamily
                                      ? Icons.account_tree
                                      : Icons.group_add,
                                ),
                                label: Text(
                                  inFamily
                                      ? 'View your family tree'
                                      : 'Invite your family',
                                ),
                              ),
                            ),
                            if (!inFamily) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _openJoinFamilyScreen,
                                  icon: const Icon(Icons.vpn_key),
                                  label: const Text('Join with invite code'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Card(
                              color: Colors.white.withOpacity(0.36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Colors.black.withOpacity(0.08),
                                ),
                              ),
                              elevation: 0,
                              child: ListTile(
                                onTap: _openVaultHome,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.black.withOpacity(
                                    0.08,
                                  ),
                                  backgroundImage: hasAvatar
                                      ? NetworkImage(_vaultAvatarUrl!)
                                      : null,
                                  child: !hasAvatar
                                      ? Icon(
                                          Icons.person,
                                          size: 18,
                                          color: Colors.black.withOpacity(0.6),
                                        )
                                      : null,
                                ),
                                title: Text((_vault!['name'] ?? '').toString()),
                                subtitle: Text(createdLabel),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Rename',
                                      onPressed: () => _renameVault(
                                        (_vault!['id'] ?? '').toString(),
                                        (_vault!['name'] ?? '').toString(),
                                      ),
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteVault(
                                        (_vault!['id'] ?? '').toString(),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                    IconButton(
                                      tooltip: 'Open',
                                      onPressed: _openVaultHome,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _buildFeedSection(inFamily),
                          ],
                        )),
          ),
        ],
      ),
    );
  }
}

class _FeedItem {
  final Map<String, dynamic> memory;
  final String vaultId;
  final String vaultName;
  final String displayName;
  final String? avatarUrl;
  final List<_MemPhoto> photos;
  final List<_VoiceNote> voiceNotes;

  const _FeedItem({
    required this.memory,
    required this.vaultId,
    required this.vaultName,
    required this.displayName,
    required this.avatarUrl,
    required this.photos,
    required this.voiceNotes,
  });

  String get memoryId => (memory['id'] ?? '').toString();
  String get promptText => (memory['prompt_text'] ?? '').toString();
  String get body => (memory['body'] ?? '').toString();
  String get createdAt => (memory['created_at'] ?? '').toString();
  int get photoCount => photos.length;
  int get voiceCount => voiceNotes.length;
  bool get hasAvatar => avatarUrl != null && avatarUrl!.trim().isNotEmpty;
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
