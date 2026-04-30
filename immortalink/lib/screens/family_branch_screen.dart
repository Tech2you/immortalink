import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_vault_screen.dart';
import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';

class FamilyBranchScreen extends StatefulWidget {
  final String familyId;
  final String rootLabel;
  final String rootSlotKey;
  final String direction; // 'ancestor' or 'descendant'

  const FamilyBranchScreen({
    super.key,
    required this.familyId,
    required this.rootLabel,
    required this.rootSlotKey,
    required this.direction,
  });

  @override
  State<FamilyBranchScreen> createState() => _FamilyBranchScreenState();
}

class _FamilyBranchScreenState extends State<FamilyBranchScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';
  static const String _vaultAvatarBucket = 'avatars';
  static const String _legacyAvatarBucket = 'vault_photos';

  static const int _maxAncestorDepth = 6;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _vaults = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _legacyMembers = [];
  List<Map<String, dynamic>> _relationships = [];
  final Map<String, String> _avatarUrlByVaultId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _signedStorageUrl({
    required String bucket,
    required String path,
  }) async {
    try {
      final signed =
          await _supabase.storage.from(bucket).createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _signedVaultAvatarUrl(String path) {
    return _signedStorageUrl(bucket: _vaultAvatarBucket, path: path);
  }

  Future<String?> _signedLegacyAvatarUrl(String path) {
    return _signedStorageUrl(bucket: _legacyAvatarBucket, path: path);
  }

  Future<Map<String, String>> _loadLegacyAvatarFallbackPaths() async {
    final result = <String, String>{};

    try {
      final res = await _supabase
          .from('legacy_member_photos')
          .select('legacy_member_id, path, created_at')
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: false);

      final rows = (res as List).cast<Map<String, dynamic>>();

      for (final row in rows) {
        final legacyId = (row['legacy_member_id'] ?? '').toString().trim();
        final path = (row['path'] ?? '').toString().trim();
        if (legacyId.isEmpty || path.isEmpty) continue;

        final existing = result[legacyId];
        final isProfilePath = path.toLowerCase().contains('/profile_picture/');

        if (existing == null) {
          result[legacyId] = path;
          continue;
        }

        final existingIsProfile =
            existing.toLowerCase().contains('/profile_picture/');

        if (!existingIsProfile && isProfilePath) {
          result[legacyId] = path;
        }
      }
    } catch (_) {}

    return result;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final vaultRes = await _supabase
          .from('vaults')
          .select('id, name, display_name, owner_id, family_id, avatar_path')
          .eq('family_id', widget.familyId);

      final memberRes = await _supabase
          .from('family_members')
          .select('user_id, slot_key, role, joined_at')
          .eq('family_id', widget.familyId);

      final legacyRes = await _supabase
          .from('legacy_family_members')
          .select(
            'id, family_id, slot_key, name, display_name, birth_year, death_year, created_at, updated_at, replaced_by_vault_id, about_me_text, avatar_path',
          )
          .eq('family_id', widget.familyId);

      final relRes = await _supabase
          .from('family_relationships')
          .select(
            'id, family_id, parent_type, parent_id, child_type, child_id, relationship_kind, created_at',
          )
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: true);

      final vaults = (vaultRes as List).cast<Map<String, dynamic>>();
      final members = (memberRes as List).cast<Map<String, dynamic>>();
      final legacyMembers = (legacyRes as List).cast<Map<String, dynamic>>();
      final relationships = (relRes as List).cast<Map<String, dynamic>>();

      final avatarMap = <String, String>{};

      for (final v in vaults) {
        final id = (v['id'] ?? '').toString().trim();
        final path = (v['avatar_path'] ?? '').toString().trim();
        if (id.isEmpty || path.isEmpty) continue;

        final url = await _signedVaultAvatarUrl(path);
        if (url != null && url.trim().isNotEmpty) {
          avatarMap[id] = url;
        }
      }

      final legacyFallbackPathById = await _loadLegacyAvatarFallbackPaths();

      for (final legacy in legacyMembers) {
        final id = (legacy['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final dbPath = (legacy['avatar_path'] ?? '').toString().trim();
        final fallbackPath = legacyFallbackPathById[id];
        final chosenPath = dbPath.isNotEmpty ? dbPath : (fallbackPath ?? '');

        if (chosenPath.isEmpty) continue;

        final url = await _signedLegacyAvatarUrl(chosenPath);
        if (url != null && url.trim().isNotEmpty) {
          avatarMap[id] = url;
        }
      }

      if (!mounted) return;
      setState(() {
        _vaults = vaults;
        _members = members;
        _legacyMembers = legacyMembers;
        _relationships = relationships;
        _avatarUrlByVaultId
          ..clear()
          ..addAll(avatarMap);
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

  Map<String, Map<String, dynamic>> _slotToPersonMap() {
    final vaultByUser = <String, Map<String, dynamic>>{};
    for (final v in _vaults) {
      final ownerId = (v['owner_id'] ?? '').toString();
      if (ownerId.isNotEmpty) {
        vaultByUser[ownerId] = v;
      }
    }

    final result = <String, Map<String, dynamic>>{};
    for (final m in _members) {
      final slotKey = (m['slot_key'] ?? '').toString().trim();
      final userId = (m['user_id'] ?? '').toString().trim();
      if (slotKey.isEmpty || userId.isEmpty) continue;

      final vault = vaultByUser[userId];
      if (vault != null) {
        result[slotKey] = vault;
      }
    }

    for (final legacy in _legacyMembers) {
      final slotKey = (legacy['slot_key'] ?? '').toString().trim();
      final replacedByVaultId =
          (legacy['replaced_by_vault_id'] ?? '').toString().trim();

      if (slotKey.isEmpty) continue;
      if (replacedByVaultId.isNotEmpty) continue;

      result.putIfAbsent(
        slotKey,
        () => {
          ...legacy,
          '__legacy': true,
        },
      );
    }

    return result;
  }

  Map<String, dynamic>? _personForNode(_NodeRef node) {
    if (node.type == 'vault') {
      for (final v in _vaults) {
        if ((v['id'] ?? '').toString() == node.id) return v;
      }
      return null;
    }

    if (node.type == 'legacy') {
      for (final l in _legacyMembers) {
        if ((l['id'] ?? '').toString() == node.id) {
          final replacedByVaultId =
              (l['replaced_by_vault_id'] ?? '').toString().trim();
          if (replacedByVaultId.isNotEmpty) return null;
          return {
            ...l,
            '__legacy': true,
          };
        }
      }
    }

    return null;
  }

  Future<void> _openPerson(Map<String, dynamic> person) async {
    final uid = _supabase.auth.currentUser?.id;
    final isLegacy = person['__legacy'] == true;

    if (isLegacy) {
      final legacyId = (person['id'] ?? '').toString();
      if (legacyId.isEmpty) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LegacyVaultScreen(
            legacyMemberId: legacyId,
            familyId: widget.familyId,
          ),
        ),
      );
      await _load();
      return;
    }

    final vaultId = (person['id'] ?? '').toString();
    final ownerId = (person['owner_id'] ?? '').toString();
    final vaultName = ((person['display_name'] ?? '').toString().trim().isNotEmpty
            ? person['display_name']
            : person['name'] ?? 'Vault')
        .toString();

    if (vaultId.isEmpty) return;

    if (!mounted) return;
    if (uid != null && ownerId == uid) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VaultHomeScreen(
            vaultId: vaultId,
            vaultName: vaultName,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VaultReadOnlyScreen(
            vaultId: vaultId,
            vaultName: vaultName,
          ),
        ),
      );
    }

    await _load();
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

  Future<void> _openBranchOptions({
    required String slotKey,
    required Map<String, dynamic> person,
  }) async {
    final direction = _branchDirectionForSlot(slotKey);

    if (direction == null) {
      await _openPerson(person);
      return;
    }

    if (!mounted) return;

    final label = _branchLabelForSlot(slotKey);

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose whether to open this person\'s vault or continue into their branch.',
                style: TextStyle(color: Colors.black.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.lock_open_outlined),
                ),
                title: const Text('Open vault'),
                subtitle: const Text('View this person\'s vault content'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openPerson(person);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.account_tree_outlined),
                ),
                title: const Text('Open branch'),
                subtitle: Text(
                  direction == 'ancestor'
                      ? 'Go further into this ancestor line'
                      : 'Go further into this descendant line',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FamilyBranchScreen(
                        familyId: widget.familyId,
                        rootLabel: label,
                        rootSlotKey: slotKey,
                        direction: direction,
                      ),
                    ),
                  );
                  await _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _personLabel(Map<String, dynamic>? person, String fallback) {
    if (person == null) return fallback;
    final display = (person['display_name'] ?? '').toString().trim();
    final name = (person['name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    if (name.isNotEmpty) return name;
    return fallback;
  }

  String? _avatarFor(Map<String, dynamic>? person) {
    if (person == null) return null;
    final id = (person['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return _avatarUrlByVaultId[id];
  }

  _BranchConfig _buildBranchConfig() {
    final isAncestor = widget.direction == 'ancestor';

    if (isAncestor) {
      switch (widget.rootSlotKey) {
        case 'mother':
          return const _BranchConfig(
            title: 'Maternal branch',
            centerSlot: 'mother',
            centerFallback: 'Mother',
            primarySlots: ['maternal_gm', 'maternal_gf'],
            primaryLabels: ['Grandmother', 'Grandfather'],
            secondarySlots: ['maternal_ggm', 'maternal_ggf'],
            secondaryLabels: ['Great-grandmother', 'Great-grandfather'],
          );
        case 'father':
          return const _BranchConfig(
            title: 'Paternal branch',
            centerSlot: 'father',
            centerFallback: 'Father',
            primarySlots: ['paternal_gm', 'paternal_gf'],
            primaryLabels: ['Grandmother', 'Grandfather'],
            secondarySlots: ['paternal_ggm', 'paternal_ggf'],
            secondaryLabels: ['Great-grandmother', 'Great-grandfather'],
          );
        case 'maternal_gm':
          return const _BranchConfig(
            title: 'Maternal grandmother branch',
            centerSlot: 'maternal_gm',
            centerFallback: 'Grandmother',
            primarySlots: ['maternal_ggm', 'maternal_ggf'],
            primaryLabels: ['Great-grandmother', 'Great-grandfather'],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'maternal_gf':
          return const _BranchConfig(
            title: 'Maternal grandfather branch',
            centerSlot: 'maternal_gf',
            centerFallback: 'Grandfather',
            primarySlots: ['maternal_ggm', 'maternal_ggf'],
            primaryLabels: ['Great-grandmother', 'Great-grandfather'],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'paternal_gm':
          return const _BranchConfig(
            title: 'Paternal grandmother branch',
            centerSlot: 'paternal_gm',
            centerFallback: 'Grandmother',
            primarySlots: ['paternal_ggm', 'paternal_ggf'],
            primaryLabels: ['Great-grandmother', 'Great-grandfather'],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'paternal_gf':
          return const _BranchConfig(
            title: 'Paternal grandfather branch',
            centerSlot: 'paternal_gf',
            centerFallback: 'Grandfather',
            primarySlots: ['paternal_ggm', 'paternal_ggf'],
            primaryLabels: ['Great-grandmother', 'Great-grandfather'],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'maternal_ggm':
          return const _BranchConfig(
            title: 'Maternal great-grandmother branch',
            centerSlot: 'maternal_ggm',
            centerFallback: 'Great-grandmother',
            primarySlots: [],
            primaryLabels: [],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'maternal_ggf':
          return const _BranchConfig(
            title: 'Maternal great-grandfather branch',
            centerSlot: 'maternal_ggf',
            centerFallback: 'Great-grandfather',
            primarySlots: [],
            primaryLabels: [],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'paternal_ggm':
          return const _BranchConfig(
            title: 'Paternal great-grandmother branch',
            centerSlot: 'paternal_ggm',
            centerFallback: 'Great-grandmother',
            primarySlots: [],
            primaryLabels: [],
            secondarySlots: [],
            secondaryLabels: [],
          );
        case 'paternal_ggf':
          return const _BranchConfig(
            title: 'Paternal great-grandfather branch',
            centerSlot: 'paternal_ggf',
            centerFallback: 'Great-grandfather',
            primarySlots: [],
            primaryLabels: [],
            secondarySlots: [],
            secondaryLabels: [],
          );
        default:
          return _BranchConfig(
            title: widget.rootLabel,
            centerSlot: widget.rootSlotKey,
            centerFallback: widget.rootLabel,
            primarySlots: const [],
            primaryLabels: const [],
            secondarySlots: const [],
            secondaryLabels: const [],
          );
      }
    }

    switch (widget.rootSlotKey) {
      case 'child_1':
      case 'child_2':
      case 'child_3':
      case 'child_4':
        return _BranchConfig(
          title: 'Descendant branch',
          centerSlot: widget.rootSlotKey,
          centerFallback: 'Child',
          primarySlots: const [
            'grandchild_1',
            'grandchild_2',
            'grandchild_3',
            'grandchild_4',
          ],
          primaryLabels: const [
            'Grandchild',
            'Grandchild',
            'Grandchild',
            'Grandchild',
          ],
          secondarySlots: const [
            'greatgrandchild_1',
            'greatgrandchild_2',
            'greatgrandchild_3',
            'greatgrandchild_4',
          ],
          secondaryLabels: const [
            'Great-grandchild',
            'Great-grandchild',
            'Great-grandchild',
            'Great-grandchild',
          ],
        );
      case 'grandchild_1':
      case 'grandchild_2':
      case 'grandchild_3':
      case 'grandchild_4':
        return _BranchConfig(
          title: 'Grandchild branch',
          centerSlot: widget.rootSlotKey,
          centerFallback: 'Grandchild',
          primarySlots: const [
            'greatgrandchild_1',
            'greatgrandchild_2',
            'greatgrandchild_3',
            'greatgrandchild_4',
          ],
          primaryLabels: const [
            'Great-grandchild',
            'Great-grandchild',
            'Great-grandchild',
            'Great-grandchild',
          ],
          secondarySlots: const [],
          secondaryLabels: const [],
        );
      case 'greatgrandchild_1':
      case 'greatgrandchild_2':
      case 'greatgrandchild_3':
      case 'greatgrandchild_4':
        return _BranchConfig(
          title: 'Great-grandchild branch',
          centerSlot: widget.rootSlotKey,
          centerFallback: 'Great-grandchild',
          primarySlots: const [],
          primaryLabels: const [],
          secondarySlots: const [],
          secondaryLabels: const [],
        );
      default:
        return _BranchConfig(
          title: widget.rootLabel,
          centerSlot: widget.rootSlotKey,
          centerFallback: widget.rootLabel,
          primarySlots: const [],
          primaryLabels: const [],
          secondarySlots: const [],
          secondaryLabels: const [],
        );
    }
  }

  _NodeRef? _rootNodeRefFromSlot() {
    final slotMap = _slotToPersonMap();
    final person = slotMap[widget.rootSlotKey];
    if (person == null) return null;

    final isLegacy = person['__legacy'] == true;
    final id = (person['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;

    return _NodeRef(
      type: isLegacy ? 'legacy' : 'vault',
      id: id,
    );
  }

  List<_NodeRef> _parentsOf(_NodeRef child) {
    final refs = <_NodeRef>[];

    for (final row in _relationships) {
      final childType = (row['child_type'] ?? '').toString().trim();
      final childId = (row['child_id'] ?? '').toString().trim();
      final kind = (row['relationship_kind'] ?? '').toString().trim();

      if (kind != 'parent_child') continue;
      if (childType != child.type || childId != child.id) continue;

      final parentType = (row['parent_type'] ?? '').toString().trim();
      final parentId = (row['parent_id'] ?? '').toString().trim();
      if (parentType.isEmpty || parentId.isEmpty) continue;

      final ref = _NodeRef(type: parentType, id: parentId);
      final exists = refs.any((e) => e.type == ref.type && e.id == ref.id);
      if (!exists) refs.add(ref);
    }

    return refs;
  }

  List<_AncestorGeneration> _buildAncestorGenerations(_NodeRef rootRef) {
    final generations = <_AncestorGeneration>[];
    List<_AncestorBranchNode> current = [_AncestorBranchNode(ref: rootRef)];

    for (int depth = 1; depth <= _maxAncestorDepth; depth++) {
      final next = <_AncestorBranchNode>[];

      for (final child in current) {
        final childPerson =
            child.ref == null ? null : _personForNode(child.ref!);

        if (child.ref == null || childPerson == null) {
          next.add(
            _AncestorBranchNode(
              ref: null,
              childRefForAdd: child.childRefForAdd,
            ),
          );
          next.add(
            _AncestorBranchNode(
              ref: null,
              childRefForAdd: child.childRefForAdd,
            ),
          );
          continue;
        }

        final parents = _parentsOf(child.ref!);
        final first = parents.isNotEmpty ? parents[0] : null;
        final second = parents.length > 1 ? parents[1] : null;

        next.add(
          _AncestorBranchNode(
            ref: first,
            childRefForAdd: child.ref,
          ),
        );
        next.add(
          _AncestorBranchNode(
            ref: second,
            childRefForAdd: child.ref,
          ),
        );
      }

      if (next.isEmpty) break;

      generations.add(
        _AncestorGeneration(
          depth: depth,
          nodes: next,
        ),
      );

      current = next;
    }

    return generations;
  }

  String _generationTitle(int depth) {
    if (depth == 1) return 'One generation further back';
    if (depth == 2) return 'Two generations further back';
    if (depth == 3) return 'Three generations further back';
    return '$depth generations further back';
  }

  Future<String?> _getMyVaultIdForInvite() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return null;

      final v = await _supabase
          .from('vaults')
          .select('id')
          .eq('owner_id', uid)
          .maybeSingle();

      final id = (v?['id'] ?? '').toString().trim();
      if (id.isEmpty) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      10,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<String> _createUniqueInviteCode() async {
    for (int i = 0; i < 12; i++) {
      final code = _generateInviteCode();
      final exists = await _supabase
          .from('family_invites')
          .select('id')
          .eq('invite_code', code)
          .maybeSingle();

      if (exists == null) return code;
    }
    throw Exception('Could not generate a unique invite code. Please try again.');
  }

  Future<void> _createAncestorInvite({
    required _NodeRef childRef,
    required String title,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final expiresAt = DateTime.now().add(const Duration(days: 7)).toUtc();
      final myVaultId = await _getMyVaultIdForInvite();

      if (myVaultId == null || myVaultId.trim().isEmpty) {
        throw Exception('You need your own vault before creating invites.');
      }

      String? inviteId;
      String? code;

      for (int attempt = 0; attempt < 8; attempt++) {
        final nextCode = await _createUniqueInviteCode();

        try {
          final inserted = await _supabase
              .from('family_invites')
              .insert({
                'family_id': widget.familyId,
                'created_by': user.id,
                'invite_code': nextCode,
                'slot_key': widget.rootSlotKey,
                'expires_at': expiresAt.toIso8601String(),
                'inviter_vault_id': myVaultId,
              })
              .select('id')
              .maybeSingle();

          inviteId = (inserted?['id'] ?? '').toString().trim();
          code = nextCode;
          if (inviteId.isNotEmpty) break;
        } on PostgrestException catch (e) {
          final msg = e.message.toLowerCase();
          final duplicate =
              e.code == '23505' || msg.contains('duplicate key value');
          if (duplicate) {
            continue;
          }
          rethrow;
        }
      }

      if (inviteId == null || inviteId.isEmpty || code == null || code.isEmpty) {
        throw Exception('Invite creation failed after multiple retries.');
      }

      await _supabase.from('family_relationships').insert({
        'family_id': widget.familyId,
        'parent_type': 'invite',
        'parent_id': inviteId,
        'child_type': childRef.type,
        'child_id': childRef.id,
        'relationship_kind': 'parent_child',
      });

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Invite created: $title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Invite code (copy & share):'),
              const SizedBox(height: 6),
              SelectableText(
                code!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Expires: ${expiresAt.toLocal()}',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code!));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite failed: $e')),
      );
    }
  }

  Future<void> _showLegacyAncestorDialog({
    required _NodeRef childRef,
    required String title,
  }) async {
    final nameController = TextEditingController();
    final displayNameController = TextEditingController();
    final birthYearController = TextEditingController();
    final deathYearController = TextEditingController();
    final aboutController = TextEditingController();

    String? errorText;
    bool saving = false;

    int? parseYear(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t);
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('Add legacy $title'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a family-owned predecessor profile and link it as a parent in this branch.',
                    style: TextStyle(color: Colors.black.withOpacity(0.65)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: birthYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Birth year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aboutController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'About me / notes (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: deathYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Death year (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(errorText!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final displayName = displayNameController.text.trim();
                      final birthYear = parseYear(birthYearController.text);
                      final deathYear = parseYear(deathYearController.text);
                      final about = aboutController.text.trim();
                      final userId = _supabase.auth.currentUser?.id;

                      if (name.isEmpty) {
                        setInner(() => errorText = 'Name is required.');
                        return;
                      }

                      if (birthYearController.text.trim().isNotEmpty &&
                          birthYear == null) {
                        setInner(() =>
                            errorText = 'Birth year must be a valid number.');
                        return;
                      }

                      if (deathYearController.text.trim().isNotEmpty &&
                          deathYear == null) {
                        setInner(() =>
                            errorText = 'Death year must be a valid number.');
                        return;
                      }

                      if (userId == null) {
                        setInner(() => errorText = 'You must be signed in.');
                        return;
                      }

                      setInner(() {
                        saving = true;
                        errorText = null;
                      });

                      try {
                        final inserted = await _supabase
                            .from('legacy_family_members')
                            .insert({
                              'family_id': widget.familyId,
                              'slot_key': null,
                              'name': name,
                              'display_name':
                                  displayName.isEmpty ? null : displayName,
                              'birth_year': birthYear,
                              'death_year': deathYear,
                              'about_me_text': about.isEmpty ? null : about,
                              'created_by': userId,
                            })
                            .select('id')
                            .maybeSingle();

                        final legacyId =
                            (inserted?['id'] ?? '').toString().trim();
                        if (legacyId.isEmpty) {
                          throw Exception(
                            'Legacy predecessor was created but no id was returned.',
                          );
                        }

                        await _supabase.from('family_relationships').insert({
                          'family_id': widget.familyId,
                          'parent_type': 'legacy',
                          'parent_id': legacyId,
                          'child_type': childRef.type,
                          'child_id': childRef.id,
                          'relationship_kind': 'parent_child',
                        });

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _load();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$title added.')),
                        );
                      } on PostgrestException catch (e) {
                        setInner(() {
                          saving = false;
                          errorText = e.message;
                        });
                      } catch (e) {
                        setInner(() {
                          saving = false;
                          errorText = e.toString();
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAncestorAddOptions({
    required _NodeRef childRef,
    required String title,
  }) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add $title',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose whether to invite a living relative or add a legacy predecessor profile for this branch.',
                style: TextStyle(color: Colors.black.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1),
                ),
                title: const Text('Invite relative'),
                subtitle: const Text('Create an invite linked as a parent here'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createAncestorInvite(
                    childRef: childRef,
                    title: title,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy predecessor'),
                subtitle:
                    const Text('Create a family-owned ancestor profile here'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLegacyAncestorDialog(
                    childRef: childRef,
                    title: title,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAncestorRelationshipView() {
    final rootRef = _rootNodeRefFromSlot();
    if (rootRef == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _BranchIntroCard(
            title: widget.rootLabel,
            subtitle:
                'This branch can load once the selected person exists in the family tree.',
          ),
        ),
      );
    }

    final rootPerson = _personForNode(rootRef);
    final generations = _buildAncestorGenerations(rootRef);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: 0.06,
                child: Image.asset(
                  _logoPath,
                  width: 520,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  children: [
                    _BranchIntroCard(
                      title: widget.rootLabel.isEmpty
                          ? 'Ancestor branch'
                          : '${widget.rootLabel} branch',
                      subtitle:
                          'This branch focuses on one ancestral line and can continue further back generation by generation.',
                    ),
                    const SizedBox(height: 16),
                    _BranchPersonCard(
                      title: 'Branch focus',
                      label: _personLabel(rootPerson, widget.rootLabel),
                      avatarUrl: _avatarFor(rootPerson),
                      onTap: rootPerson == null
                          ? null
                          : () async {
                              await _openPerson(rootPerson);
                            },
                    ),
                    for (final generation in generations) ...[
                      const SizedBox(height: 22),
                      _BranchSectionTitle(
                        title: _generationTitle(generation.depth),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: generation.nodes.map((node) {
                          final person =
                              node.ref == null ? null : _personForNode(node.ref!);

                          if (person == null) {
                            return _MiniBranchAddCard(
                              label: 'Add ancestor',
                              onTap: node.childRefForAdd == null
                                  ? null
                                  : () => _openAncestorAddOptions(
                                        childRef: node.childRefForAdd!,
                                        title: 'Ancestor',
                                      ),
                            );
                          }

                          return _MiniBranchCard(
                            label: _personLabel(person, 'Ancestor'),
                            avatarUrl: _avatarFor(person),
                            onTap: () async {
                              await _openPerson(person);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _BranchIntroCard(
                      title: 'Next phase',
                      subtitle:
                          'This ancestor branch now reads from family relationships so you can keep extending the line further back without changing the family tree home screen.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAncestor = widget.direction == 'ancestor';

    return Scaffold(
      appBar: AppBar(
        title: Text(isAncestor ? 'Ancestor Branch' : 'Descendant Branch'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : isAncestor
                  ? _buildAncestorRelationshipView()
                  : Builder(
                      builder: (context) {
                        final slotMap = _slotToPersonMap();
                        final config = _buildBranchConfig();

                        final centerPerson = slotMap[config.centerSlot];
                        final primaryPeople = List.generate(
                          config.primarySlots.length,
                          (i) => slotMap[config.primarySlots[i]],
                        );
                        final secondaryPeople = List.generate(
                          config.secondarySlots.length,
                          (i) => slotMap[config.secondarySlots[i]],
                        );

                        return Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Center(
                                  child: Opacity(
                                    opacity: 0.06,
                                    child: Image.asset(
                                      _logoPath,
                                      width: 520,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 900),
                                    child: Column(
                                      children: [
                                        _BranchIntroCard(
                                          title: config.title,
                                          subtitle:
                                              'This branch focuses on one descendant line.',
                                        ),
                                        const SizedBox(height: 16),
                                        _BranchPersonCard(
                                          title: 'Branch focus',
                                          label: _personLabel(
                                            centerPerson,
                                            config.centerFallback,
                                          ),
                                          avatarUrl: _avatarFor(centerPerson),
                                          onTap: centerPerson == null
                                              ? null
                                              : () => _openBranchOptions(
                                                    slotKey: config.centerSlot,
                                                    person: centerPerson,
                                                  ),
                                        ),
                                        if (config.primarySlots.isNotEmpty) ...[
                                          const SizedBox(height: 18),
                                          _BranchSectionTitle(
                                            title:
                                                'Next generation in this line',
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            alignment: WrapAlignment.center,
                                            children: List.generate(
                                              config.primarySlots.length,
                                              (i) => _MiniBranchCard(
                                                label: _personLabel(
                                                  primaryPeople[i],
                                                  config.primaryLabels[i],
                                                ),
                                                avatarUrl:
                                                    _avatarFor(primaryPeople[i]),
                                                onTap: primaryPeople[i] == null
                                                    ? null
                                                    : () => _openBranchOptions(
                                                          slotKey: config
                                                              .primarySlots[i],
                                                          person:
                                                              primaryPeople[i]!,
                                                        ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (config.secondarySlots.isNotEmpty) ...[
                                          const SizedBox(height: 18),
                                          _BranchSectionTitle(
                                            title: 'Future descendants',
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            alignment: WrapAlignment.center,
                                            children: List.generate(
                                              config.secondarySlots.length,
                                              (i) => _MiniBranchCard(
                                                label: _personLabel(
                                                  secondaryPeople[i],
                                                  config.secondaryLabels[i],
                                                ),
                                                avatarUrl: _avatarFor(
                                                  secondaryPeople[i],
                                                ),
                                                onTap:
                                                    secondaryPeople[i] == null
                                                        ? null
                                                        : () =>
                                                            _openBranchOptions(
                                                              slotKey: config
                                                                  .secondarySlots[i],
                                                              person:
                                                                  secondaryPeople[i]!,
                                                            ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 22),
                                        _BranchIntroCard(
                                          title: 'Next phase',
                                          subtitle:
                                              'This descendant branch remains compatible with the current family tree flow.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
    );
  }
}

class _BranchConfig {
  final String title;
  final String centerSlot;
  final String centerFallback;
  final List<String> primarySlots;
  final List<String> primaryLabels;
  final List<String> secondarySlots;
  final List<String> secondaryLabels;

  const _BranchConfig({
    required this.title,
    required this.centerSlot,
    required this.centerFallback,
    required this.primarySlots,
    required this.primaryLabels,
    required this.secondarySlots,
    required this.secondaryLabels,
  });
}

class _BranchIntroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _BranchIntroCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.black.withOpacity(0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchSectionTitle extends StatelessWidget {
  final String title;

  const _BranchSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BranchPersonCard extends StatelessWidget {
  final String title;
  final String label;
  final String? avatarUrl;
  final VoidCallback? onTap;

  const _BranchPersonCard({
    required this.title,
    required this.label,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.88,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
            color: Colors.white.withOpacity(0.36),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.58),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _BranchAvatar(url: avatarUrl, radius: 30),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBranchCard extends StatelessWidget {
  final String label;
  final String? avatarUrl;
  final VoidCallback? onTap;

  const _MiniBranchCard({
    required this.label,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.86,
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
            color: Colors.white.withOpacity(0.32),
          ),
          child: Column(
            children: [
              _BranchAvatar(url: avatarUrl, radius: 22),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBranchAddCard extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _MiniBranchAddCard({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.70,
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
            color: Colors.white.withOpacity(0.28),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.black.withOpacity(0.08),
                child: Icon(
                  Icons.add,
                  color: Colors.black.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchAvatar extends StatelessWidget {
  final String? url;
  final double radius;

  const _BranchAvatar({
    required this.url,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    final has = u.isNotEmpty;

    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.08),
      ),
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.black.withOpacity(0.55),
      ),
    );

    if (!has) return fallback;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          u,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

class _NodeRef {
  final String type;
  final String id;

  const _NodeRef({
    required this.type,
    required this.id,
  });
}

class _AncestorBranchNode {
  final _NodeRef? ref;
  final _NodeRef? childRefForAdd;

  const _AncestorBranchNode({
    required this.ref,
    this.childRefForAdd,
  });
}

class _AncestorGeneration {
  final int depth;
  final List<_AncestorBranchNode> nodes;

  const _AncestorGeneration({
    required this.depth,
    required this.nodes,
  });
}