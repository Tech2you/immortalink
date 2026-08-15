import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/everroot_upgrade_prompt.dart';
import 'vault_home_screen.dart';
import 'relationship_tree_screen.dart';
import 'join_family_screen.dart';

enum _VaultSettingsAction {
  refresh,
  joinFamily,
  createFamily,
  manageSubscription,
  changePassword,
  deleteAccount,
  signOut,
}

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
  List<Map<String, dynamic>> _familyMemberships = [];
  String? _activeFamilyId;

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

  Map<String, String> _authHeadersOrThrow() {
    final token = _supabase.auth.currentSession?.accessToken.trim();
    if (token == null || token.isEmpty) {
      throw Exception('Missing session. Please sign in again.');
    }
    return {'Authorization': 'Bearer $token', 'authorization': 'Bearer $token'};
  }

  Future<void> _handleSettingsAction(_VaultSettingsAction action) async {
    switch (action) {
      case _VaultSettingsAction.refresh:
        await _loadVault();
        return;
      case _VaultSettingsAction.joinFamily:
        _openJoinFamilyScreen();
        return;
      case _VaultSettingsAction.createFamily:
        await _ensureFamilyAndOpenTree(createAnother: true);
        return;
      case _VaultSettingsAction.manageSubscription:
        await _showSubscriptionSettings();
        return;
      case _VaultSettingsAction.changePassword:
        await _changePassword();
        return;
      case _VaultSettingsAction.deleteAccount:
        await _deleteAccount();
        return;
      case _VaultSettingsAction.signOut:
        await _signOut();
        return;
    }
  }

  Future<void> _showSubscriptionSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscription'),
        content: const Text(
          'Your subscription controls will appear here once billing is connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be signed out of Ever Roots.'),
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
        _familyMemberships = [];
        _activeFamilyId = null;
      });
    } catch (e) {
      _toast('Sign out failed: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DeleteAccountConfirmationDialog(),
    );

    if (password == null) return;
    if (password.trim().isEmpty) {
      _toast('Enter your password to confirm account deletion.');
      return;
    }

    try {
      final email = _supabase.auth.currentUser?.email?.trim();
      if (email == null || email.isEmpty) {
        throw Exception('Missing account email. Please sign in again.');
      }

      await _supabase.auth
          .signInWithPassword(email: email, password: password.trim())
          .timeout(const Duration(seconds: 20));

      final res = await _supabase.functions
          .invoke('delete_account', headers: _authHeadersOrThrow())
          .timeout(const Duration(seconds: 45));

      if (res.status < 200 || res.status >= 300) {
        throw Exception(res.data?.toString() ?? 'Delete account failed.');
      }

      await _supabase.auth.signOut();
      if (!mounted) return;
      setState(() {
        _vault = null;
        _vaultAvatarUrl = null;
        _error = null;
        _familyFeed = [];
        _feedError = null;
        _familyMemberships = [];
        _activeFamilyId = null;
      });
      _toast('Account deleted.');
    } on AuthException {
      _toast('Password confirmation failed.');
    } on TimeoutException {
      _toast('Account deletion timed out. Try again.');
    } catch (e) {
      _toast('Account deletion failed: $e');
    }
  }

  Future<void> _changePassword() async {
    final values = await showDialog<_ChangePasswordValues>(
      context: context,
      builder: (ctx) => const _ChangePasswordDialog(),
    );

    if (values == null) return;

    final currentPassword = values.currentPassword.trim();
    final newPassword = values.newPassword.trim();
    final confirmPassword = values.confirmPassword.trim();

    if (currentPassword.isEmpty) {
      _toast('Enter your current password first.');
      return;
    }
    if (newPassword.length < 8) {
      _toast('Use at least 8 characters for your new password.');
      return;
    }
    if (newPassword != confirmPassword) {
      _toast('The new passwords do not match yet.');
      return;
    }

    try {
      final email = _supabase.auth.currentUser?.email?.trim();
      if (email == null || email.isEmpty) {
        throw Exception('Missing account email. Please sign in again.');
      }

      await _supabase.auth
          .signInWithPassword(email: email, password: currentPassword)
          .timeout(const Duration(seconds: 20));
      await _supabase.auth
          .updateUser(UserAttributes(password: newPassword))
          .timeout(const Duration(seconds: 20));

      _toast('Password changed.');
    } on AuthException {
      _toast('Current password could not be confirmed.');
    } on TimeoutException {
      _toast('Password change timed out. Try again.');
    } catch (e) {
      _toast('Password change failed: $e');
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
          _familyMemberships = [];
          _activeFamilyId = null;
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

      await _cleanupStaleMembershipsForFreshVault(data, user.id);
      await _loadFamilyMemberships(user.id);
      if (!mounted) return;
      setState(() => _loading = false);
      unawaited(_loadFamilyFeed());
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
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cleanupStaleMembershipsForFreshVault(
    Map<String, dynamic>? vault,
    String userId,
  ) async {
    final vaultFamilyId = (vault?['family_id'] ?? '').toString().trim();
    final vaultCreatedAt = DateTime.tryParse(
      (vault?['created_at'] ?? '').toString().trim(),
    )?.toUtc();

    if (vault == null || vaultFamilyId.isNotEmpty || vaultCreatedAt == null) {
      return;
    }

    try {
      final rawRows = await _supabase
          .from('family_members')
          .select('family_id, joined_at')
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));

      final staleFamilyIds = List<Map<String, dynamic>>.from(rawRows)
          .where((row) {
            final familyId = (row['family_id'] ?? '').toString().trim();
            final joinedAt = DateTime.tryParse(
              (row['joined_at'] ?? '').toString().trim(),
            )?.toUtc();
            return familyId.isNotEmpty &&
                joinedAt != null &&
                joinedAt.isBefore(vaultCreatedAt);
          })
          .map((row) => (row['family_id'] ?? '').toString().trim())
          .toSet();

      for (final familyId in staleFamilyIds) {
        await _supabase
            .rpc('leave_family', params: {'p_family_id': familyId})
            .timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      // A failed cleanup should not block loading the user's vault.
    }
  }

  Future<void> _loadFamilyMemberships(String userId) async {
    final rawRows = await _supabase
        .from('family_members')
        .select('family_id, role, joined_at, is_primary')
        .eq('user_id', userId)
        .order('joined_at', ascending: true)
        .timeout(const Duration(seconds: 12));
    final memberships = List<Map<String, dynamic>>.from(rawRows);
    final familyIds = memberships
        .map((row) => (row['family_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toList();

    final namesById = <String, String>{};
    if (familyIds.isNotEmpty) {
      try {
        final rawFamilies = await _supabase
            .from('family_groups')
            .select('id, name')
            .inFilter('id', familyIds)
            .timeout(const Duration(seconds: 12));
        for (final family in List<Map<String, dynamic>>.from(rawFamilies)) {
          final id = (family['id'] ?? '').toString().trim();
          if (id.isNotEmpty) {
            namesById[id] = (family['name'] ?? 'Family').toString().trim();
          }
        }
      } catch (_) {}
    }

    for (final membership in memberships) {
      final id = (membership['family_id'] ?? '').toString().trim();
      membership['family_name'] = namesById[id]?.isNotEmpty == true
          ? namesById[id]
          : 'Family tree';
    }

    String? primaryId;
    for (final row in memberships) {
      final id = (row['family_id'] ?? '').toString().trim();
      if (row['is_primary'] == true && id.isNotEmpty) {
        primaryId = id;
        break;
      }
    }
    final storedPrimary = (_vault?['family_id'] as String?)?.trim();
    // The family feed always follows the user's home family. A tree can still
    // be opened directly without silently changing which family owns the feed.
    final nextActive =
        primaryId ??
        (storedPrimary?.isNotEmpty == true ? storedPrimary : null) ??
        (familyIds.isEmpty ? null : familyIds.first);

    if (!mounted) return;
    setState(() {
      _familyMemberships = memberships;
      _activeFamilyId = nextActive;
    });
  }

  Future<void> _loadFamilyFeed() async {
    final familyId = _activeFamilyId?.trim();

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
      final currentUserId = _supabase.auth.currentUser?.id;
      final hiddenRowsFuture = currentUserId == null
          ? Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[])
          : _supabase
                .from('family_feed_hidden_vaults')
                .select('hidden_vault_id')
                .eq('user_id', currentUserId)
                .timeout(const Duration(seconds: 12))
                .then((rows) => List<Map<String, dynamic>>.from(rows));
      final memberRowsFuture = _supabase
          .from('family_members')
          .select('user_id')
          .eq('family_id', familyId)
          .timeout(const Duration(seconds: 12))
          .then((rows) => List<Map<String, dynamic>>.from(rows));

      final hiddenRows = await hiddenRowsFuture;
      final hiddenVaultIds = hiddenRows
          .map((row) => (row['hidden_vault_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      final memberRows = await memberRowsFuture;
      final memberUserIds = memberRows
          .map((row) => (row['user_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();
      final vaultRows = memberUserIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _supabase
                .from('vaults')
                .select('id, name, display_name, avatar_path, owner_id')
                .inFilter('owner_id', memberUserIds)
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
      final visibleVaults = <Map<String, dynamic>>[];

      for (final v in vaultList) {
        final id = (v['id'] ?? '').toString();
        if (id.isEmpty || id == currentVaultId || hiddenVaultIds.contains(id)) {
          continue;
        }
        vaultMap[id] = v;
        vaultIds.add(id);
        visibleVaults.add(v);
      }

      if (vaultIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _familyFeed = [];
          _loadingFeed = false;
        });
        return;
      }

      final nextAvatarUrlCache = <String, String?>{};
      final avatarEntries = await Future.wait(
        visibleVaults.map((v) async {
          final id = (v['id'] ?? '').toString();
          final avatarPath = (v['avatar_path'] ?? '').toString().trim();
          if (avatarPath.isEmpty) return MapEntry<String, String?>(id, null);
          return MapEntry<String, String?>(
            id,
            await _signedAvatarUrl(avatarPath),
          );
        }),
      );
      for (final entry in avatarEntries) {
        nextAvatarUrlCache[entry.key] = entry.value;
      }

      final memoryRows = await _supabase
          .from('memories')
          .select(
            'id, vault_id, life_stage, prompt_text, prompt_key, body, created_at, share_to_family_feed',
          )
          .inFilter('vault_id', vaultIds)
          .eq('share_to_family_feed', true)
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
        final photoRowsFuture = _supabase
            .from('memory_photos')
            .select('id, memory_id, path, created_at')
            .inFilter('memory_id', memoryIds)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 12));
        final voiceRowsFuture = _supabase
            .from('memory_voice_notes')
            .select('id, memory_id, path, title, created_at')
            .inFilter('memory_id', memoryIds)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 12));

        final photoRows = await photoRowsFuture;
        final photoEntries = await Future.wait(
          List<Map<String, dynamic>>.from(photoRows).map((row) async {
            final id = (row['id'] ?? '').toString();
            final memoryId = (row['memory_id'] ?? '').toString();
            final path = (row['path'] ?? '').toString().trim();
            if (id.isEmpty || memoryId.isEmpty || path.isEmpty) return null;

            final url = await _signedUrl('memory_photos', path);
            if (url == null || url.trim().isEmpty) return null;

            return _MemPhoto(id: id, memoryId: memoryId, path: path, url: url);
          }),
        );
        for (final photo in photoEntries) {
          if (photo == null) continue;
          _feedPhotosByMemoryId
              .putIfAbsent(photo.memoryId, () => [])
              .add(photo);
        }

        final voiceRows = await voiceRowsFuture;
        final voiceEntries = await Future.wait(
          List<Map<String, dynamic>>.from(voiceRows).map((row) async {
            final id = (row['id'] ?? '').toString();
            final memoryId = (row['memory_id'] ?? '').toString();
            final path = (row['path'] ?? '').toString().trim();
            final title = (row['title'] ?? '').toString().trim();
            final createdAt = (row['created_at'] ?? '').toString();

            if (id.isEmpty || memoryId.isEmpty || path.isEmpty) return null;

            final url = await _signedUrl('memory_voice', path);
            if (url == null || url.trim().isEmpty) return null;

            return MapEntry(
              memoryId,
              _VoiceNote(
                id: id,
                path: path,
                title: title.isEmpty ? 'Voice note' : title,
                url: url,
                createdAt: createdAt,
              ),
            );
          }),
        );
        for (final entry in voiceEntries) {
          if (entry == null) continue;
          _feedVoiceByMemoryId
              .putIfAbsent(entry.key, () => [])
              .add(entry.value);
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
            avatarUrl: nextAvatarUrlCache[vaultId],
            photos: photos,
            voiceNotes: voices,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _avatarUrlCache
          ..clear()
          ..addAll(nextAvatarUrlCache);
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
          familyId: _activeFamilyId,
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
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
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
      final userId = _supabase.auth.currentUser?.id;
      final familyIds = _familyMemberships
          .map((row) => (row['family_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      if (userId != null && familyIds.isEmpty) {
        final rawRows = await _supabase
            .from('family_members')
            .select('family_id')
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 12));
        familyIds.addAll(
          List<Map<String, dynamic>>.from(rawRows)
              .map((row) => (row['family_id'] ?? '').toString().trim())
              .where((id) => id.isNotEmpty),
        );
      }

      for (final familyId in familyIds) {
        try {
          await _supabase
              .rpc('leave_family', params: {'p_family_id': familyId})
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          // Deleting the vault should not be blocked by an old family row.
        }
      }

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
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create your vault'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your name as it should display on your family tree.',
            ),
            const SizedBox(height: 6),
            Text(
              'You can edit this later.',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.62)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Example: Frank',
              ),
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not signed in.');

      final staleFamilyIds = <String>{};
      try {
        final rawMemberships = await _supabase
            .from('family_members')
            .select('family_id')
            .eq('user_id', user.id)
            .timeout(const Duration(seconds: 12));
        staleFamilyIds.addAll(
          List<Map<String, dynamic>>.from(rawMemberships)
              .map((row) => (row['family_id'] ?? '').toString().trim())
              .where((id) => id.isNotEmpty),
        );
      } catch (_) {
        // Vault creation should still work if old membership cleanup is stale.
      }

      await _supabase
          .from('vaults')
          .insert({'name': name, 'display_name': name})
          .timeout(const Duration(seconds: 12));

      for (final familyId in staleFamilyIds) {
        try {
          await _supabase
              .rpc('leave_family', params: {'p_family_id': familyId})
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          // Keep creation successful even if a stale old membership is gone.
        }
      }

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

  Future<void> _ensureFamilyAndOpenTree({bool createAnother = false}) async {
    final familyId = _activeFamilyId?.trim();
    if (!createAnother && familyId != null && familyId.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RelationshipTreeScreen(familyId: familyId),
        ),
      );
      return;
    }

    final familyName = await showDialog<String>(
      context: context,
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(viewInsets: EdgeInsets.zero),
        child: _CreateFamilyDialog(
          title: createAnother ? 'Create another family' : 'Invite your family',
        ),
      ),
    );

    if (familyName == null) return;
    if (_vault == null) return;
    final trimmedFamilyName = familyName.trim().isEmpty
        ? 'My Family'
        : familyName.trim();

    try {
      final newFamilyId = await _supabase
          .rpc(
            'create_family_group_and_link_vault',
            params: {'p_family_name': trimmedFamilyName},
          )
          .timeout(const Duration(seconds: 12));

      final newFamilyIdStr = (newFamilyId ?? '').toString();
      if (newFamilyIdStr.isEmpty) {
        throw Exception('Failed to create family id');
      }

      await _supabase.rpc(
        'set_primary_family',
        params: {'p_family_id': newFamilyIdStr},
      );

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
      if (isEverRootFamilyUpgradeError(e)) {
        if (!mounted) return;
        await showEverRootFamilyUpgradePrompt(context, message: e.message);
        return;
      }
      _toast('Family setup failed: ${e.message}');
    } catch (e) {
      if (isEverRootFamilyUpgradeError(e)) {
        if (!mounted) return;
        await showEverRootFamilyUpgradePrompt(context);
        return;
      }
      _toast('Family setup failed: $e');
    }
  }

  void _openFamilyTree(String familyId) {
    setState(() => _activeFamilyId = familyId);
    _loadFamilyFeed();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelationshipTreeScreen(familyId: familyId),
      ),
    ).then((_) => _loadVault());
  }

  Future<void> _makePrimaryFamily(String familyId) async {
    try {
      await _supabase.rpc(
        'set_primary_family',
        params: {'p_family_id': familyId},
      );
      await _loadVault();
      _toast('Home family updated.');
    } on PostgrestException catch (e) {
      _toast('Could not update home family: ${e.message}');
    } catch (e) {
      _toast('Could not update home family: $e');
    }
  }

  Widget _familyTreesCard() {
    if (_familyMemberships.isEmpty) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _ensureFamilyAndOpenTree(),
              icon: const Icon(Icons.group_add),
              label: const Text('Create your family tree'),
            ),
          ),
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
      );
    }

    return Card(
      color: Colors.white.withOpacity(0.36),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your family trees',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                PopupMenuButton<_VaultSettingsAction>(
                  tooltip: 'Family tree actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: _handleSettingsAction,
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: _VaultSettingsAction.joinFamily,
                      child: ListTile(
                        leading: Icon(Icons.group_add),
                        title: Text('Join another family'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _VaultSettingsAction.createFamily,
                      child: ListTile(
                        leading: Icon(Icons.add_circle_outline),
                        title: Text('Create another family'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'You can join more than one. Your home family opens by default.',
              style: TextStyle(color: Colors.black.withOpacity(0.62)),
            ),
            const SizedBox(height: 8),
            ..._familyMemberships.map((membership) {
              final id = (membership['family_id'] ?? '').toString();
              final name = (membership['family_name'] ?? 'Family tree')
                  .toString();
              final isPrimary = membership['is_primary'] == true;
              final isActive = id == _activeFamilyId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: isActive
                      ? const Color(0xFFE6D7EF)
                      : Colors.black.withOpacity(0.06),
                  child: const Icon(Icons.account_tree),
                ),
                title: Text(name),
                subtitle: Text(isPrimary ? 'Home family' : 'Family member'),
                onTap: () => _openFamilyTree(id),
                trailing: isPrimary
                    ? const Icon(Icons.home, color: Color(0xFF6E5A93))
                    : TextButton(
                        onPressed: () => _makePrimaryFamily(id),
                        child: const Text('Make home'),
                      ),
              );
            }),
          ],
        ),
      ),
    );
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
                                    child: _memoryPhotoImage(
                                      p.url,
                                      width: 110,
                                      height: 80,
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
                                    child: _memoryPhotoImage(
                                      previewPhoto.url,
                                      width: 96,
                                      height: 76,
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
          PopupMenuButton<_VaultSettingsAction>(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onSelected: _handleSettingsAction,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: _VaultSettingsAction.refresh,
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh'),
                ),
              ),
              PopupMenuItem(
                value: _VaultSettingsAction.joinFamily,
                child: ListTile(
                  leading: Icon(Icons.group_add),
                  title: Text('Join family'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _VaultSettingsAction.manageSubscription,
                child: ListTile(
                  leading: Icon(Icons.credit_card_outlined),
                  title: Text('Subscription'),
                  subtitle: Text('Manage or cancel'),
                ),
              ),
              PopupMenuItem(
                value: _VaultSettingsAction.changePassword,
                child: ListTile(
                  leading: Icon(Icons.lock_reset),
                  title: Text('Change password'),
                  subtitle: Text('Confirm current password'),
                ),
              ),
              PopupMenuItem(
                value: _VaultSettingsAction.deleteAccount,
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined),
                  title: Text('Delete account'),
                  subtitle: Text('Permanent'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _VaultSettingsAction.signOut,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
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
                            _familyTreesCard(),
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
                            _buildFeedSection(_familyMemberships.isNotEmpty),
                          ],
                        )),
          ),
        ],
      ),
    );
  }
}

class _CreateFamilyDialog extends StatefulWidget {
  final String title;

  const _CreateFamilyDialog({required this.title});

  @override
  State<_CreateFamilyDialog> createState() => _CreateFamilyDialogState();
}

class _CreateFamilyDialogState extends State<_CreateFamilyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'My Family');
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose a name for this family. You can invite relatives after it is created.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enableInteractiveSelection: true,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Family name'),
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}

class _DeleteAccountConfirmationDialog extends StatefulWidget {
  const _DeleteAccountConfirmationDialog();

  @override
  State<_DeleteAccountConfirmationDialog> createState() =>
      _DeleteAccountConfirmationDialogState();
}

class _DeleteAccountConfirmationDialogState
    extends State<_DeleteAccountConfirmationDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(context, _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account permanently?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your account, vault, memories, media, and family-tree links. This cannot be undone.',
          ),
          const SizedBox(height: 12),
          const Text('Enter your password to confirm this is you.'),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB3261E),
            foregroundColor: Colors.white,
          ),
          onPressed: _confirm,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _ChangePasswordValues {
  const _ChangePasswordValues({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String currentPassword;
  final String newPassword;
  final String confirmPassword;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(
      context,
      _ChangePasswordValues(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your current password to confirm this is you.'),
            const SizedBox(height: 12),
            TextField(
              controller: _currentPasswordController,
              autofocus: true,
              obscureText: _hideCurrentPassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Current password',
                suffixIcon: IconButton(
                  tooltip: _hideCurrentPassword ? 'Show' : 'Hide',
                  onPressed: () => setState(
                    () => _hideCurrentPassword = !_hideCurrentPassword,
                  ),
                  icon: Icon(
                    _hideCurrentPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: _hideNewPassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: _hideNewPassword ? 'Show' : 'Hide',
                  onPressed: () =>
                      setState(() => _hideNewPassword = !_hideNewPassword),
                  icon: Icon(
                    _hideNewPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _hideConfirmPassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Confirm password',
                suffixIcon: IconButton(
                  tooltip: _hideConfirmPassword ? 'Show' : 'Hide',
                  onPressed: () => setState(
                    () => _hideConfirmPassword = !_hideConfirmPassword,
                  ),
                  icon: Icon(
                    _hideConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('Change')),
      ],
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
