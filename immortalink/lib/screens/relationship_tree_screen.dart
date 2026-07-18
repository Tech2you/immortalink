import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_vault_screen.dart';
import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';
import 'vaults_screen.dart';

enum _RelativeKind { parent, spouse, sibling, child }

class RelationshipTreeScreen extends StatefulWidget {
  final String familyId;

  const RelationshipTreeScreen({super.key, required this.familyId});

  @override
  State<RelationshipTreeScreen> createState() => _RelationshipTreeScreenState();
}

class _RelationshipTreeScreenState extends State<RelationshipTreeScreen> {
  final _supabase = Supabase.instance.client;
  final _transformController = TransformationController();

  static const _logoPath = 'assets/images/immortalink_logo.png';
  static const _vaultAvatarBucket = 'avatars';
  static const _legacyAvatarBucket = 'vault_photos';

  bool _loading = true;
  String? _error;
  List<_TreePerson> _people = [];
  List<_TreeRelationship> _relationships = [];
  _TreePerson? _viewer;
  _TreePerson? _focus;
  final List<_TreePerson> _focusHistory = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<String?> _signedUrl(String bucket, String path) async {
    if (path.trim().isEmpty) return null;
    try {
      return await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({String? keepFocusKey}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('vaults')
            .select('id, name, display_name, owner_id, family_id, avatar_path')
            .eq('family_id', widget.familyId),
        _supabase
            .from('family_members')
            .select('user_id, slot_key, role')
            .eq('family_id', widget.familyId),
        _supabase
            .from('legacy_family_members')
            .select(
              'id, family_id, slot_key, name, display_name, avatar_path, replaced_by_vault_id',
            )
            .eq('family_id', widget.familyId),
        _supabase
            .from('family_relationships')
            .select(
              'id, parent_type, parent_id, child_type, child_id, relationship_kind, created_at',
            )
            .eq('family_id', widget.familyId)
            .order('created_at', ascending: true),
      ]);

      final vaultRows = (results[0] as List).cast<Map<String, dynamic>>();
      final memberRows = (results[1] as List).cast<Map<String, dynamic>>();
      final legacyRows = (results[2] as List).cast<Map<String, dynamic>>();
      final relationshipRows = (results[3] as List)
          .cast<Map<String, dynamic>>();

      final slotByUser = <String, String?>{};
      for (final row in memberRows) {
        final userId = (row['user_id'] ?? '').toString().trim();
        if (userId.isEmpty) continue;
        final slot = (row['slot_key'] ?? '').toString().trim();
        slotByUser[userId] = slot.isEmpty ? null : slot;
      }

      final people = <_TreePerson>[];
      for (final row in vaultRows) {
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final ownerId = (row['owner_id'] ?? '').toString().trim();
        final avatarPath = (row['avatar_path'] ?? '').toString().trim();
        people.add(
          _TreePerson(
            type: 'vault',
            id: id,
            name: _nameFromRow(row, 'Family member'),
            ownerId: ownerId.isEmpty ? null : ownerId,
            slotKey: slotByUser[ownerId],
            avatarUrl: await _signedUrl(_vaultAvatarBucket, avatarPath),
            isPlaceholder: false,
          ),
        );
      }

      for (final row in legacyRows) {
        final replaced = (row['replaced_by_vault_id'] ?? '').toString().trim();
        if (replaced.isNotEmpty) continue;
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final name = _nameFromRow(row, 'Legacy family member');
        final avatarPath = (row['avatar_path'] ?? '').toString().trim();
        people.add(
          _TreePerson(
            type: 'legacy',
            id: id,
            name: name,
            ownerId: null,
            slotKey: (row['slot_key'] ?? '').toString().trim(),
            avatarUrl: await _signedUrl(_legacyAvatarBucket, avatarPath),
            isPlaceholder: name.toLowerCase() == 'parent not added yet',
          ),
        );
      }

      final peopleByKey = {for (final person in people) person.key: person};
      final relationships = <_TreeRelationship>[];
      for (final row in relationshipRows) {
        final aKey =
            '${(row['parent_type'] ?? '').toString()}:${(row['parent_id'] ?? '').toString()}';
        final bKey =
            '${(row['child_type'] ?? '').toString()}:${(row['child_id'] ?? '').toString()}';
        if (!peopleByKey.containsKey(aKey) || !peopleByKey.containsKey(bKey)) {
          continue;
        }
        relationships.add(
          _TreeRelationship(
            firstKey: aKey,
            secondKey: bKey,
            kind: (row['relationship_kind'] ?? '').toString().trim(),
          ),
        );
      }

      final uid = _supabase.auth.currentUser?.id;
      final viewer = uid == null
          ? null
          : people.where((person) => person.ownerId == uid).firstOrNull;
      final wantedFocus = keepFocusKey ?? _focus?.key;
      final focus = wantedFocus == null
          ? viewer
          : peopleByKey[wantedFocus] ?? viewer;

      if (!mounted) return;
      setState(() {
        _people = people;
        _relationships = relationships;
        _viewer = viewer;
        _focus = focus ?? (people.isEmpty ? null : people.first);
        if (_focusHistory.isEmpty && _focus != null) {
          _focusHistory.add(_focus!);
        } else {
          for (int i = 0; i < _focusHistory.length; i++) {
            final refreshed = peopleByKey[_focusHistory[i].key];
            if (refreshed != null) _focusHistory[i] = refreshed;
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _nameFromRow(Map<String, dynamic> row, String fallback) {
    final displayName = (row['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
    final name = (row['name'] ?? '').toString().trim();
    return name.isEmpty ? fallback : name;
  }

  _TreePerson? _person(String key) {
    for (final person in _people) {
      if (person.key == key) return person;
    }
    return null;
  }

  List<_TreePerson> _parentsOf(_TreePerson person) {
    final result = <_TreePerson>[];
    for (final relationship in _relationships) {
      if (relationship.kind != 'parent_child' ||
          relationship.secondKey != person.key) {
        continue;
      }
      final parent = _person(relationship.firstKey);
      if (parent != null) result.add(parent);
    }
    return _sortedUnique(result);
  }

  List<_TreePerson> _childrenOf(_TreePerson person) {
    final result = <_TreePerson>[];
    for (final relationship in _relationships) {
      if (relationship.kind != 'parent_child' ||
          relationship.firstKey != person.key) {
        continue;
      }
      final child = _person(relationship.secondKey);
      if (child != null) result.add(child);
    }
    return _sortedUnique(result);
  }

  List<_TreePerson> _spousesOf(_TreePerson person) {
    final result = <_TreePerson>[];
    for (final relationship in _relationships) {
      if (relationship.kind != 'spouse') continue;
      if (relationship.firstKey == person.key) {
        final spouse = _person(relationship.secondKey);
        if (spouse != null) result.add(spouse);
      } else if (relationship.secondKey == person.key) {
        final spouse = _person(relationship.firstKey);
        if (spouse != null) result.add(spouse);
      }
    }
    return _sortedUnique(result);
  }

  List<_TreePerson> _siblingsOf(_TreePerson person) {
    final result = <_TreePerson>[];
    for (final parent in _parentsOf(person)) {
      for (final child in _childrenOf(parent)) {
        if (child.key != person.key) result.add(child);
      }
    }
    for (final relationship in _relationships) {
      if (relationship.kind != 'sibling') continue;
      if (relationship.firstKey == person.key) {
        final sibling = _person(relationship.secondKey);
        if (sibling != null) result.add(sibling);
      } else if (relationship.secondKey == person.key) {
        final sibling = _person(relationship.firstKey);
        if (sibling != null) result.add(sibling);
      }
    }
    return _sortedUnique(result);
  }

  List<_TreePerson> _sortedUnique(List<_TreePerson> input) {
    final byKey = <String, _TreePerson>{};
    for (final person in input) {
      byKey[person.key] = person;
    }
    final result = byKey.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  void _focusOn(_TreePerson person) {
    setState(() {
      _focus = person;
      final existingIndex = _focusHistory.indexWhere(
        (entry) => entry.key == person.key,
      );
      if (existingIndex >= 0) {
        _focusHistory.removeRange(existingIndex + 1, _focusHistory.length);
      } else {
        _focusHistory.add(person);
      }
    });
    _transformController.value = Matrix4.identity();
  }

  void _focusFromBreadcrumb(int index) {
    if (index < 0 || index >= _focusHistory.length) return;
    final person = _focusHistory[index];
    setState(() {
      _focus = person;
      _focusHistory.removeRange(index + 1, _focusHistory.length);
    });
    _transformController.value = Matrix4.identity();
  }

  void _returnToViewer() {
    final viewer = _viewer;
    if (viewer == null) return;
    setState(() {
      _focus = viewer;
      _focusHistory
        ..clear()
        ..add(viewer);
    });
    _transformController.value = Matrix4.identity();
  }

  Future<void> _leaveFamily() async {
    final viewer = _viewer;
    final focus = _focus;
    if (viewer == null || focus?.key != viewer.key) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave family?'),
        content: const Text(
          'This removes your account and vault from this family tree. You can join a family again later with an invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave family'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.rpc(
        'leave_family',
        params: {'p_family_id': widget.familyId},
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VaultsScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not leave family: $e')));
    }
  }

  Future<void> _openPerson(_TreePerson person) async {
    if (person.isLegacy) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LegacyVaultScreen(
            legacyMemberId: person.id,
            familyId: widget.familyId,
          ),
        ),
      );
    } else {
      final isOwner = person.ownerId == _supabase.auth.currentUser?.id;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isOwner
              ? VaultHomeScreen(vaultId: person.id, vaultName: person.name)
              : VaultReadOnlyScreen(vaultId: person.id, vaultName: person.name),
        ),
      );
    }
    await _load(keepFocusKey: person.key);
  }

  String _kindLabel(_RelativeKind kind) => switch (kind) {
    _RelativeKind.parent => 'parent',
    _RelativeKind.spouse => 'spouse',
    _RelativeKind.sibling => 'sibling',
    _RelativeKind.child => 'child',
  };

  Future<void> _showAddOptions(_RelativeKind kind) async {
    final focus = _focus;
    if (focus == null) return;
    final label = _kindLabel(kind);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add $label to ${focus.name}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose whether to invite them or create a family-owned legacy profile.',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1),
                ),
                title: const Text('Invite relative'),
                subtitle: const Text('Create and copy an invite code'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _createInvite(kind, focus);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy relative'),
                subtitle: const Text('Create a profile without an account'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showLegacyDialog(kind, focus);
                },
              ),
              if (kind == _RelativeKind.child)
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.account_tree_outlined),
                  ),
                  title: const Text('Add grandchild with missing parent'),
                  subtitle: const Text(
                    'Creates a visible “Parent not added yet” placeholder',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showMissingParentGrandchildOptions(focus);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _inviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<_TreePerson> _ensureSiblingParent(_TreePerson focus) async {
    final parents = _parentsOf(focus);
    if (parents.isNotEmpty) return parents.first;

    final id = await _supabase.rpc(
      'create_legacy_relative',
      params: {
        'p_family_id': widget.familyId,
        'p_anchor_type': focus.type,
        'p_anchor_id': focus.id,
        'p_relation': 'parent',
        'p_name': 'Parent not added yet',
        'p_display_name': 'Parent not added yet',
        'p_birth_year': null,
        'p_death_year': null,
        'p_about_me_text':
            'Placeholder created to preserve a sibling relationship.',
      },
    );
    final placeholderId = (id ?? '').toString().trim();
    if (placeholderId.isEmpty) {
      throw Exception('Could not create the missing-parent placeholder.');
    }
    return _TreePerson(
      type: 'legacy',
      id: placeholderId,
      name: 'Parent not added yet',
      ownerId: null,
      slotKey: null,
      avatarUrl: null,
      isPlaceholder: true,
    );
  }

  Future<void> _createInvite(_RelativeKind kind, _TreePerson focus) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final code = _inviteCode();
      final expiresAt = DateTime.now().add(const Duration(days: 7)).toUtc();
      final viewerVaultId = _viewer?.id;
      if (viewerVaultId == null) {
        throw Exception('You need your own vault before inviting relatives.');
      }

      final inserted = await _supabase
          .from('family_invites')
          .insert({
            'family_id': widget.familyId,
            'created_by': user.id,
            'invite_code': code,
            'slot_key': null,
            'expires_at': expiresAt.toIso8601String(),
            'inviter_vault_id': viewerVaultId,
          })
          .select('id')
          .maybeSingle();

      final inviteId = (inserted?['id'] ?? '').toString().trim();
      if (inviteId.isEmpty) throw Exception('The invite could not be created.');

      late String firstType;
      late String firstId;
      late String secondType;
      late String secondId;
      var relationshipKind = 'parent_child';

      switch (kind) {
        case _RelativeKind.parent:
          firstType = 'invite';
          firstId = inviteId;
          secondType = focus.type;
          secondId = focus.id;
        case _RelativeKind.child:
          firstType = focus.type;
          firstId = focus.id;
          secondType = 'invite';
          secondId = inviteId;
        case _RelativeKind.spouse:
          firstType = focus.type;
          firstId = focus.id;
          secondType = 'invite';
          secondId = inviteId;
          relationshipKind = 'spouse';
        case _RelativeKind.sibling:
          final parent = await _ensureSiblingParent(focus);
          firstType = parent.type;
          firstId = parent.id;
          secondType = 'invite';
          secondId = inviteId;
      }

      await _supabase.from('family_relationships').insert({
        'family_id': widget.familyId,
        'parent_type': firstType,
        'parent_id': firstId,
        'child_type': secondType,
        'child_id': secondId,
        'relationship_kind': relationshipKind,
      });

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Invite ${_kindLabel(kind)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share this invite code:'),
              const SizedBox(height: 8),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text('Expires ${expiresAt.toLocal()}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await _load(keepFocusKey: focus.key);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create invite: $e')));
    }
  }

  Future<void> _showLegacyDialog(
    _RelativeKind kind,
    _TreePerson focus, {
    bool grandchildWithMissingParent = false,
  }) async {
    final nameController = TextEditingController();
    final displayNameController = TextEditingController();
    final birthYearController = TextEditingController();
    final deathYearController = TextEditingController();
    final aboutController = TextEditingController();
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            grandchildWithMissingParent
                ? 'Add legacy grandchild'
                : 'Add legacy ${_kindLabel(kind)}',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: birthYearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Birth year',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: deathYearController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Death year',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aboutController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'About / notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final birthYear = int.tryParse(
                        birthYearController.text.trim(),
                      );
                      final deathYear = int.tryParse(
                        deathYearController.text.trim(),
                      );
                      if (name.isEmpty) {
                        setDialogState(() => error = 'Name is required.');
                        return;
                      }
                      if (birthYearController.text.trim().isNotEmpty &&
                          birthYear == null) {
                        setDialogState(
                          () => error = 'Birth year must be a number.',
                        );
                        return;
                      }
                      if (deathYearController.text.trim().isNotEmpty &&
                          deathYear == null) {
                        setDialogState(
                          () => error = 'Death year must be a number.',
                        );
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                        error = null;
                      });

                      try {
                        var anchor = focus;
                        if (grandchildWithMissingParent) {
                          anchor = await _createMissingParentPlaceholder(focus);
                        }
                        await _supabase.rpc(
                          'create_legacy_relative',
                          params: {
                            'p_family_id': widget.familyId,
                            'p_anchor_type': anchor.type,
                            'p_anchor_id': anchor.id,
                            'p_relation': _kindLabel(kind),
                            'p_name': name,
                            'p_display_name':
                                displayNameController.text.trim().isEmpty
                                ? null
                                : displayNameController.text.trim(),
                            'p_birth_year': birthYear,
                            'p_death_year': deathYear,
                            'p_about_me_text':
                                aboutController.text.trim().isEmpty
                                ? null
                                : aboutController.text.trim(),
                          },
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _load(keepFocusKey: focus.key);
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString();
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

  Future<_TreePerson> _createMissingParentPlaceholder(_TreePerson focus) async {
    final id = await _supabase.rpc(
      'create_legacy_relative',
      params: {
        'p_family_id': widget.familyId,
        'p_anchor_type': focus.type,
        'p_anchor_id': focus.id,
        'p_relation': 'child',
        'p_name': 'Parent not added yet',
        'p_display_name': 'Parent not added yet',
        'p_birth_year': null,
        'p_death_year': null,
        'p_about_me_text':
            'Placeholder created because a descendant was added first.',
      },
    );
    final placeholderId = (id ?? '').toString().trim();
    if (placeholderId.isEmpty) {
      throw Exception('Could not create the parent placeholder.');
    }
    return _TreePerson(
      type: 'legacy',
      id: placeholderId,
      name: 'Parent not added yet',
      ownerId: null,
      slotKey: null,
      avatarUrl: null,
      isPlaceholder: true,
    );
  }

  Future<void> _showMissingParentGrandchildOptions(_TreePerson focus) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add grandchild with missing parent',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'A visible parent placeholder will preserve the family line. You can replace it later.',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1),
                ),
                title: const Text('Invite grandchild'),
                subtitle: const Text(
                  'Create the placeholder and an invite code',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    final placeholder = await _createMissingParentPlaceholder(
                      focus,
                    );
                    await _createInvite(_RelativeKind.child, placeholder);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not create invite: $e')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy grandchild'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showLegacyDialog(
                    _RelativeKind.child,
                    focus,
                    grandchildWithMissingParent: true,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  _CanvasModel _canvasModel(_TreePerson focus) {
    final parents = _parentsOf(focus);
    final spouses = _spousesOf(focus);
    final siblings = _siblingsOf(focus);
    final children = _childrenOf(focus);

    final widestRow = max(parents.length + 1, children.length + 1);
    final sideCount = siblings.length + spouses.length + 2;
    final width = max(1700.0, max(widestRow * 190.0, sideCount * 180.0 + 500));
    const height = 1500.0;
    final center = Offset(width / 2, 720);
    final bubbles = <_BubbleSpec>[];

    void addCenteredRow(
      List<_TreePerson> people,
      _RelativeKind kind,
      double y,
    ) {
      final count = people.length + 1;
      const gap = 185.0;
      final startX = center.dx - ((count - 1) * gap / 2);
      for (int i = 0; i < people.length; i++) {
        bubbles.add(
          _BubbleSpec.person(people[i], kind, Offset(startX + i * gap, y)),
        );
      }
      bubbles.add(
        _BubbleSpec.add(kind, Offset(startX + people.length * gap, y)),
      );
    }

    addCenteredRow(parents, _RelativeKind.parent, 300);
    addCenteredRow(children, _RelativeKind.child, 1140);

    for (int i = 0; i < siblings.length; i++) {
      bubbles.add(
        _BubbleSpec.person(
          siblings[i],
          _RelativeKind.sibling,
          Offset(center.dx - 260 - i * 175, 720),
        ),
      );
    }
    bubbles.add(
      _BubbleSpec.add(
        _RelativeKind.sibling,
        Offset(center.dx - 260 - siblings.length * 175, 720),
      ),
    );

    for (int i = 0; i < spouses.length; i++) {
      bubbles.add(
        _BubbleSpec.person(
          spouses[i],
          _RelativeKind.spouse,
          Offset(center.dx + 260 + i * 175, 720),
        ),
      );
    }
    bubbles.add(
      _BubbleSpec.add(
        _RelativeKind.spouse,
        Offset(center.dx + 260 + spouses.length * 175, 720),
      ),
    );

    return _CanvasModel(
      size: Size(width, height),
      focusCenter: center,
      bubbles: bubbles,
    );
  }

  @override
  Widget build(BuildContext context) {
    final focus = _focus;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Family Tree'),
        actions: [
          IconButton(
            tooltip: 'Return to my branch',
            onPressed: _viewer == null ? null : _returnToViewer,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(keepFocusKey: focus?.key),
            icon: const Icon(Icons.refresh),
          ),
          if (_viewer != null && focus?.key == _viewer!.key)
            IconButton(
              tooltip: 'Leave family',
              onPressed: _leaveFamily,
              icon: const Icon(Icons.group_remove_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : focus == null
          ? const Center(child: Text('No family members found.'))
          : _buildCanvas(focus),
    );
  }

  Widget _buildCanvas(_TreePerson focus) {
    final model = _canvasModel(focus);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(child: Container(color: const Color(0xFFF9F4FB))),
          InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(800),
            minScale: 0.3,
            maxScale: 2.4,
            child: SizedBox(
              width: model.size.width,
              height: model.size.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.045,
                      child: Image.asset(_logoPath, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RelationshipLinesPainter(model: model),
                    ),
                  ),
                  _sectionLabel('Parents', model.focusCenter.dx, 145),
                  _sectionLabel('Siblings', model.focusCenter.dx - 360, 540),
                  _sectionLabel('Spouses', model.focusCenter.dx + 360, 540),
                  _sectionLabel('Children', model.focusCenter.dx, 985),
                  Positioned(
                    left: model.focusCenter.dx - 95,
                    top: model.focusCenter.dy - 75,
                    child: _PersonBubble(
                      person: focus,
                      focused: true,
                      onTap: () {},
                      onOpen: () => _openPerson(focus),
                    ),
                  ),
                  for (final bubble in model.bubbles)
                    Positioned(
                      left: bubble.center.dx - 80,
                      top: bubble.center.dy - 58,
                      child: bubble.person == null
                          ? _AddBubble(
                              label: 'Add ${_kindLabel(bubble.kind)}',
                              onTap: () => _showAddOptions(bubble.kind),
                            )
                          : _PersonBubble(
                              person: bubble.person!,
                              focused: false,
                              onTap: () => _focusOn(bubble.person!),
                              onOpen: () => _openPerson(bubble.person!),
                            ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: Center(child: _buildBreadcrumbs()),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pan_tool_alt_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Drag to explore • Tap a person to follow their branch',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 14,
            child: AnimatedBuilder(
              animation: _transformController,
              builder: (context, _) => _TreeMiniMap(
                model: model,
                transform: _transformController.value,
                viewportSize: Size(constraints.maxWidth, constraints.maxHeight),
                onNavigate: (canvasPoint) {
                  final scale = _transformController.value.getMaxScaleOnAxis();
                  final safeScale = scale <= 0 ? 1.0 : scale;
                  final targetX =
                      constraints.maxWidth / 2 - canvasPoint.dx * safeScale;
                  final targetY =
                      constraints.maxHeight / 2 - canvasPoint.dy * safeScale;
                  final next = Matrix4.identity()
                    ..translateByDouble(targetX, targetY, 0, 1)
                    ..scaleByDouble(safeScale, safeScale, 1, 1);
                  _transformController.value = next;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        elevation: 3,
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _focusHistory.length; i++) ...[
                if (i > 0)
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                TextButton.icon(
                  onPressed: () => _focusFromBreadcrumb(i),
                  icon: Icon(
                    i == _focusHistory.length - 1
                        ? Icons.account_tree
                        : Icons.person_outline,
                    size: 16,
                  ),
                  label: Text(_focusHistory[i].name),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, double centerX, double top) {
    return Positioned(
      left: centerX - 90,
      top: top,
      width: 180,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TreePerson {
  final String type;
  final String id;
  final String name;
  final String? ownerId;
  final String? slotKey;
  final String? avatarUrl;
  final bool isPlaceholder;

  const _TreePerson({
    required this.type,
    required this.id,
    required this.name,
    required this.ownerId,
    required this.slotKey,
    required this.avatarUrl,
    required this.isPlaceholder,
  });

  String get key => '$type:$id';
  bool get isLegacy => type == 'legacy';
}

class _TreeRelationship {
  final String firstKey;
  final String secondKey;
  final String kind;

  const _TreeRelationship({
    required this.firstKey,
    required this.secondKey,
    required this.kind,
  });
}

class _BubbleSpec {
  final _TreePerson? person;
  final _RelativeKind kind;
  final Offset center;

  const _BubbleSpec.person(this.person, this.kind, this.center);
  const _BubbleSpec.add(this.kind, this.center) : person = null;
}

class _CanvasModel {
  final Size size;
  final Offset focusCenter;
  final List<_BubbleSpec> bubbles;

  const _CanvasModel({
    required this.size,
    required this.focusCenter,
    required this.bubbles,
  });
}

class _RelationshipLinesPainter extends CustomPainter {
  final _CanvasModel model;

  const _RelationshipLinesPainter({required this.model});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7B5B8E).withValues(alpha: 0.42)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final bubble in model.bubbles) {
      if (bubble.person == null) continue;
      final path = Path()..moveTo(model.focusCenter.dx, model.focusCenter.dy);
      final midpointY = (model.focusCenter.dy + bubble.center.dy) / 2;
      path.cubicTo(
        model.focusCenter.dx,
        midpointY,
        bubble.center.dx,
        midpointY,
        bubble.center.dx,
        bubble.center.dy,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RelationshipLinesPainter oldDelegate) =>
      oldDelegate.model != model;
}

class _PersonBubble extends StatelessWidget {
  final _TreePerson person;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _PersonBubble({
    required this.person,
    required this.focused,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: person.isPlaceholder
          ? const Color(0xFFFFF3D6)
          : focused
          ? const Color(0xFFEADCF2)
          : Colors.white,
      elevation: focused ? 8 : 3,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: SizedBox(
          width: focused ? 190 : 160,
          height: focused ? 150 : 116,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: focused ? 31 : 24,
                        backgroundImage: person.avatarUrl == null
                            ? null
                            : NetworkImage(person.avatarUrl!),
                        child: person.avatarUrl == null
                            ? Icon(
                                person.isPlaceholder
                                    ? Icons.help_outline
                                    : Icons.person_outline,
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        person.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: person.isPlaceholder
                              ? const Color(0xFF7A5410)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open ${person.name}\'s vault',
                  onPressed: onOpen,
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddBubble extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddBubble({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        minimumSize: const Size(160, 92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}

class _TreeMiniMap extends StatelessWidget {
  final _CanvasModel model;
  final Matrix4 transform;
  final Size viewportSize;
  final ValueChanged<Offset> onNavigate;

  const _TreeMiniMap({
    required this.model,
    required this.transform,
    required this.viewportSize,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    const mapSize = Size(210, 140);
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 5,
      borderRadius: BorderRadius.circular(16),
      child: Tooltip(
        message: 'Family overview — tap to move',
        child: GestureDetector(
          onTapDown: (details) {
            final scale = min(
              mapSize.width / model.size.width,
              mapSize.height / model.size.height,
            );
            final drawnWidth = model.size.width * scale;
            final drawnHeight = model.size.height * scale;
            final offset = Offset(
              (mapSize.width - drawnWidth) / 2,
              (mapSize.height - drawnHeight) / 2,
            );
            final canvasPoint = Offset(
              (details.localPosition.dx - offset.dx) / scale,
              (details.localPosition.dy - offset.dy) / scale,
            );
            onNavigate(canvasPoint);
          },
          child: SizedBox(
            width: mapSize.width,
            height: mapSize.height,
            child: CustomPaint(
              painter: _MiniMapPainter(
                model: model,
                transform: transform,
                viewportSize: viewportSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final _CanvasModel model;
  final Matrix4 transform;
  final Size viewportSize;

  const _MiniMapPainter({
    required this.model,
    required this.transform,
    required this.viewportSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mapScale = min(
      size.width / model.size.width,
      size.height / model.size.height,
    );
    final offset = Offset(
      (size.width - model.size.width * mapScale) / 2,
      (size.height - model.size.height * mapScale) / 2,
    );

    Offset mapPoint(Offset point) => offset + point * mapScale;

    final linePaint = Paint()
      ..color = const Color(0xFF9A7AAA).withValues(alpha: 0.42)
      ..strokeWidth = 1;
    final personPaint = Paint()..color = const Color(0xFF7B5B8E);
    final addPaint = Paint()..color = const Color(0xFFD8CBDD);

    for (final bubble in model.bubbles) {
      final target = mapPoint(bubble.center);
      if (bubble.person != null) {
        canvas.drawLine(mapPoint(model.focusCenter), target, linePaint);
        canvas.drawCircle(target, 3.1, personPaint);
      } else {
        canvas.drawCircle(target, 2.2, addPaint);
      }
    }
    canvas.drawCircle(
      mapPoint(model.focusCenter),
      5,
      Paint()..color = const Color(0xFF5B2D73),
    );

    final zoom = transform.getMaxScaleOnAxis();
    final safeZoom = zoom <= 0 ? 1.0 : zoom;
    final tx = transform.storage[12];
    final ty = transform.storage[13];
    final visibleTopLeft = Offset(-tx / safeZoom, -ty / safeZoom);
    final visibleSize = Size(
      viewportSize.width / safeZoom,
      viewportSize.height / safeZoom,
    );
    final visibleRect = Rect.fromLTWH(
      offset.dx + visibleTopLeft.dx * mapScale,
      offset.dy + visibleTopLeft.dy * mapScale,
      visibleSize.width * mapScale,
      visibleSize.height * mapScale,
    ).intersect(Offset.zero & size);

    if (!visibleRect.isEmpty) {
      canvas.drawRect(
        visibleRect,
        Paint()
          ..color = const Color(0xFF5B2D73).withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        visibleRect,
        Paint()
          ..color = const Color(0xFF5B2D73).withValues(alpha: 0.7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
