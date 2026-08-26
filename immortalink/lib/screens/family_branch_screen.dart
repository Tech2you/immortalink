import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_tree_screen.dart';
import 'legacy_vault_screen.dart';
import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';
import '../utils/everroot_upgrade_prompt.dart';

class FamilyBranchScreen extends StatefulWidget {
  final String familyId;
  final String rootLabel;
  final String rootSlotKey;
  final String direction; // 'ancestor' or 'descendant'

  final String? rootNodeType; // 'vault' or 'legacy'
  final String? rootNodeId;

  const FamilyBranchScreen({
    super.key,
    required this.familyId,
    required this.rootLabel,
    required this.rootSlotKey,
    required this.direction,
    this.rootNodeType,
    this.rootNodeId,
  });

  @override
  State<FamilyBranchScreen> createState() => _FamilyBranchScreenState();
}

class _FamilyBranchScreenState extends State<FamilyBranchScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';
  static const String _vaultAvatarBucket = 'avatars';
  static const String _legacyAvatarBucket = 'vault_photos';

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

  EdgeInsets _legacyDialogInsetPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return EdgeInsets.symmetric(
      horizontal: width < 600 ? 16 : 32,
      vertical: width < 600 ? 18 : 24,
    );
  }

  Widget _legacyDialogContent(
    BuildContext context, {
    required Widget child,
    double desktopMaxWidth = 560,
  }) {
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 600 ? 16.0 : 32.0;
    final contentPadding = size.width < 600 ? 40.0 : 48.0;
    final availableWidth = size.width - (horizontalInset * 2) - contentPadding;
    final width = min(availableWidth, desktopMaxWidth);
    final maxHeight = size.height * (size.width < 600 ? 0.68 : 0.76);

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  Future<String?> _signedStorageUrl({
    required String bucket,
    required String path,
  }) async {
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

        final existingIsProfile = existing.toLowerCase().contains(
          '/profile_picture/',
        );

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
      final replacedByVaultId = (legacy['replaced_by_vault_id'] ?? '')
          .toString()
          .trim();

      if (slotKey.isEmpty) continue;
      if (replacedByVaultId.isNotEmpty) continue;

      result[slotKey] = {...legacy, '__legacy': true};
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
          final replacedByVaultId = (l['replaced_by_vault_id'] ?? '')
              .toString()
              .trim();
          if (replacedByVaultId.isNotEmpty) return null;
          return {...l, '__legacy': true};
        }
      }
    }

    return null;
  }

  _NodeRef? _nodeRefFromPerson(Map<String, dynamic>? person) {
    if (person == null) return null;
    final id = (person['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final isLegacy = person['__legacy'] == true;
    return _NodeRef(type: isLegacy ? 'legacy' : 'vault', id: id);
  }

  String _nodeKey(_NodeRef ref) => '${ref.type}:${ref.id}';

  _NodeRef? _slotRef(String? slotKey) {
    final normalized = (slotKey ?? '').trim();
    if (normalized.isEmpty) return null;
    final person = _slotToPersonMap()[normalized];
    return _nodeRefFromPerson(person);
  }

  List<_NodeRef?> _refsForDisplaySlots({
    required List<String?> slotKeys,
    required List<_NodeRef> relatedRefs,
  }) {
    final result = List<_NodeRef?>.filled(slotKeys.length, null);
    final used = <String>{};

    int nextOpenIndex() {
      for (int i = 0; i < result.length; i++) {
        if (result[i] == null) return i;
      }
      return -1;
    }

    // First priority: actual relationship-linked people for this branch.
    for (final ref in relatedRefs) {
      final key = _nodeKey(ref);
      if (used.contains(key)) continue;

      final hintedSlot = _slotHintForNode(ref);
      final hintedIndex = slotKeys.indexOf(hintedSlot);

      if (hintedIndex != -1 && result[hintedIndex] == null) {
        result[hintedIndex] = ref;
        used.add(key);
      }
    }

    // Second priority: place remaining related people left-to-right in open slots.
    for (final ref in relatedRefs) {
      final key = _nodeKey(ref);
      if (used.contains(key)) continue;

      final openIndex = nextOpenIndex();
      if (openIndex == -1) break;

      result[openIndex] = ref;
      used.add(key);
    }

    // Only if there are NO relationship-linked people at all do we fall back
    // to slot-bound people.
    if (relatedRefs.isEmpty) {
      for (int i = 0; i < slotKeys.length; i++) {
        final slotRef = _slotRef(slotKeys[i]);
        if (slotRef != null) {
          result[i] = slotRef;
        }
      }
    }

    return result;
  }

  List<_NodeRef?> _ancestorRefsForDisplay(
    _NodeRef? childRef,
    String? childSlotKey,
  ) {
    final slotKeys = _ancestorSlotKeysForNodeFromSlot(childSlotKey);
    final relatedRefs = childRef == null ? <_NodeRef>[] : _parentsOf(childRef);
    return _refsForDisplaySlots(slotKeys: slotKeys, relatedRefs: relatedRefs);
  }

  List<_NodeRef?> _descendantRefsForDisplay(
    _NodeRef? parentRef,
    String? parentSlotKey,
  ) {
    final slotKeys = _descendantSlotKeysForNodeFromSlot(parentSlotKey);
    final relatedRefs = parentRef == null
        ? <_NodeRef>[]
        : _childrenOf(parentRef);
    return _refsForDisplaySlots(slotKeys: slotKeys, relatedRefs: relatedRefs);
  }

  String _slotHintForNode(_NodeRef ref) {
    final slotMap = _slotToPersonMap();
    final person = _personForNode(ref);
    if (person == null) return '';
    final key = _nodeKey(ref);

    for (final entry in slotMap.entries) {
      final entryRef = _nodeRefFromPerson(entry.value);
      if (entryRef != null && _nodeKey(entryRef) == key) {
        return entry.key;
      }
    }

    return '';
  }

  int _slotPriority(String slot) {
    const ordered = [
      'mother',
      'father',
      'maternal_gm',
      'maternal_gf',
      'paternal_gm',
      'paternal_gf',
      'maternal_gm_mother',
      'maternal_gm_father',
      'maternal_gf_mother',
      'maternal_gf_father',
      'paternal_gm_mother',
      'paternal_gm_father',
      'paternal_gf_mother',
      'paternal_gf_father',
      'child_1',
      'child_2',
      'child_3',
      'child_4',
      'grandchild_1',
      'grandchild_2',
      'grandchild_3',
      'grandchild_4',
      'greatgrandchild_1',
      'greatgrandchild_2',
      'greatgrandchild_3',
      'greatgrandchild_4',
    ];
    final idx = ordered.indexOf(slot);
    return idx == -1 ? 999 : idx;
  }

  void _putSlotFromGlobalIfMissing(
    Map<String, Map<String, dynamic>> visible,
    Map<String, Map<String, dynamic>> global,
    String slotKey, {
    required Map<String, dynamic> viewer,
  }) {
    if (visible.containsKey(slotKey)) return;

    final person = global[slotKey];
    if (person == null) return;

    visible[slotKey] = {
      ...person,
      '__viewer_relation_slot': slotKey,
      '__viewer_person_id': viewer['id'],
    };
  }

  void _sortNodeRefs(List<_NodeRef> refs) {
    refs.sort((a, b) {
      final slotA = _slotHintForNode(a);
      final slotB = _slotHintForNode(b);

      final prioA = _slotPriority(slotA);
      final prioB = _slotPriority(slotB);

      if (prioA != prioB) return prioA.compareTo(prioB);

      final personA = _personForNode(a);
      final personB = _personForNode(b);

      final nameA = _personLabel(personA, '').toLowerCase();
      final nameB = _personLabel(personB, '').toLowerCase();

      return nameA.compareTo(nameB);
    });
  }

  List<String?> _ancestorSlotKeysForNodeFromSlot(String? slot) {
    switch ((slot ?? '').trim()) {
      case 'mother':
        return const ['maternal_gm', 'maternal_gf'];
      case 'father':
        return const ['paternal_gm', 'paternal_gf'];
      case 'maternal_gm':
        return const ['maternal_gm_mother', 'maternal_gm_father'];
      case 'maternal_gf':
        return const ['maternal_gf_mother', 'maternal_gf_father'];
      case 'paternal_gm':
        return const ['paternal_gm_mother', 'paternal_gm_father'];
      case 'paternal_gf':
        return const ['paternal_gf_mother', 'paternal_gf_father'];
      default:
        return const [null, null];
    }
  }

  List<String?> _ancestorSlotKeysForNode(_NodeRef? nodeRef) {
    final slot = nodeRef == null ? '' : _slotHintForNode(nodeRef);
    return _ancestorSlotKeysForNodeFromSlot(slot);
  }

  List<String?> _descendantSlotKeysForNodeFromSlot(String? slot) {
    switch ((slot ?? '').trim()) {
      case 'child_1':
      case 'child_2':
      case 'child_3':
      case 'child_4':
        return const [
          'grandchild_1',
          'grandchild_2',
          'grandchild_3',
          'grandchild_4',
        ];
      case 'grandchild_1':
      case 'grandchild_2':
      case 'grandchild_3':
      case 'grandchild_4':
        return const [
          'greatgrandchild_1',
          'greatgrandchild_2',
          'greatgrandchild_3',
          'greatgrandchild_4',
        ];
      default:
        return const [null, null, null, null];
    }
  }

  List<String?> _descendantSlotKeysForNode(_NodeRef? nodeRef) {
    final slot = nodeRef == null ? '' : _slotHintForNode(nodeRef);
    return _descendantSlotKeysForNodeFromSlot(slot);
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
    final vaultName =
        ((person['display_name'] ?? '').toString().trim().isNotEmpty
                ? person['display_name']
                : person['name'] ?? 'Vault')
            .toString();

    if (vaultId.isEmpty) return;

    if (!mounted) return;
    if (uid != null && ownerId == uid) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VaultHomeScreen(vaultId: vaultId, vaultName: vaultName),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VaultReadOnlyScreen(vaultId: vaultId, vaultName: vaultName),
        ),
      );
    }

    await _load();
  }

  Future<void> _openAncestorBranchForPerson(
    Map<String, dynamic> person, {
    required String fallbackLabel,
  }) async {
    final isLegacy = person['__legacy'] == true;
    final id = (person['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    final personRef = _nodeRefFromPerson(person);
    if (personRef == null) return;

    final nextSlotKey = _slotHintForNode(personRef);
    if (nextSlotKey.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyBranchScreen(
          familyId: widget.familyId,
          rootLabel: _personLabel(person, fallbackLabel),
          rootSlotKey: nextSlotKey,
          direction: 'ancestor',
          rootNodeType: isLegacy ? 'legacy' : 'vault',
          rootNodeId: id,
        ),
      ),
    );

    await _load();
  }

  Future<void> _exitToFamilyTree() async {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => FamilyTreeScreen(familyId: widget.familyId),
      ),
      (route) => false,
    );
  }

  bool _canOpenAncestorBranch(String slotKey) {
    return slotKey == 'mother' ||
        slotKey == 'father' ||
        slotKey == 'maternal_gm' ||
        slotKey == 'maternal_gf' ||
        slotKey == 'paternal_gm' ||
        slotKey == 'paternal_gf' ||
        slotKey == 'maternal_gm_mother' ||
        slotKey == 'maternal_gm_father' ||
        slotKey == 'maternal_gf_mother' ||
        slotKey == 'maternal_gf_father' ||
        slotKey == 'paternal_gm_mother' ||
        slotKey == 'paternal_gm_father' ||
        slotKey == 'paternal_gf_mother' ||
        slotKey == 'paternal_gf_father';
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
      case 'maternal_gm_mother':
      case 'maternal_gf_mother':
      case 'paternal_gm_mother':
      case 'paternal_gf_mother':
        return 'Great-grandmother';
      case 'maternal_gm_father':
      case 'maternal_gf_father':
      case 'paternal_gm_father':
      case 'paternal_gf_father':
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

                  final isLegacy = person['__legacy'] == true;
                  final personId = (person['id'] ?? '').toString().trim();

                  if (direction == 'ancestor') {
                    await _openAncestorBranchForPerson(
                      person,
                      fallbackLabel: label,
                    );
                  } else {
                    final personRef = _nodeRefFromPerson(person);
                    if (personRef == null) return;

                    final nextSlotKey = _slotHintForNode(personRef);
                    if (nextSlotKey.isEmpty) return;

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FamilyBranchScreen(
                          familyId: widget.familyId,
                          rootLabel: _personLabel(person, label),
                          rootSlotKey: nextSlotKey,
                          direction: direction,
                          rootNodeType: isLegacy ? 'legacy' : 'vault',
                          rootNodeId: personId.isEmpty ? null : personId,
                        ),
                      ),
                    );
                    await _load();
                  }
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

  _NodeRef? _rootNodeRefFromSlot() {
    final slotMap = _slotToPersonMap();
    final person = slotMap[widget.rootSlotKey];
    return _nodeRefFromPerson(person);
  }

  _NodeRef? _explicitRootNodeRef() {
    final type = (widget.rootNodeType ?? '').trim();
    final id = (widget.rootNodeId ?? '').trim();
    if (type.isEmpty || id.isEmpty) return null;
    return _NodeRef(type: type, id: id);
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
      if (parentType == 'invite') continue;

      final ref = _NodeRef(type: parentType, id: parentId);
      final exists = refs.any((e) => e.type == ref.type && e.id == ref.id);
      if (!exists) refs.add(ref);
    }

    _sortNodeRefs(refs);
    return refs;
  }

  List<_NodeRef> _childrenOf(_NodeRef parent) {
    final refs = <_NodeRef>[];

    for (final row in _relationships) {
      final parentType = (row['parent_type'] ?? '').toString().trim();
      final parentId = (row['parent_id'] ?? '').toString().trim();
      final kind = (row['relationship_kind'] ?? '').toString().trim();

      if (kind != 'parent_child') continue;
      if (parentType != parent.type || parentId != parent.id) continue;

      final childType = (row['child_type'] ?? '').toString().trim();
      final childId = (row['child_id'] ?? '').toString().trim();
      if (childType.isEmpty || childId.isEmpty) continue;
      if (childType == 'invite') continue;

      final ref = _NodeRef(type: childType, id: childId);
      final exists = refs.any((e) => e.type == ref.type && e.id == ref.id);
      if (!exists) refs.add(ref);
    }

    _sortNodeRefs(refs);
    return refs;
  }

  Future<_AncestorViewModel> _buildAncestorViewModel() async {
    final explicitRoot = _explicitRootNodeRef();

    _NodeRef? focusRef;
    String focusFallback = widget.rootLabel;

    if (explicitRoot != null) {
      focusRef = explicitRoot;
    } else {
      focusRef = _rootNodeRefFromSlot();
    }

    final focusPerson = focusRef == null ? null : _personForNode(focusRef);
    final generations = <_AncestorGeneration>[];

    final firstGenSlotKeys = _ancestorSlotKeysForNodeFromSlot(
      widget.rootSlotKey,
    );
    final firstGenRefs = _ancestorRefsForDisplay(focusRef, widget.rootSlotKey);

    if (firstGenSlotKeys.isNotEmpty) {
      generations.add(
        _AncestorGeneration(
          depth: 1,
          nodes: List.generate(firstGenSlotKeys.length, (index) {
            final ref = index < firstGenRefs.length
                ? firstGenRefs[index]
                : null;
            return _AncestorBranchNode(
              ref: ref,
              childRefForAdd: focusRef,
              slotKeyForAdd: firstGenSlotKeys[index],
            );
          }),
        ),
      );
    }

    final secondGenNodes = <_AncestorBranchNode>[];
    for (
      int firstIndex = 0;
      firstIndex < firstGenSlotKeys.length;
      firstIndex++
    ) {
      final firstGenRef = firstIndex < firstGenRefs.length
          ? firstGenRefs[firstIndex]
          : null;
      final firstGenSlotKey = firstGenSlotKeys[firstIndex];
      final parentSlots = _ancestorSlotKeysForNodeFromSlot(firstGenSlotKey);
      final parentRefs = _ancestorRefsForDisplay(firstGenRef, firstGenSlotKey);

      for (int i = 0; i < parentSlots.length; i++) {
        final ref = i < parentRefs.length ? parentRefs[i] : null;
        secondGenNodes.add(
          _AncestorBranchNode(
            ref: ref,
            childRefForAdd: firstGenRef,
            slotKeyForAdd: parentSlots[i],
          ),
        );
      }
    }

    if (secondGenNodes.isNotEmpty) {
      generations.add(_AncestorGeneration(depth: 2, nodes: secondGenNodes));
    }

    return _AncestorViewModel(
      focusPerson: focusPerson,
      focusFallback: focusFallback,
      generations: generations,
    );
  }

  Future<_DescendantViewModel> _buildDescendantViewModel() async {
    final explicitRoot = _explicitRootNodeRef();

    _NodeRef? focusRef;
    String focusFallback = widget.rootLabel;

    if (explicitRoot != null) {
      focusRef = explicitRoot;
    } else {
      focusRef = _rootNodeRefFromSlot();
    }

    final focusPerson = focusRef == null ? null : _personForNode(focusRef);
    final generations = <_DescendantGeneration>[];

    final firstGenSlotKeys = _descendantSlotKeysForNodeFromSlot(
      widget.rootSlotKey,
    );
    final firstGenRefs = _descendantRefsForDisplay(
      focusRef,
      widget.rootSlotKey,
    );

    if (firstGenSlotKeys.isNotEmpty) {
      generations.add(
        _DescendantGeneration(
          depth: 1,
          nodes: List.generate(firstGenSlotKeys.length, (index) {
            final ref = index < firstGenRefs.length
                ? firstGenRefs[index]
                : null;
            return _DescendantBranchNode(
              ref: ref,
              parentRefForAdd: focusRef,
              slotKeyForAdd: firstGenSlotKeys[index],
            );
          }),
        ),
      );
    }

    final secondGenNodes = <_DescendantBranchNode>[];
    for (
      int firstIndex = 0;
      firstIndex < firstGenSlotKeys.length;
      firstIndex++
    ) {
      final firstGenRef = firstIndex < firstGenRefs.length
          ? firstGenRefs[firstIndex]
          : null;
      final firstGenSlotKey = firstGenSlotKeys[firstIndex];
      final childSlots = _descendantSlotKeysForNodeFromSlot(firstGenSlotKey);
      final childRefs = _descendantRefsForDisplay(firstGenRef, firstGenSlotKey);

      for (int i = 0; i < childSlots.length; i++) {
        final ref = i < childRefs.length ? childRefs[i] : null;
        secondGenNodes.add(
          _DescendantBranchNode(
            ref: ref,
            parentRefForAdd: firstGenRef,
            slotKeyForAdd: childSlots[i],
          ),
        );
      }
    }

    if (secondGenNodes.isNotEmpty) {
      generations.add(_DescendantGeneration(depth: 2, nodes: secondGenNodes));
    }

    return _DescendantViewModel(
      focusPerson: focusPerson,
      focusFallback: focusFallback,
      generations: generations,
    );
  }

  String _generationTitle(int depth) {
    if (depth == 1) return 'One generation further back';
    if (depth == 2) return 'Two generations further back';
    if (depth == 3) return 'Three generations further back';
    return '$depth generations further back';
  }

  String _descendantGenerationTitle(int depth) {
    if (depth == 1) return 'Next generation in this line';
    if (depth == 2) return 'Future descendants';
    return '$depth generations forward';
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
    return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
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
    throw Exception(
      'Could not generate a unique invite code. Please try again.',
    );
  }

  Future<void> _createAncestorInvite({
    _NodeRef? childRef,
    required String title,
    String? slotKey,
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
      String code = '';

      for (int attempt = 0; attempt < 8; attempt++) {
        final nextCode = await _createUniqueInviteCode();

        try {
          final inserted = await _supabase
              .from('family_invites')
              .insert({
                'family_id': widget.familyId,
                'created_by': user.id,
                'invite_code': nextCode,
                'slot_key': slotKey,
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
          if (duplicate) continue;
          rethrow;
        }
      }

      if (inviteId == null || inviteId.isEmpty || code.isEmpty) {
        throw Exception('Invite creation failed after multiple retries.');
      }

      if (childRef != null) {
        await _supabase.from('family_relationships').insert({
          'family_id': widget.familyId,
          'parent_type': 'invite',
          'parent_id': inviteId,
          'child_type': childRef.type,
          'child_id': childRef.id,
          'relationship_kind': 'parent_child',
        });
      }

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
                code,
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
                await Clipboard.setData(ClipboardData(text: code));
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      if (isEverRootFamilyUpgradeError(e)) {
        await showEverRootFamilyUpgradePrompt(
          context,
          message: e is PostgrestException ? e.message : null,
        );
        return;
      }
      if (isEverRootQuotaError(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(everRootQuotaMessageFromError(e))),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    }
  }

  Future<void> _createDescendantInvite({
    _NodeRef? parentRef,
    required String title,
    String? slotKey,
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
      String code = '';

      for (int attempt = 0; attempt < 8; attempt++) {
        final nextCode = await _createUniqueInviteCode();

        try {
          final inserted = await _supabase
              .from('family_invites')
              .insert({
                'family_id': widget.familyId,
                'created_by': user.id,
                'invite_code': nextCode,
                'slot_key': slotKey,
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
          if (duplicate) continue;
          rethrow;
        }
      }

      if (inviteId == null || inviteId.isEmpty || code.isEmpty) {
        throw Exception('Invite creation failed after multiple retries.');
      }

      if (parentRef != null) {
        await _supabase.from('family_relationships').insert({
          'family_id': widget.familyId,
          'parent_type': parentRef.type,
          'parent_id': parentRef.id,
          'child_type': 'invite',
          'child_id': inviteId,
          'relationship_kind': 'parent_child',
        });
      }

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
                code,
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
                await Clipboard.setData(ClipboardData(text: code));
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      if (isEverRootFamilyUpgradeError(e)) {
        await showEverRootFamilyUpgradePrompt(
          context,
          message: e is PostgrestException ? e.message : null,
        );
        return;
      }
      if (isEverRootQuotaError(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(everRootQuotaMessageFromError(e))),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    }
  }

  Future<void> _showLegacyAncestorDialog({
    _NodeRef? childRef,
    required String title,
    String? slotKey,
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
          insetPadding: _legacyDialogInsetPadding(ctx),
          title: Text('Add legacy $title'),
          content: _legacyDialogContent(
            ctx,
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
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: displayNameController,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: birthYearController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
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
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text(
                    'Optional extra details',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    TextField(
                      controller: deathYearController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Death year (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
              ],
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

                      if (name.isEmpty) {
                        setInner(() => errorText = 'Name is required.');
                        return;
                      }

                      if (birthYearController.text.trim().isNotEmpty &&
                          birthYear == null) {
                        setInner(
                          () =>
                              errorText = 'Birth year must be a valid number.',
                        );
                        return;
                      }

                      if (deathYearController.text.trim().isNotEmpty &&
                          deathYear == null) {
                        setInner(
                          () =>
                              errorText = 'Death year must be a valid number.',
                        );
                        return;
                      }

                      setInner(() {
                        saving = true;
                        errorText = null;
                      });

                      try {
                        String createdLegacyId = '';

                        if (childRef == null) {
                          final uid = _supabase.auth.currentUser?.id;
                          if (uid == null || uid.trim().isEmpty) {
                            throw Exception(
                              'You must be signed in to create a legacy ancestor.',
                            );
                          }

                          final inserted = await _supabase
                              .from('legacy_family_members')
                              .insert({
                                'family_id': widget.familyId,
                                'slot_key': slotKey,
                                'name': name,
                                'display_name': displayName.isEmpty
                                    ? null
                                    : displayName,
                                'birth_year': birthYear,
                                'death_year': deathYear,
                                'created_by': uid,
                                'about_me_text': about.isEmpty ? null : about,
                              })
                              .select('id')
                              .maybeSingle();

                          createdLegacyId = (inserted?['id'] ?? '')
                              .toString()
                              .trim();
                        } else {
                          final legacyId = await _supabase.rpc(
                            'create_legacy_relative',
                            params: {
                              'p_family_id': widget.familyId,
                              'p_anchor_type': childRef.type,
                              'p_anchor_id': childRef.id,
                              'p_relation': 'parent',
                              'p_name': name,
                              'p_display_name': displayName.isEmpty
                                  ? null
                                  : displayName,
                              'p_birth_year': birthYear,
                              'p_death_year': deathYear,
                              'p_about_me_text': about.isEmpty ? null : about,
                            },
                          );

                          createdLegacyId = (legacyId ?? '').toString().trim();

                          if (createdLegacyId.isNotEmpty &&
                              slotKey != null &&
                              slotKey.trim().isNotEmpty) {
                            await _supabase
                                .from('legacy_family_members')
                                .update({'slot_key': slotKey})
                                .eq('id', createdLegacyId);
                          }
                        }

                        if (createdLegacyId.isEmpty) {
                          throw Exception('Failed to create legacy ancestor.');
                        }

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

  Future<void> _showLegacyDescendantDialog({
    _NodeRef? parentRef,
    required String title,
    String? slotKey,
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
          insetPadding: _legacyDialogInsetPadding(ctx),
          title: Text('Add legacy $title'),
          content: _legacyDialogContent(
            ctx,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a family-owned descendant profile and link it as a child in this branch.',
                  style: TextStyle(color: Colors.black.withOpacity(0.65)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: displayNameController,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: birthYearController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
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
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text(
                    'Optional extra details',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    TextField(
                      controller: deathYearController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: const InputDecoration(
                        labelText: 'Death year (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
              ],
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

                      if (name.isEmpty) {
                        setInner(() => errorText = 'Name is required.');
                        return;
                      }

                      if (birthYearController.text.trim().isNotEmpty &&
                          birthYear == null) {
                        setInner(
                          () =>
                              errorText = 'Birth year must be a valid number.',
                        );
                        return;
                      }

                      if (deathYearController.text.trim().isNotEmpty &&
                          deathYear == null) {
                        setInner(
                          () =>
                              errorText = 'Death year must be a valid number.',
                        );
                        return;
                      }

                      setInner(() {
                        saving = true;
                        errorText = null;
                      });

                      try {
                        String createdLegacyId = '';

                        if (parentRef == null) {
                          final uid = _supabase.auth.currentUser?.id;
                          if (uid == null || uid.trim().isEmpty) {
                            throw Exception(
                              'You must be signed in to create a legacy descendant.',
                            );
                          }

                          final inserted = await _supabase
                              .from('legacy_family_members')
                              .insert({
                                'family_id': widget.familyId,
                                'slot_key': slotKey,
                                'name': name,
                                'display_name': displayName.isEmpty
                                    ? null
                                    : displayName,
                                'birth_year': birthYear,
                                'death_year': deathYear,
                                'created_by': uid,
                                'about_me_text': about.isEmpty ? null : about,
                              })
                              .select('id')
                              .maybeSingle();

                          createdLegacyId = (inserted?['id'] ?? '')
                              .toString()
                              .trim();
                        } else {
                          final legacyId = await _supabase.rpc(
                            'create_legacy_relative',
                            params: {
                              'p_family_id': widget.familyId,
                              'p_anchor_type': parentRef.type,
                              'p_anchor_id': parentRef.id,
                              'p_relation': 'child',
                              'p_name': name,
                              'p_display_name': displayName.isEmpty
                                  ? null
                                  : displayName,
                              'p_birth_year': birthYear,
                              'p_death_year': deathYear,
                              'p_about_me_text': about.isEmpty ? null : about,
                            },
                          );

                          createdLegacyId = (legacyId ?? '').toString().trim();

                          if (createdLegacyId.isNotEmpty &&
                              slotKey != null &&
                              slotKey.trim().isNotEmpty) {
                            await _supabase
                                .from('legacy_family_members')
                                .update({'slot_key': slotKey})
                                .eq('id', createdLegacyId);
                          }
                        }

                        if (createdLegacyId.isEmpty) {
                          throw Exception(
                            'Failed to create legacy descendant.',
                          );
                        }

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
    _NodeRef? childRef,
    required String title,
    String? slotKey,
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
                subtitle: const Text(
                  'Create an invite linked as a parent here',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _createAncestorInvite(
                    childRef: childRef,
                    title: title,
                    slotKey: slotKey,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy predecessor'),
                subtitle: const Text(
                  'Create a family-owned ancestor profile here',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLegacyAncestorDialog(
                    childRef: childRef,
                    title: title,
                    slotKey: slotKey,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDescendantAddOptions({
    _NodeRef? parentRef,
    required String title,
    String? slotKey,
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
                'Choose whether to invite a living relative or add a legacy descendant profile for this branch.',
                style: TextStyle(color: Colors.black.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1),
                ),
                title: const Text('Invite relative'),
                subtitle: const Text('Create an invite linked as a child here'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createDescendantInvite(
                    parentRef: parentRef,
                    title: title,
                    slotKey: slotKey,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy descendant'),
                subtitle: const Text(
                  'Create a family-owned descendant profile here',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLegacyDescendantDialog(
                    parentRef: parentRef,
                    title: title,
                    slotKey: slotKey,
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
    return FutureBuilder<_AncestorViewModel>(
      future: _buildAncestorViewModel(),
      builder: (context, snapshot) {
        final model = snapshot.data;

        if (model == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final rootPerson = model.focusPerson;
        final generations = model.generations;

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
                          label: _personLabel(rootPerson, model.focusFallback),
                          avatarUrl: _avatarFor(rootPerson),
                          onTap: rootPerson == null
                              ? null
                              : () async {
                                  await _openPerson(rootPerson);
                                },
                          onBranchTap: null,
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
                              final person = node.ref == null
                                  ? null
                                  : _personForNode(node.ref!);

                              if (person == null) {
                                return _MiniBranchAddCard(
                                  label: 'Add ancestor',
                                  onTap:
                                      (node.childRefForAdd == null &&
                                          (node.slotKeyForAdd == null ||
                                              node.slotKeyForAdd!
                                                  .trim()
                                                  .isEmpty))
                                      ? null
                                      : () => _openAncestorAddOptions(
                                          childRef: node.childRefForAdd,
                                          title: 'Ancestor',
                                          slotKey: node.slotKeyForAdd,
                                        ),
                                );
                              }

                              return _MiniBranchCard(
                                label: _personLabel(person, 'Ancestor'),
                                avatarUrl: _avatarFor(person),
                                onTap: () async {
                                  await _openPerson(person);
                                },
                                onBranchTap: () => _openAncestorBranchForPerson(
                                  person,
                                  fallbackLabel: 'Ancestor',
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDescendantRelationshipView() {
    return FutureBuilder<_DescendantViewModel>(
      future: _buildDescendantViewModel(),
      builder: (context, snapshot) {
        final model = snapshot.data;

        if (model == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final rootPerson = model.focusPerson;
        final generations = model.generations;

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
                              ? 'Descendant branch'
                              : '${widget.rootLabel} branch',
                          subtitle:
                              'This branch focuses on one descendant line.',
                        ),
                        const SizedBox(height: 16),
                        _BranchPersonCard(
                          title: 'Branch focus',
                          label: _personLabel(rootPerson, model.focusFallback),
                          avatarUrl: _avatarFor(rootPerson),
                          onTap: rootPerson == null
                              ? null
                              : () async {
                                  await _openPerson(rootPerson);
                                },
                          onBranchTap: null,
                        ),
                        for (final generation in generations) ...[
                          const SizedBox(height: 22),
                          _BranchSectionTitle(
                            title: _descendantGenerationTitle(generation.depth),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: generation.nodes.map((node) {
                              final person = node.ref == null
                                  ? null
                                  : _personForNode(node.ref!);

                              if (person == null) {
                                return _MiniBranchAddCard(
                                  label: 'Add descendant',
                                  onTap:
                                      (node.parentRefForAdd == null &&
                                          (node.slotKeyForAdd == null ||
                                              node.slotKeyForAdd!
                                                  .trim()
                                                  .isEmpty))
                                      ? null
                                      : () => _openDescendantAddOptions(
                                          parentRef: node.parentRefForAdd,
                                          title: 'Descendant',
                                          slotKey: node.slotKeyForAdd,
                                        ),
                                );
                              }

                              return _MiniBranchCard(
                                label: _personLabel(person, 'Descendant'),
                                avatarUrl: _avatarFor(person),
                                onTap: () async {
                                  await _openPerson(person);
                                },
                                onBranchTap: () async {
                                  final isLegacy = person['__legacy'] == true;
                                  final personId = (person['id'] ?? '')
                                      .toString()
                                      .trim();

                                  final personRef = _nodeRefFromPerson(person);
                                  if (personRef == null) return;

                                  final nextSlotKey = _slotHintForNode(
                                    personRef,
                                  );
                                  if (nextSlotKey.isEmpty) return;

                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FamilyBranchScreen(
                                        familyId: widget.familyId,
                                        rootLabel: _personLabel(
                                          person,
                                          'Descendant',
                                        ),
                                        rootSlotKey: nextSlotKey,
                                        direction: 'descendant',
                                        rootNodeType: isLegacy
                                            ? 'legacy'
                                            : 'vault',
                                        rootNodeId: personId.isEmpty
                                            ? null
                                            : personId,
                                      ),
                                    ),
                                  );
                                  await _load();
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _requiredSlotForPerson(Map<String, dynamic> person) {
    final ref = _nodeRefFromPerson(person);
    if (ref == null) return '';
    return _slotHintForNode(ref);
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
          IconButton(
            tooltip: 'Back to family tree',
            onPressed: _exitToFamilyTree,
            icon: const Icon(Icons.exit_to_app),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : isAncestor
          ? _buildAncestorRelationshipView()
          : _buildDescendantRelationshipView(),
    );
  }
}

class _AncestorViewModel {
  final Map<String, dynamic>? focusPerson;
  final String focusFallback;
  final List<_AncestorGeneration> generations;

  const _AncestorViewModel({
    required this.focusPerson,
    required this.focusFallback,
    required this.generations,
  });
}

class _DescendantViewModel {
  final Map<String, dynamic>? focusPerson;
  final String focusFallback;
  final List<_DescendantGeneration> generations;

  const _DescendantViewModel({
    required this.focusPerson,
    required this.focusFallback,
    required this.generations,
  });
}

class _BranchIntroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _BranchIntroCard({required this.title, required this.subtitle});

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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
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
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BranchPersonCard extends StatelessWidget {
  final String title;
  final String label;
  final String? avatarUrl;
  final VoidCallback? onTap;
  final VoidCallback? onBranchTap;

  const _BranchPersonCard({
    required this.title,
    required this.label,
    required this.avatarUrl,
    required this.onTap,
    required this.onBranchTap,
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
                if (onBranchTap != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onBranchTap,
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                    label: const Text('Open branch'),
                  ),
                ],
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
  final VoidCallback? onBranchTap;

  const _MiniBranchCard({
    required this.label,
    required this.avatarUrl,
    required this.onTap,
    required this.onBranchTap,
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
              if (onBranchTap != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onBranchTap,
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('Branch'),
                ),
              ],
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

  const _MiniBranchAddCard({required this.label, required this.onTap});

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
                child: Icon(Icons.add, color: Colors.black.withOpacity(0.65)),
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

  const _BranchAvatar({required this.url, required this.radius});

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
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

class _NodeRef {
  final String type;
  final String id;

  const _NodeRef({required this.type, required this.id});
}

class _AncestorBranchNode {
  final _NodeRef? ref;
  final _NodeRef? childRefForAdd;
  final String? slotKeyForAdd;

  const _AncestorBranchNode({
    required this.ref,
    this.childRefForAdd,
    this.slotKeyForAdd,
  });
}

class _DescendantBranchNode {
  final _NodeRef? ref;
  final _NodeRef? parentRefForAdd;
  final String? slotKeyForAdd;

  const _DescendantBranchNode({
    required this.ref,
    this.parentRefForAdd,
    this.slotKeyForAdd,
  });
}

class _AncestorGeneration {
  final int depth;
  final List<_AncestorBranchNode> nodes;

  const _AncestorGeneration({required this.depth, required this.nodes});
}

class _DescendantGeneration {
  final int depth;
  final List<_DescendantBranchNode> nodes;

  const _DescendantGeneration({required this.depth, required this.nodes});
}
