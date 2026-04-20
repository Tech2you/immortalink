import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';
import 'vaults_screen.dart';
import 'legacy_vault_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String familyId;

  const FamilyTreeScreen({super.key, required this.familyId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';

  static const String kMaternalGgm = 'maternal_ggm';
  static const String kMaternalGgf = 'maternal_ggf';
  static const String kPaternalGgm = 'paternal_ggm';
  static const String kPaternalGgf = 'paternal_ggf';

  static const String kMaternalGm = 'maternal_gm';
  static const String kMaternalGf = 'maternal_gf';
  static const String kPaternalGm = 'paternal_gm';
  static const String kPaternalGf = 'paternal_gf';

  static const String kMother = 'mother';
  static const String kFather = 'father';

  static const String kSpouse1 = 'spouse_1';

  static const String kSibling1 = 'sibling_1';
  static const String kSibling2 = 'sibling_2';
  static const String kSibling3 = 'sibling_3';

  static const String kChild1 = 'child_1';
  static const String kChild2 = 'child_2';
  static const String kChild3 = 'child_3';
  static const String kChild4 = 'child_4';

  static const String kGrandchild1 = 'grandchild_1';
  static const String kGrandchild2 = 'grandchild_2';
  static const String kGrandchild3 = 'grandchild_3';
  static const String kGrandchild4 = 'grandchild_4';

  static const String kGreatGrandchild1 = 'greatgrandchild_1';
  static const String kGreatGrandchild2 = 'greatgrandchild_2';
  static const String kGreatGrandchild3 = 'greatgrandchild_3';
  static const String kGreatGrandchild4 = 'greatgrandchild_4';

  bool _showGreatGrandparents = false;
  bool _showGrandparents = true;

  bool _showDescendants = true;
  bool _showGrandkids = false;
  bool _showGreatGrandkids = false;

  bool _showFutureAncestorBranches = false;
  bool _showFutureDescendantBranches = false;

  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _nodeKeys = {};
  Map<String, _NodeGeom> _geom = {};

  late Future<_FamilyData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFamilyData();
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed =
          await _supabase.storage.from('avatars').createSignedUrl(path, 60 * 60);
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<_JoinContext?> _getJoinContext() async {
    try {
      final res = await _supabase.rpc(
        'get_join_context',
        params: {'p_family_id': widget.familyId},
      );

      if (res is List && res.isNotEmpty && res.first is Map) {
        final m = res.first as Map;
        final inviterVaultId =
            (m['inviter_vault_id'] ?? '').toString().trim();
        final slotKey = (m['slot_key'] ?? '').toString().trim();
        if (inviterVaultId.isNotEmpty && slotKey.isNotEmpty) {
          return _JoinContext(inviterVaultId: inviterVaultId, slotKey: slotKey);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<_FamilyData> _loadFamilyData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const _FamilyData(
        vaults: [],
        members: [],
        avatarUrlByVaultId: {},
        legacyMembers: [],
        yourVault: null,
        yourAvatarUrl: null,
        joinContext: null,
      );
    }

    List<Map<String, dynamic>> vaults = [];
    Map<String, dynamic>? myVaultMap;

    try {
      final familyVaultRes = await _supabase
          .from('vaults')
          .select('id, name, owner_id, family_id, created_at, avatar_path')
          .eq('family_id', widget.familyId);

      vaults = (familyVaultRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      vaults = [];
    }

    try {
      final myVault = await _supabase
          .from('vaults')
          .select('id, name, owner_id, family_id, created_at, avatar_path')
          .eq('owner_id', user.id)
          .maybeSingle();

      if (myVault != null) {
        myVaultMap = Map<String, dynamic>.from(myVault);
        final myId = (myVaultMap['id'] ?? '').toString();
        final alreadyInList =
            vaults.any((v) => (v['id'] ?? '').toString() == myId);
        if (!alreadyInList) {
          vaults.add(myVaultMap);
        }
      }
    } catch (_) {}

    final joinCtx = await _getJoinContext();

    if (joinCtx != null) {
      final inviterVaultId = joinCtx.inviterVaultId;
      final already =
          vaults.any((v) => (v['id'] ?? '').toString() == inviterVaultId);
      if (!already) {
        try {
          final v = await _supabase
              .from('vaults')
              .select('id, name, owner_id, family_id, created_at, avatar_path')
              .eq('id', inviterVaultId)
              .maybeSingle();
          if (v != null) {
            vaults.add(Map<String, dynamic>.from(v));
          }
        } catch (_) {}
      }
    }

    final Map<String, String> avatarUrlByVaultId = {};
    for (final v in vaults) {
      final id = (v['id'] ?? '').toString();
      final path = (v['avatar_path'] ?? '').toString().trim();
      if (id.isEmpty || path.isEmpty) continue;

      final url = await _signedAvatarUrl(path);
      if (url != null && url.trim().isNotEmpty) {
        avatarUrlByVaultId[id] = url;
      }
    }

    String? yourAvatarUrl;
    if (myVaultMap != null) {
      final myId = (myVaultMap['id'] ?? '').toString();
      yourAvatarUrl = avatarUrlByVaultId[myId];

      if (yourAvatarUrl == null || yourAvatarUrl!.trim().isEmpty) {
        final path = (myVaultMap['avatar_path'] ?? '').toString().trim();
        if (path.isNotEmpty) {
          final direct = await _signedAvatarUrl(path);
          if (direct != null && direct.trim().isNotEmpty) {
            yourAvatarUrl = direct;
            avatarUrlByVaultId[myId] = direct;
          }
        }
      }
    }

    List<Map<String, dynamic>> members = [];
    try {
      final memberRes = await _supabase
          .from('family_members')
          .select('user_id, slot_key, role, joined_at')
          .eq('family_id', widget.familyId);

      members = (memberRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      members = [];
    }

    List<Map<String, dynamic>> legacyMembers = [];
    try {
      final legacyRes = await _supabase
          .from('legacy_family_members')
          .select(
              'id, family_id, slot_key, name, display_name, birth_year, death_year, created_by, created_at, updated_at, replaced_by_vault_id')
          .eq('family_id', widget.familyId);

      legacyMembers = (legacyRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      legacyMembers = [];
    }

    return _FamilyData(
      vaults: vaults,
      members: members,
      avatarUrlByVaultId: avatarUrlByVaultId,
      legacyMembers: legacyMembers,
      yourVault: myVaultMap,
      yourAvatarUrl: yourAvatarUrl,
      joinContext: joinCtx,
    );
  }

  void _refresh() {
    setState(() {
      _future = _loadFamilyData();
    });
  }

  Future<void> _leaveFamily() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave family?'),
        content: const Text(
          'This will remove you from the family and detach your vault. '
          'You can re-join later with an invite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.rpc('leave_family', params: {
        'p_family_id': widget.familyId,
      });

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VaultsScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave family: $e')),
      );
    }
  }

  Map<String, Map<String, dynamic>> _slotToVaultMap(_FamilyData data) {
    final Map<String, Map<String, dynamic>> vaultByUser = {};
    for (final v in data.vaults) {
      final ownerId = (v['owner_id'] ?? '').toString();
      if (ownerId.isNotEmpty) vaultByUser[ownerId] = v;
    }

    final Map<String, Map<String, dynamic>> slotVault = {};
    for (final m in data.members) {
      final slotKey = (m['slot_key'] ?? '').toString();
      final userId = (m['user_id'] ?? '').toString();
      if (slotKey.isEmpty || userId.isEmpty) continue;
      final v = vaultByUser[userId];
      if (v != null) slotVault[slotKey] = v;
    }

    return slotVault;
  }

  Map<String, Map<String, dynamic>> _slotToVaultMapForView(_FamilyData data) {
    final base = _slotToVaultMap(data);

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return base;

    base.removeWhere((_, v) => (v['owner_id'] ?? '').toString() == uid);

    final jc = data.joinContext;
    if (jc == null) return base;

    final inviterVaultId = jc.inviterVaultId;
    final joinedAs = jc.slotKey;

    Map<String, dynamic>? inviterVault;
    for (final v in data.vaults) {
      if ((v['id'] ?? '').toString() == inviterVaultId) {
        inviterVault = v;
        break;
      }
    }
    if (inviterVault == null) return base;

    void putInviterAsParent() {
      if (base[kMother] == null) {
        base[kMother] = inviterVault!;
      } else if (base[kFather] == null) {
        base[kFather] = inviterVault!;
      }
    }

    void putInviterAsSibling() {
      if (base[kSibling1] == null) {
        base[kSibling1] = inviterVault!;
      } else if (base[kSibling2] == null) {
        base[kSibling2] = inviterVault!;
      } else if (base[kSibling3] == null) {
        base[kSibling3] = inviterVault!;
      }
    }

    void putInviterAsChild() {
      if (base[kChild1] == null) {
        base[kChild1] = inviterVault!;
      } else if (base[kChild2] == null) {
        base[kChild2] = inviterVault!;
      } else if (base[kChild3] == null) {
        base[kChild3] = inviterVault!;
      } else if (base[kChild4] == null) {
        base[kChild4] = inviterVault!;
      }
    }

    void putInviterAsGrandchild() {
      if (base[kGrandchild1] == null) {
        base[kGrandchild1] = inviterVault!;
      } else if (base[kGrandchild2] == null) {
        base[kGrandchild2] = inviterVault!;
      } else if (base[kGrandchild3] == null) {
        base[kGrandchild3] = inviterVault!;
      } else if (base[kGrandchild4] == null) {
        base[kGrandchild4] = inviterVault!;
      } else {
        putInviterAsChild();
      }
    }

    void putInviterAsGreatGrandchild() {
      if (base[kGreatGrandchild1] == null) {
        base[kGreatGrandchild1] = inviterVault!;
      } else if (base[kGreatGrandchild2] == null) {
        base[kGreatGrandchild2] = inviterVault!;
      } else if (base[kGreatGrandchild3] == null) {
        base[kGreatGrandchild3] = inviterVault!;
      } else if (base[kGreatGrandchild4] == null) {
        base[kGreatGrandchild4] = inviterVault!;
      } else {
        putInviterAsGrandchild();
      }
    }

    void putInviterAsGrandparent() {
      if (base[kMaternalGm] == null) {
        base[kMaternalGm] = inviterVault!;
      } else if (base[kMaternalGf] == null) {
        base[kMaternalGf] = inviterVault!;
      } else if (base[kPaternalGm] == null) {
        base[kPaternalGm] = inviterVault!;
      } else if (base[kPaternalGf] == null) {
        base[kPaternalGf] = inviterVault!;
      } else {
        putInviterAsParent();
      }
    }

    void putInviterAsGreatGrandparent() {
      if (base[kMaternalGgm] == null) {
        base[kMaternalGgm] = inviterVault!;
      } else if (base[kMaternalGgf] == null) {
        base[kMaternalGgf] = inviterVault!;
      } else if (base[kPaternalGgm] == null) {
        base[kPaternalGgm] = inviterVault!;
      } else if (base[kPaternalGgf] == null) {
        base[kPaternalGgf] = inviterVault!;
      } else {
        putInviterAsGrandparent();
      }
    }

    if (joinedAs.startsWith('child_') ||
        joinedAs == 'child_left' ||
        joinedAs == 'child_right') {
      putInviterAsParent();
    } else if (joinedAs.startsWith('sibling_')) {
      putInviterAsSibling();
    } else if (joinedAs == kMother ||
        joinedAs == kFather ||
        joinedAs == 'parent_left' ||
        joinedAs == 'parent_right') {
      putInviterAsChild();
    } else if (joinedAs == kSpouse1) {
      base[kSpouse1] ??= inviterVault!;
    } else if (joinedAs == kMaternalGm ||
        joinedAs == kMaternalGf ||
        joinedAs == kPaternalGm ||
        joinedAs == kPaternalGf) {
      putInviterAsGrandchild();
    } else if (joinedAs == kMaternalGgm ||
        joinedAs == kMaternalGgf ||
        joinedAs == kPaternalGgm ||
        joinedAs == kPaternalGgf) {
      putInviterAsGreatGrandchild();
    } else if (joinedAs.startsWith('grandchild_')) {
      putInviterAsGrandparent();
    } else if (joinedAs.startsWith('greatgrandchild_')) {
      putInviterAsGreatGrandparent();
    }

    return base;
  }

  Map<String, Map<String, dynamic>> _slotToDisplayMap(_FamilyData data) {
    final base = _slotToVaultMapForView(data);

    const predecessorSlots = {
      kMaternalGgm,
      kMaternalGgf,
      kPaternalGgm,
      kPaternalGgf,
      kMaternalGm,
      kMaternalGf,
      kPaternalGm,
      kPaternalGf,
      kMother,
      kFather,
    };

    for (final legacy in data.legacyMembers) {
      final slotKey = (legacy['slot_key'] ?? '').toString().trim();
      if (slotKey.isEmpty) continue;
      if (!predecessorSlots.contains(slotKey)) continue;
      if (base.containsKey(slotKey)) continue;

      base[slotKey] = {
        ...legacy,
        '__legacy': true,
      };
    }

    return base;
  }

  Map<String, dynamic>? _yourVault(_FamilyData data) {
    if (data.yourVault != null) return data.yourVault;

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    for (final v in data.vaults) {
      if ((v['owner_id'] ?? '').toString() == uid) return v;
    }
    return null;
  }

  Future<void> _openYourVaultFallback() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      final v = await _supabase
          .from('vaults')
          .select('id, name, owner_id')
          .eq('owner_id', uid)
          .maybeSingle();
      if (v == null) return;

      final vaultId = (v['id'] ?? '').toString();
      final vaultName = (v['name'] ?? 'Vault').toString();
      if (vaultId.isEmpty) return;

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VaultHomeScreen(vaultId: vaultId, vaultName: vaultName),
        ),
      );

      _refresh();
    } catch (_) {}
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
      final id = (v?['id'] ?? '').toString();
      if (id.isEmpty) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _createInvite({
    required String slotKey,
    required String title,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final code = _generateInviteCode();
      final expiresAt = DateTime.now().add(const Duration(days: 7)).toUtc();

      final myVaultId = await _getMyVaultIdForInvite();
      if (myVaultId == null || myVaultId.trim().isEmpty) {
        throw Exception('You need a vault before creating an invite.');
      }

      await _supabase.from('family_invites').insert({
        'family_id': widget.familyId,
        'created_by': user.id,
        'invite_code': code,
        'slot_key': slotKey,
        'expires_at': expiresAt.toIso8601String(),
        'inviter_vault_id': myVaultId,
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
              Text('Slot: $slotKey'),
              const SizedBox(height: 10),
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

      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite failed: $e')),
      );
    }
  }

  Future<void> _showLegacyPredecessorComingSoon({
    required String slotKey,
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
                    'Create a family-owned predecessor profile for someone who does not have their own account or vault.',
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
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'About me / notes (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Slot: $slotKey',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.55),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
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

                      setInner(() {
                        saving = true;
                        errorText = null;
                      });

                      try {
                        await _supabase.rpc(
                          'create_legacy_predecessor',
                          params: {
                            'p_family_id': widget.familyId,
                            'p_slot_key': slotKey,
                            'p_name': name,
                            'p_display_name':
                                displayName.isEmpty ? null : displayName,
                            'p_birth_year': birthYear,
                            'p_death_year': deathYear,
                            'p_about_me_text': about.isEmpty ? null : about,
                          },
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _refresh();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$title added to the family tree.'),
                          ),
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

  Future<void> _showPerpetualTreeInfo({
    required String title,
    required String body,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPredecessorAddOptions({
    required String slotKey,
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
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose whether this person is a living family member to invite now, or a legacy predecessor profile your family will build together.',
                style: TextStyle(color: Colors.black.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.person_add_alt_1),
                ),
                title: const Text('Invite relative'),
                subtitle: const Text('Create an invite code for this slot'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createInvite(slotKey: slotKey, title: title);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.history_edu_outlined),
                ),
                title: const Text('Add legacy predecessor'),
                subtitle:
                    const Text('For an ancestor without their own account/vault'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLegacyPredecessorComingSoon(
                    slotKey: slotKey,
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

  Future<void> _openVaultFromTree(
    _FamilyData data,
    Map<String, dynamic> v,
  ) async {
    final uid = _supabase.auth.currentUser?.id;
    final ownerId = (v['owner_id'] ?? '').toString();
    final vaultId = (v['id'] ?? '').toString();
    final vaultName = (v['name'] ?? 'Vault').toString();

    final isLegacy = v['__legacy'] == true;
    if (isLegacy) {
      final legacyId = (v['id'] ?? '').toString();
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

      _refresh();
      return;
    }

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

    _refresh();
  }

  GlobalKey _keyFor(String id) => _nodeKeys.putIfAbsent(id, () => GlobalKey());

  void _recalcGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stackCtx = _stackKey.currentContext;
      if (stackCtx == null) return;
      final stackBox = stackCtx.findRenderObject() as RenderBox;

      final Map<String, _NodeGeom> next = {};
      for (final entry in _nodeKeys.entries) {
        final ctx = entry.value.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox;
        final topLeft = box.localToGlobal(Offset.zero, ancestor: stackBox);
        next[entry.key] = _NodeGeom(
          center: topLeft + Offset(box.size.width / 2, box.size.height / 2),
          size: box.size,
        );
      }

      if (!mounted) return;
      setState(() {
        _geom = next;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Family Tree'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Leave family',
            onPressed: _leaveFamily,
            icon: const Icon(Icons.exit_to_app),
          ),
        ],
      ),
      body: FutureBuilder<_FamilyData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ??
              const _FamilyData(
                vaults: [],
                members: [],
                avatarUrlByVaultId: {},
                legacyMembers: [],
                yourVault: null,
                yourAvatarUrl: null,
                joinContext: null,
              );

          final slotVault = _slotToDisplayMap(data);

          final yourVault = _yourVault(data);
          final yourName = (yourVault?['name'] ?? 'Your vault (you)').toString();
          final yourVaultId = (yourVault?['id'] ?? '').toString();

          final yourAvatarUrl = (data.yourAvatarUrl != null &&
                  data.yourAvatarUrl!.trim().isNotEmpty)
              ? data.yourAvatarUrl
              : (yourVaultId.isNotEmpty
                  ? data.avatarUrlByVaultId[yourVaultId]
                  : null);

          _recalcGeometry();

          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: 0.08,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Image.asset(
                      _logoPath,
                      width: 210,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Your Family Tree',
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1020),
                      child: Container(
                        key: _stackKey,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.black.withOpacity(0.08)),
                          color: Colors.white.withOpacity(0.22),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _TreeLinesPainter(
                                  geom: _geom,
                                  showGreatGrandparents: _showGreatGrandparents,
                                  showGrandparents: _showGrandparents,
                                  showDescendants: _showDescendants,
                                  showGrandkids: _showGrandkids,
                                  showGreatGrandkids: _showGreatGrandkids,
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                _SectionHeader(
                                  title: 'Great-grandparents',
                                  isOpen: _showGreatGrandparents,
                                  onToggle: () => setState(() =>
                                      _showGreatGrandparents =
                                          !_showGreatGrandparents),
                                ),
                                if (_showGreatGrandparents) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Great-grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGgm),
                                                  filled: slotVault[kMaternalGgm],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kMaternalGgm]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGgm,
                                                    title: 'Great-grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel:
                                                      'Add great-grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGgf),
                                                  filled: slotVault[kMaternalGgf],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kMaternalGgf]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGgf,
                                                    title: 'Great-grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel:
                                                      'Add great-grandparent',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Great-grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGgm),
                                                  filled: slotVault[kPaternalGgm],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kPaternalGgm]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGgm,
                                                    title: 'Great-grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel:
                                                      'Add great-grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGgf),
                                                  filled: slotVault[kPaternalGgf],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kPaternalGgf]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGgf,
                                                    title: 'Great-grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel:
                                                      'Add great-grandparent',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                _SectionHeader(
                                  title: 'Grandparents',
                                  isOpen: _showGrandparents,
                                  onToggle: () => setState(() =>
                                      _showGrandparents = !_showGrandparents),
                                ),
                                if (_showGrandparents) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _GroupCard(
                                          title: ' Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGm),
                                                  filled: slotVault[kMaternalGm],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kMaternalGm]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGm,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGf),
                                                  filled: slotVault[kMaternalGf],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kMaternalGf]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGf,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandparent',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _GroupCard(
                                          title: ' Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGm),
                                                  filled: slotVault[kPaternalGm],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kPaternalGm]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGm,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGf),
                                                  filled: slotVault[kPaternalGf],
                                                  avatarUrl: data
                                                      .avatarUrlByVaultId[
                                                          (slotVault[kPaternalGf]
                                                                      ?['id'] ??
                                                                  '')
                                                              .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGf,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: (v) =>
                                                      _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandparent',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                _GroupCard(
                                  title: 'Parents',
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 220,
                                        child: _PersonSlot(
                                          key: _keyFor(kMother),
                                          filled: slotVault[kMother],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kMother]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kMother,
                                            title: 'Parent',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                          showAddLabel: 'Add parent',
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      SizedBox(
                                        width: 220,
                                        child: _PersonSlot(
                                          key: _keyFor(kFather),
                                          filled: slotVault[kFather],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kFather]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kFather,
                                            title: 'Parent',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                          showAddLabel: 'Add parent',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _GroupCard(
                                        title: 'Spouse',
                                        child: _PersonSlot(
                                          key: _keyFor(kSpouse1),
                                          filled: slotVault[kSpouse1],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kSpouse1]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () => _createInvite(
                                            slotKey: kSpouse1,
                                            title: 'Spouse',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                          showAddLabel: 'Add spouse',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: _YourVaultCard(
                                        key: _keyFor('you'),
                                        name: yourName,
                                        subtitle: 'You',
                                        avatarUrl: yourAvatarUrl,
                                        onTap: () async {
                                          if (yourVault != null) {
                                            await _openVaultFromTree(
                                              data,
                                              yourVault,
                                            );
                                          } else {
                                            await _openYourVaultFallback();
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _GroupCard(
                                        title: 'Siblings',
                                        child: Column(
                                          children: [
                                            _PersonSlot(
                                              key: _keyFor(kSibling1),
                                              filled: slotVault[kSibling1],
                                              avatarUrl: data.avatarUrlByVaultId[
                                                  (slotVault[kSibling1]?['id'] ??
                                                          '')
                                                      .toString()],
                                              onInvite: () => _createInvite(
                                                slotKey: kSibling1,
                                                title: 'Sibling 1',
                                              ),
                                              onOpen: (v) =>
                                                  _openVaultFromTree(data, v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling2),
                                              filled: slotVault[kSibling2],
                                              avatarUrl: data.avatarUrlByVaultId[
                                                  (slotVault[kSibling2]?['id'] ??
                                                          '')
                                                      .toString()],
                                              onInvite: () => _createInvite(
                                                slotKey: kSibling2,
                                                title: 'Sibling 2',
                                              ),
                                              onOpen: (v) =>
                                                  _openVaultFromTree(data, v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling3),
                                              filled: slotVault[kSibling3],
                                              avatarUrl: data.avatarUrlByVaultId[
                                                  (slotVault[kSibling3]?['id'] ??
                                                          '')
                                                      .toString()],
                                              onInvite: () => _createInvite(
                                                slotKey: kSibling3,
                                                title: 'Sibling 3',
                                              ),
                                              onOpen: (v) =>
                                                  _openVaultFromTree(data, v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _SectionHeader(
                                  title: 'Descendants',
                                  isOpen: _showDescendants,
                                  onToggle: () => setState(
                                      () => _showDescendants = !_showDescendants),
                                ),
                                if (_showDescendants) ...[
                                  const SizedBox(height: 8),
                                  _GroupCard(
                                    title: 'Kids',
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild1),
                                          text: 'Add child',
                                          filled: slotVault[kChild1],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild1]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () => _createInvite(
                                            slotKey: kChild1,
                                            title: 'Child 1',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild2),
                                          text: 'Add child',
                                          filled: slotVault[kChild2],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild2]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () => _createInvite(
                                            slotKey: kChild2,
                                            title: 'Child 2',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild3),
                                          text: 'Add child',
                                          filled: slotVault[kChild3],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild3]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () => _createInvite(
                                            slotKey: kChild3,
                                            title: 'Child 3',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild4),
                                          text: 'Add child',
                                          filled: slotVault[kChild4],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild4]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () => _createInvite(
                                            slotKey: kChild4,
                                            title: 'Child 4',
                                          ),
                                          onOpen: (v) =>
                                              _openVaultFromTree(data, v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _SectionHeader(
                                    title: 'Grandkids',
                                    isOpen: _showGrandkids,
                                    onToggle: () => setState(
                                        () => _showGrandkids = !_showGrandkids),
                                  ),
                                  if (_showGrandkids) ...[
                                    const SizedBox(height: 8),
                                    _GroupCard(
                                      title: 'Grandkids',
                                      child: Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild1),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild1],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild1]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGrandchild1,
                                              title: 'Grandchild 1',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild2),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild2],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild2]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGrandchild2,
                                              title: 'Grandchild 2',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild3),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild3],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild3]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGrandchild3,
                                              title: 'Grandchild 3',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild4),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild4],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild4]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGrandchild4,
                                              title: 'Grandchild 4',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  _SectionHeader(
                                    title: 'Great-grandkids',
                                    isOpen: _showGreatGrandkids,
                                    onToggle: () => setState(() =>
                                        _showGreatGrandkids =
                                            !_showGreatGrandkids),
                                  ),
                                  if (_showGreatGrandkids) ...[
                                    const SizedBox(height: 8),
                                    _GroupCard(
                                      title: 'Great-grandkids',
                                      child: Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _SmallInviteSlot(
                                            key: _keyFor(kGreatGrandchild1),
                                            text: 'Add great-grandchild',
                                            filled: slotVault[kGreatGrandchild1],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGreatGrandchild1]
                                                            ?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGreatGrandchild1,
                                              title: 'Great-Grandchild 1',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGreatGrandchild2),
                                            text: 'Add great-grandchild',
                                            filled: slotVault[kGreatGrandchild2],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGreatGrandchild2]
                                                            ?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGreatGrandchild2,
                                              title: 'Great-Grandchild 2',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGreatGrandchild3),
                                            text: 'Add great-grandchild',
                                            filled: slotVault[kGreatGrandchild3],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGreatGrandchild3]
                                                            ?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGreatGrandchild3,
                                              title: 'Great-Grandchild 3',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGreatGrandchild4),
                                            text: 'Add great-grandchild',
                                            filled: slotVault[kGreatGrandchild4],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGreatGrandchild4]
                                                            ?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () => _createInvite(
                                              slotKey: kGreatGrandchild4,
                                              title: 'Great-Grandchild 4',
                                            ),
                                            onOpen: (v) =>
                                                _openVaultFromTree(data, v),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 14),
                                _SectionHeader(
                                  title: 'Expand ancestor branches',
                                  isOpen: _showFutureAncestorBranches,
                                  onToggle: () => setState(() =>
                                      _showFutureAncestorBranches =
                                          !_showFutureAncestorBranches),
                                ),
                                if (_showFutureAncestorBranches) ...[
                                  const SizedBox(height: 8),
                                  _FutureBranchCard(
                                    title: 'Older ancestors',
                                    subtitle:
                                        'In the next phase, each ancestor card can open its own branch so your tree keeps growing upward without replacing this main view.',
                                    buttonText: 'How this will work',
                                    onTap: () => _showPerpetualTreeInfo(
                                      title: 'Ancestor branch expansion',
                                      body:
                                          'The main tree will stay simple and familiar. Later, tapping a parent, grandparent, or great-grandparent will open that person\'s own branch view so older generations can keep expanding upward without cramming everything onto one screen.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _SectionHeader(
                                  title: 'Expand descendant branches',
                                  isOpen: _showFutureDescendantBranches,
                                  onToggle: () => setState(() =>
                                      _showFutureDescendantBranches =
                                          !_showFutureDescendantBranches),
                                ),
                                if (_showFutureDescendantBranches) ...[
                                  const SizedBox(height: 8),
                                  _FutureBranchCard(
                                    title: 'Future generations',
                                    subtitle:
                                        'Kids, grandkids, and great-grandkids will later be able to open their own branch views so descendants can keep extending downward over time.',
                                    buttonText: 'How this will work',
                                    onTap: () => _showPerpetualTreeInfo(
                                      title: 'Descendant branch expansion',
                                      body:
                                          'Your current tree will remain the home view. Later, when a descendant branch gets large, tapping that child or grandchild line will open a focused branch view for that line, allowing perpetual family growth without forcing endless hardcoded slots into one screen.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                SizedBox(
                                  height: 54,
                                  child: CustomPaint(
                                    painter: _BottomVinesPainter(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: Text(
                                    'Your tree grows as more people are added. Branch expansion will let future generations keep unfolding from this view.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.black.withOpacity(0.50),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/* =======================
   UI Components
======================= */

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isOpen;
  final VoidCallback onToggle;

  const _SectionHeader({
    required this.title,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Icon(isOpen ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _GroupCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black.withOpacity(0.35),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final String? url;
  final double radius;

  const _AvatarBubble({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    final has = u.isNotEmpty;

    final bg = Container(
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

    if (!has) return bg;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          u,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => bg,
        ),
      ),
    );
  }
}

class _YourVaultCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? avatarUrl;
  final VoidCallback onTap;

  const _YourVaultCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: SizedBox(
        height: 150,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withOpacity(0.10)),
            color: Colors.white.withOpacity(0.40),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AvatarBubble(url: avatarUrl, radius: 28),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonSlot extends StatelessWidget {
  final Map<String, dynamic>? filled;
  final String? avatarUrl;
  final VoidCallback onInvite;
  final void Function(Map<String, dynamic> v) onOpen;
  final String showAddLabel;

  const _PersonSlot({
    super.key,
    required this.filled,
    required this.avatarUrl,
    required this.onInvite,
    required this.onOpen,
    required this.showAddLabel,
  });

  @override
  Widget build(BuildContext context) {
    final has = filled != null;
    final label = has
        ? (((filled!['display_name'] ?? '').toString().trim().isNotEmpty)
            ? filled!['display_name'].toString()
            : ((filled!['name'] ?? 'Vault').toString()))
        : showAddLabel;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => has ? onOpen(filled!) : onInvite(),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.35),
        ),
        child: Row(
          children: [
            has
                ? _AvatarBubble(url: avatarUrl, radius: 20)
                : CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.black.withOpacity(0.08),
                    child: Icon(
                      Icons.add,
                      color: Colors.black.withOpacity(0.65),
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: has ? FontWeight.w700 : FontWeight.w600,
                  color: Colors.black.withOpacity(0.80),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallInviteSlot extends StatelessWidget {
  final String text;
  final Map<String, dynamic>? filled;
  final String? avatarUrl;
  final VoidCallback onInvite;
  final void Function(Map<String, dynamic> v) onOpen;

  const _SmallInviteSlot({
    super.key,
    required this.text,
    required this.filled,
    required this.avatarUrl,
    required this.onInvite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final has = filled != null;
    final label = has
        ? (((filled!['display_name'] ?? '').toString().trim().isNotEmpty)
            ? filled!['display_name'].toString()
            : ((filled!['name'] ?? 'Child').toString()))
        : text;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => has ? onOpen(filled!) : onInvite(),
      child: Container(
        width: 200,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.30),
        ),
        child: Row(
          children: [
            has
                ? _AvatarBubble(url: avatarUrl, radius: 16)
                : CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black.withOpacity(0.08),
                    child: Icon(
                      Icons.add,
                      color: Colors.black.withOpacity(0.65),
                      size: 18,
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.75),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FutureBranchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  const _FutureBranchCard({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.06),
              child: Icon(
                Icons.account_tree_outlined,
                color: Colors.black.withOpacity(0.70),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onTap,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

/* =======================
   Lines Painter
======================= */

class _NodeGeom {
  final Offset center;
  final Size size;

  const _NodeGeom({required this.center, required this.size});
}

class _TreeLinesPainter extends CustomPainter {
  final Map<String, _NodeGeom> geom;

  final bool showGreatGrandparents;
  final bool showGrandparents;

  final bool showDescendants;
  final bool showGrandkids;
  final bool showGreatGrandkids;

  const _TreeLinesPainter({
    required this.geom,
    required this.showGreatGrandparents,
    required this.showGrandparents,
    required this.showDescendants,
    required this.showGrandkids,
    required this.showGreatGrandkids,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Offset? c(String id) => geom[id]?.center;
    Size? s(String id) => geom[id]?.size;

    Offset edgePoint(String fromId, String toId, {double pad = 8}) {
      final from = c(fromId)!;
      final to = c(toId)!;
      final sz = s(fromId)!;
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;

      final halfW = (sz.width / 2) + pad;
      final halfH = (sz.height / 2) + pad;

      final adx = dx.abs();
      final ady = dy.abs();
      if (adx == 0 && ady == 0) return from;

      final scale = max(adx / halfW, ady / halfH);
      return Offset(from.dx + dx / scale, from.dy + dy / scale);
    }

    void line(String a, String b) {
      if (c(a) == null || c(b) == null || s(a) == null || s(b) == null) {
        return;
      }
      final p1 = edgePoint(a, b);
      final p2 = edgePoint(b, a);
      canvas.drawLine(p1, p2, paint);
    }

    const you = 'you';

    if (showGreatGrandparents) {
      line('maternal_ggm', 'maternal_gm');
      line('maternal_ggf', 'maternal_gm');
      line('paternal_ggm', 'paternal_gm');
      line('paternal_ggf', 'paternal_gm');
    }

    if (showGrandparents) {
      line('maternal_gm', 'mother');
      line('maternal_gf', 'mother');
      line('paternal_gm', 'father');
      line('paternal_gf', 'father');
    }

    line('mother', you);
    line('father', you);
    line('spouse_1', you);

    line('sibling_1', you);
    line('sibling_2', you);
    line('sibling_3', you);

    if (showDescendants) {
      line(you, 'child_1');
      line(you, 'child_2');
      line(you, 'child_3');
      line(you, 'child_4');

      if (showGrandkids) {
        line(you, 'grandchild_1');
        line(you, 'grandchild_2');
        line(you, 'grandchild_3');
        line(you, 'grandchild_4');
      }
      if (showGreatGrandkids) {
        line(you, 'greatgrandchild_1');
        line(you, 'greatgrandchild_2');
        line(you, 'greatgrandchild_3');
        line(you, 'greatgrandchild_4');
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TreeLinesPainter oldDelegate) {
    return oldDelegate.geom != geom ||
        oldDelegate.showGreatGrandparents != showGreatGrandparents ||
        oldDelegate.showGrandparents != showGrandparents ||
        oldDelegate.showDescendants != showDescendants ||
        oldDelegate.showGrandkids != showGrandkids ||
        oldDelegate.showGreatGrandkids != showGreatGrandkids;
  }
}

class _BottomVinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final p2 = Paint()
      ..color = Colors.black.withOpacity(0.10)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final y1 = size.height * 0.55;
    final y2 = size.height * 0.72;

    final path1 = Path()
      ..moveTo(0, y1)
      ..cubicTo(
        size.width * 0.22,
        y1 - 10,
        size.width * 0.38,
        y1 + 14,
        size.width * 0.52,
        y1,
      )
      ..cubicTo(
        size.width * 0.70,
        y1 - 16,
        size.width * 0.84,
        y1 + 10,
        size.width,
        y1,
      );

    final path2 = Path()
      ..moveTo(0, y2)
      ..cubicTo(
        size.width * 0.18,
        y2 + 8,
        size.width * 0.42,
        y2 - 12,
        size.width * 0.60,
        y2,
      )
      ..cubicTo(
        size.width * 0.78,
        y2 + 14,
        size.width * 0.92,
        y2 - 6,
        size.width,
        y2,
      );

    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/* =======================
   Data
======================= */

class _JoinContext {
  final String inviterVaultId;
  final String slotKey;

  const _JoinContext({required this.inviterVaultId, required this.slotKey});
}

class _FamilyData {
  final List<Map<String, dynamic>> vaults;
  final List<Map<String, dynamic>> members;
  final Map<String, String> avatarUrlByVaultId;
  final List<Map<String, dynamic>> legacyMembers;
  final Map<String, dynamic>? yourVault;
  final String? yourAvatarUrl;
  final _JoinContext? joinContext;

  const _FamilyData({
    required this.vaults,
    required this.members,
    required this.avatarUrlByVaultId,
    required this.legacyMembers,
    required this.yourVault,
    required this.yourAvatarUrl,
    required this.joinContext,
  });
}