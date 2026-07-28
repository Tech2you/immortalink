// lib/screens/vault_readonly_screen.dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';
import 'family_branch_screen.dart';
import 'vault_companion_screen.dart';

class VaultReadOnlyScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;
  final String? familyId;

  const VaultReadOnlyScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
    this.familyId,
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
  String? _familyId;
  String? _slotKey;
  bool _hiddenFromMyFeed = false;
  bool _updatingFeedPreference = false;

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

  Map<String, dynamic>? _sharedMediaPayload;
  Future<Map<String, dynamic>>? _sharedMediaRequest;

  int _selectedVaultSection = 0;

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

  bool _isMissingStorageObject(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('object not found') ||
        message.contains('statuscode: 404') ||
        message.contains('statuscode=404');
  }

  Future<String?> _signedUrl(
    String bucket,
    String path, {
    void Function(Object error)? onAccessError,
  }) async {
    try {
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      // An old database row can outlive a removed storage object. It should be
      // skipped in a read-only vault, not presented as a technical error.
      if (_isMissingStorageObject(e)) return null;
      _storageErrorHint =
          'Signed URL failed for bucket="$bucket" path="$path" → $e';
      onAccessError?.call(e);
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadSharedMediaPayload() {
    final cached = _sharedMediaPayload;
    if (cached != null) return Future.value(cached);

    final pending = _sharedMediaRequest;
    if (pending != null) return pending;

    final request = () async {
      final result = await _client.rpc(
        'read_shared_vault_media',
        params: {'p_vault_id': widget.vaultId},
      );
      final payload = Map<String, dynamic>.from(result as Map);
      _sharedMediaPayload = payload;
      return payload;
    }();
    _sharedMediaRequest = request;
    return request;
  }

  Future<List<Map<String, dynamic>>> _sharedMediaRows(String key) async {
    final payload = await _loadSharedMediaPayload();
    final raw = payload[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed = await _client.storage
          .from(_avatarBucket)
          .createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      _storageErrorHint = 'Signed avatar URL failed for path="$path" → $e';
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

    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final meta = await _client
          .from('vaults')
          .select('owner_id, family_id, avatar_path, display_name, name')
          .eq('id', widget.vaultId)
          .maybeSingle();

      final ownerId = (meta?['owner_id'] as String?)?.trim();
      final familyId = (widget.familyId ?? meta?['family_id'] as String?)
          ?.trim();
      final path = (meta?['avatar_path'] as String?)?.trim();
      final dn =
          (meta?['display_name'] as String?) ??
          (meta?['name'] as String?) ??
          _vaultName;

      String? signed;
      if (path != null && path.isNotEmpty) {
        signed = await _signedAvatarUrl(path);
      }

      String? slotKey;
      if (ownerId != null &&
          ownerId.isNotEmpty &&
          familyId != null &&
          familyId.isNotEmpty) {
        try {
          final member = await _client
              .from('family_members')
              .select('slot_key')
              .eq('family_id', familyId)
              .eq('user_id', ownerId)
              .maybeSingle();

          slotKey = (member?['slot_key'] as String?)?.trim();
        } catch (_) {}
      }

      var hiddenFromMyFeed = false;
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId != null) {
        try {
          final hiddenRow = await _client
              .from('family_feed_hidden_vaults')
              .select('hidden_vault_id')
              .eq('user_id', currentUserId)
              .eq('hidden_vault_id', widget.vaultId)
              .maybeSingle();
          hiddenFromMyFeed = hiddenRow != null;
        } catch (_) {
          // A feed preference should never prevent the vault from opening.
        }
      }

      final data = await _client
          .from('memories')
          .select(
            'id, life_stage, prompt_key, prompt_text, body, created_at, '
            'memory_date_label, people, location, mood',
          )
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _ownerId = ownerId;
        _familyId = familyId;
        _slotKey = slotKey;
        _hiddenFromMyFeed = hiddenFromMyFeed;
        _avatarUrl = signed;
        _displayName = (dn ?? _vaultName).toString();
        _memories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });

      _sharedMediaPayload = null;
      _sharedMediaRequest = null;

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

  Future<void> _toggleFeedPreference() async {
    if (_updatingFeedPreference) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final name = (_displayName ?? _vaultName).trim();

    if (!_hiddenFromMyFeed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            name.isEmpty ? 'Hide their posts?' : "Hide $name's posts?",
          ),
          content: const Text(
            'Their memories will no longer appear in your Family Feed. '
            'This only changes your feed, they will not be notified, and '
            'you can still visit their vault or undo this at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hide posts'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _updatingFeedPreference = true);
    try {
      if (_hiddenFromMyFeed) {
        await _client
            .from('family_feed_hidden_vaults')
            .delete()
            .eq('user_id', userId)
            .eq('hidden_vault_id', widget.vaultId);
      } else {
        await _client.from('family_feed_hidden_vaults').insert({
          'user_id': userId,
          'hidden_vault_id': widget.vaultId,
        });
      }
      if (!mounted) return;
      setState(() => _hiddenFromMyFeed = !_hiddenFromMyFeed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hiddenFromMyFeed
                ? 'Their posts are now hidden from your feed.'
                : 'Their posts will appear in your feed again.',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update your feed: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your feed. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingFeedPreference = false);
      }
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
      final list = await _sharedMediaRows('about_photos');

      final items = <Map<String, String>>[];
      for (final r in list) {
        final path = (r['path'] ?? '').toString().trim();
        if (path.isEmpty) continue;
        final url = await _signedUrl(
          _aboutPhotosBucket,
          path,
          onAccessError: (_) {
            _aboutPhotoError ??=
                'This photo is not available to this family member.';
          },
        );
        if (url == null || url.trim().isEmpty) {
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_aboutMeTextError != null)
            Text(
              'About me load issue (MVP): $_aboutMeTextError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
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
                (_aboutMeText ?? '').trim().isEmpty
                    ? 'No About me text yet.'
                    : (_aboutMeText ?? ''),
                style: TextStyle(color: Colors.black.withOpacity(0.85)),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'About me photos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                'View only',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.black.withOpacity(0.55),
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
                    'No About me photos yet.',
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

  String _featuredPrefix(String ownerId) =>
      '$ownerId/${widget.vaultId}/featured';

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

  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _highlightsError = null;
      _featuredPhotos = [];
    });

    try {
      final rows = await _sharedMediaRows('highlights');

      final items = <Map<String, String>>[];
      for (final row in rows) {
        final fullPath = (row['path'] ?? '').toString().trim();
        if (fullPath.isEmpty) continue;
        final url = await _signedUrl(
          _featuredPhotosBucket,
          fullPath,
          onAccessError: (_) {
            _highlightsError ??= 'Highlights are temporarily unavailable.';
          },
        );
        if (url == null || url.trim().isEmpty) {
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
                            'Owner highlights',
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
              const Text(
                'Owner highlights',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                'Favourite photos / moments',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingHighlights)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_highlightsError != null)
            Text(
              'Highlights load issue (MVP): $_highlightsError',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else if (_featuredPhotos.isEmpty)
            Row(
              children: [
                Icon(Icons.photo, color: Colors.black.withOpacity(0.45)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No highlights yet.',
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

  Future<void> _loadCoreVoice() async {
    setState(() {
      _loadingCoreVoice = true;
      _coreVoiceError = null;
      _coreVoice = null;
    });

    try {
      final rows = await _sharedMediaRows('core_voice');
      final row = rows.isEmpty ? null : rows.first;

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

      final url = await _signedUrl(
        _voiceBucket,
        path,
        onAccessError: (_) {
          _coreVoiceError ??= 'This voice introduction is unavailable.';
        },
      );
      if (url == null || url.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingCoreVoice = false;
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

      final list = await _sharedMediaRows('memory_photos');

      final futures = list.map((r) async {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) return null;

        final url = await _signedUrl(
          _memoryPhotosBucket,
          path,
          onAccessError: (_) {
            _memoryPhotoError ??= 'Some memory photos are unavailable.';
          },
        );
        if (url == null || url.trim().isEmpty) {
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

      final list = await _sharedMediaRows('memory_voice');

      for (final r in list) {
        final id = (r['id'] ?? '').toString();
        final memoryId = (r['memory_id'] ?? '').toString();
        final path = (r['path'] ?? '').toString().trim();
        final title = (r['title'] ?? '').toString().trim();
        final createdAt = (r['created_at'] ?? '').toString();

        if (id.isEmpty || memoryId.isEmpty || path.isEmpty) continue;

        final url = await _signedUrl(
          _memoryVoiceBucket,
          path,
          onAccessError: (_) {
            _memoryVoiceError ??= 'Some voice notes are unavailable.';
          },
        );
        if (url == null || url.trim().isEmpty) {
          continue;
        }

        _memoryVoiceById
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
    } catch (_) {}
  }

  void _openAskAI() {
    final name = (_displayName ?? _vaultName).trim().isEmpty
        ? 'Vault'
        : (_displayName ?? _vaultName).trim();

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
    final name = (_displayName ?? _vaultName).trim().isEmpty
        ? _vaultName
        : (_displayName ?? _vaultName).trim();
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;
    final slotKey = (_slotKey ?? '').trim();
    final canOpenBranch = _branchDirectionForSlot(slotKey) != null;

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
                ? Icon(
                    Icons.person,
                    color: Colors.black.withOpacity(0.45),
                    size: 28,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'View only',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withOpacity(0.60),
                  ),
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
                    if (canOpenBranch)
                      SizedBox(
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: _openBranch,
                          icon: const Icon(
                            Icons.account_tree_outlined,
                            size: 18,
                          ),
                          label: const Text('Open branch'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              'No voice yet.',
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
          else
            Builder(
              builder: (_) {
                final v = _coreVoice!;
                final key = 'core:${widget.vaultId}';
                final icon = (_playingKey == key && _isPlaying)
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline;

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
                    title: Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

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
                              border: Border.all(
                                color: Colors.black.withOpacity(0.08),
                              ),
                              color: Colors.white.withOpacity(0.35),
                            ),
                            child: Text(body),
                          )
                        else
                          Text(
                            'No answer text.',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.60),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          'Photos',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _memoryPhotoStrip(memoryId),
                        const SizedBox(height: 14),
                        Text(
                          'Voice notes',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withOpacity(0.85),
                          ),
                        ),
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

  Widget _memoryPhotoStrip(String memoryId) {
    final photos = _memoryPhotosById[memoryId] ?? [];
    final preview = photos.take(4).toList();

    if (_loadingMemoryPhotos) {
      return Text(
        'Loading photos…',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (_memoryPhotoError != null) {
      return Text(
        'Photo load issue (MVP): $_memoryPhotoError',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (photos.isEmpty) {
      return Text(
        'No photos on this memory.',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
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
      return Text(
        'Loading voice…',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (_memoryVoiceError != null) {
      return Text(
        'Voice load issue (MVP): $_memoryVoiceError',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    if (notes.isEmpty) {
      return Text(
        'No voice notes on this memory yet.',
        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
      );
    }

    return Column(
      children: preview.map((v) {
        final key = 'mem:${v.id}';
        final icon = (_playingKey == key && _isPlaying)
            ? Icons.pause_circle_outline
            : Icons.play_circle_outline;

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
            subtitle: Text(
              v.createdAt.isEmpty ? '' : 'Added: ${v.createdAt}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _readOnlyProfileHeader() {
    final name = (_displayName ?? _vaultName).trim();
    final hasAvatar = (_avatarUrl ?? '').trim().isNotEmpty;
    final canOpenBranch =
        _branchDirectionForSlot((_slotKey ?? '').trim()) != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.78),
            const Color(0xFFF4E8F7).withOpacity(0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFFE9D7F1),
            backgroundImage: hasAvatar ? NetworkImage(_avatarUrl!) : null,
            child: hasAvatar
                ? null
                : const Icon(Icons.person_outline, size: 42),
          ),
          const SizedBox(height: 14),
          Text(
            name.isEmpty ? 'Family vault' : name,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Stories, voice and moments — shared with family.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black.withOpacity(0.56)),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _openAskAI,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Ask my AI'),
              ),
              if (canOpenBranch)
                OutlinedButton.icon(
                  onPressed: _openBranch,
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Open branch'),
                ),
              OutlinedButton.icon(
                onPressed: _updatingFeedPreference
                    ? null
                    : _toggleFeedPreference,
                icon: _updatingFeedPreference
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _hiddenFromMyFeed
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                label: Text(
                  _hiddenFromMyFeed ? 'Show in my feed' : 'Hide from my feed',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: const Text('View only'),
                backgroundColor: Colors.white.withOpacity(0.52),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialHighlightsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.48),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Highlights',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (_loadingHighlights)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_featuredPhotos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.42),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _highlightsError == null
                    ? 'No highlights shared yet.'
                    : 'Highlights are temporarily unavailable.',
                style: TextStyle(color: Colors.black.withOpacity(0.58)),
              ),
            )
          else
            SizedBox(
              height: 152,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _featuredPhotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, index) {
                  final photo = _featuredPhotos[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openHighlightsGallery,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        photo['url'] ?? '',
                        width: 118,
                        height: 152,
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

  Widget _vaultSectionPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      width: double.infinity,
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

  Widget _detailChip(IconData icon, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(value),
    );
  }

  Widget _socialMemoryCard(Map<String, dynamic> memory) {
    final memoryId = (memory['id'] ?? '').toString();
    final prompt = (memory['prompt_text'] ?? '').toString().trim();
    final body = (memory['body'] ?? '').toString().trim();
    final when = (memory['memory_date_label'] ?? '').toString().trim();
    final people = (memory['people'] ?? '').toString().trim();
    final location = (memory['location'] ?? '').toString().trim();
    final photos = _memoryPhotosById[memoryId] ?? const <_MemPhoto>[];
    final notes = _memoryVoiceById[memoryId] ?? const <_VoiceNote>[];
    final name = (_displayName ?? _vaultName).trim();
    final hasAvatar = (_avatarUrl ?? '').trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white.withOpacity(0.74),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openMemoryDetail(memory),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: hasAvatar
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    child: hasAvatar ? null : const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Family vault' : name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Memory · Shared with family',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
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
              if (prompt.isNotEmpty && body.isNotEmpty)
                const SizedBox(height: 7),
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
                      _detailChip(Icons.calendar_today_outlined, when),
                    if (people.isNotEmpty)
                      _detailChip(Icons.people_outline, people),
                    if (location.isNotEmpty)
                      _detailChip(Icons.location_on_outlined, location),
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
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        photos[index].url,
                        width: photos.length == 1 ? 520 : 260,
                        height: 230,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...notes.map((note) {
                  final key = 'mem:${note.id}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconButton(
                      icon: Icon(
                        _playingKey == key && _isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                      onPressed: () => _togglePlay(note, playKey: key),
                    ),
                    title: Text(note.title),
                    subtitle: const Text('Voice memory'),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _readOnlyAboutSection() {
    final aboutText = (_aboutMeText ?? '').trim();
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.58),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'About me',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (_loadingAboutMeText)
                const LinearProgressIndicator()
              else
                Text(
                  aboutText.isEmpty
                      ? 'Nothing has been shared here yet.'
                      : aboutText,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              if (_aboutPhotos.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _aboutPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) => InkWell(
                      onTap: _openAboutGallery,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          _aboutPhotos[index]['url'] ?? '',
                          width: 180,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.58),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voice introduction',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (_loadingCoreVoice)
                const LinearProgressIndicator()
              else if (_coreVoice == null)
                const Text('No voice introduction has been shared yet.')
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: IconButton(
                    icon: Icon(
                      _playingKey == 'core:${widget.vaultId}' && _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                    ),
                    onPressed: () => _togglePlay(
                      _coreVoice!,
                      playKey: 'core:${widget.vaultId}',
                    ),
                  ),
                  title: Text(_coreVoice!.title),
                  subtitle: const Text('Tap to listen'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _readOnlyMediaSection() {
    final photos = <Map<String, String>>[
      ..._featuredPhotos,
      ..._aboutPhotos,
      for (final group in _memoryPhotosById.values)
        for (final photo in group) {'path': photo.path, 'url': photo.url},
    ];
    final seen = <String>{};
    final uniquePhotos = photos.where((photo) {
      final path = photo['path'] ?? '';
      return path.isNotEmpty && seen.add(path);
    }).toList();
    final voices = <_VoiceNote>[
      if (_coreVoice != null) _coreVoice!,
      for (final group in _memoryVoiceById.values) ...group,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.52),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shared media',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (uniquePhotos.isEmpty)
            const Text('No photos have been shared yet.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: uniquePhotos.length,
              itemBuilder: (_, index) => ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  uniquePhotos[index]['url'] ?? '',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (voices.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Voice notes',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            ...voices.map((voice) {
              final key = voice == _coreVoice
                  ? 'core:${widget.vaultId}'
                  : 'mem:${voice.id}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconButton(
                  icon: Icon(
                    _playingKey == key && _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                  ),
                  onPressed: () => _togglePlay(voice, playKey: key),
                ),
                title: Text(voice.title),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((_displayName ?? _vaultName).trim()),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('This vault could not be loaded: $_error'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
                    children: [
                      _readOnlyProfileHeader(),
                      _socialHighlightsSection(),
                      _vaultSectionPicker(),
                      if (_selectedVaultSection == 0) ...[
                        if (_memories
                            .where(
                              (memory) =>
                                  (memory['prompt_key'] ?? '').toString() !=
                                  'about_me',
                            )
                            .isEmpty)
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.auto_stories_outlined, size: 42),
                                SizedBox(height: 12),
                                Text(
                                  'No memories shared yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._memories
                              .where(
                                (memory) =>
                                    (memory['prompt_key'] ?? '').toString() !=
                                    'about_me',
                              )
                              .map(_socialMemoryCard),
                      ],
                      if (_selectedVaultSection == 1) _readOnlyAboutSection(),
                      if (_selectedVaultSection == 2) _readOnlyMediaSection(),
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
