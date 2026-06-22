import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';
import 'vaults_screen.dart';
import 'legacy_vault_screen.dart';
import 'family_branch_screen.dart';
import 'sign_in_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String familyId;

  const FamilyTreeScreen({super.key, required this.familyId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';
  static const String _vaultAvatarBucket = 'avatars';
  static const String _legacyAvatarBucket = 'vault_photos';

  // Great-grandparents: two parents for each grandparent = 8 total slots.
  static const String kMaternalGmMother = 'maternal_gm_mother';
  static const String kMaternalGmFather = 'maternal_gm_father';
  static const String kMaternalGfMother = 'maternal_gf_mother';
  static const String kMaternalGfFather = 'maternal_gf_father';
  static const String kPaternalGmMother = 'paternal_gm_mother';
  static const String kPaternalGmFather = 'paternal_gm_father';
  static const String kPaternalGfMother = 'paternal_gf_mother';
  static const String kPaternalGfFather = 'paternal_gf_father';

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

  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _nodeKeys = {};
  Map<String, _NodeGeom> _geom = {};

  late Future<_FamilyData> _future;

  _FamilyData? _latestData;
  Map<String, Map<String, dynamic>> _latestDisplaySlots = {};

  @override
  void initState() {
    super.initState();
    _future = _loadFamilyData();
  }

  String? _legacyRelationForSlot(String slotKey) {
    switch (slotKey) {
      case kMother:
      case kFather:
      case kMaternalGm:
      case kMaternalGf:
      case kPaternalGm:
      case kPaternalGf:
      case kMaternalGmMother:
      case kMaternalGmFather:
      case kMaternalGfMother:
      case kMaternalGfFather:
      case kPaternalGmMother:
      case kPaternalGmFather:
      case kPaternalGfMother:
      case kPaternalGfFather:
        return 'parent';

      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
      case kGrandchild1:
      case kGrandchild2:
      case kGrandchild3:
      case kGrandchild4:
      case kGreatGrandchild1:
      case kGreatGrandchild2:
      case kGreatGrandchild3:
      case kGreatGrandchild4:
        return 'child';

      case kSpouse1:
        return 'spouse';

      case kSibling1:
      case kSibling2:
      case kSibling3:
        return 'sibling';

      default:
        return null;
    }
  }

  Map<String, dynamic>? _firstNonNullPerson(List<Map<String, dynamic>?> people) {
    for (final person in people) {
      if (person != null) return person;
    }
    return null;
  }

  Map<String, dynamic>? _legacyAnchorPersonForSlot(String slotKey) {
    switch (slotKey) {
      case kMother:
      case kFather:
      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
      case kSpouse1:
      case kSibling1:
      case kSibling2:
      case kSibling3:
        return _currentViewerPerson(_latestData);

      case kMaternalGm:
      case kMaternalGf:
        return _latestDisplaySlots[kMother];

      case kPaternalGm:
      case kPaternalGf:
        return _latestDisplaySlots[kFather];

      case kMaternalGmMother:
      case kMaternalGmFather:
        return _latestDisplaySlots[kMaternalGm];

      case kMaternalGfMother:
      case kMaternalGfFather:
        return _latestDisplaySlots[kMaternalGf];

      case kPaternalGmMother:
      case kPaternalGmFather:
        return _latestDisplaySlots[kPaternalGm];

      case kPaternalGfMother:
      case kPaternalGfFather:
        return _latestDisplaySlots[kPaternalGf];

      case kGrandchild1:
        return _latestDisplaySlots[kChild1];
      case kGrandchild2:
        return _latestDisplaySlots[kChild2];
      case kGrandchild3:
        return _latestDisplaySlots[kChild3];
      case kGrandchild4:
        return _latestDisplaySlots[kChild4];

      case kGreatGrandchild1:
        return _latestDisplaySlots[kGrandchild1];
      case kGreatGrandchild2:
        return _latestDisplaySlots[kGrandchild2];
      case kGreatGrandchild3:
        return _latestDisplaySlots[kGrandchild3];
      case kGreatGrandchild4:
        return _latestDisplaySlots[kGrandchild4];

      default:
        return null;
    }
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

  Future<_FamilyData> _loadFamilyData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const _FamilyData(
        vaults: [],
        members: [],
        relationships: [],
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
          .select(
            'id, name, display_name, owner_id, family_id, created_at, avatar_path',
          )
          .eq('family_id', widget.familyId);

      vaults = (familyVaultRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      vaults = [];
    }

    try {
      final myVault = await _supabase
          .from('vaults')
          .select(
            'id, name, display_name, owner_id, family_id, created_at, avatar_path',
          )
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
              .select(
                'id, name, display_name, owner_id, family_id, created_at, avatar_path',
              )
              .eq('id', inviterVaultId)
              .maybeSingle();
          if (v != null) {
            vaults.add(Map<String, dynamic>.from(v));
          }
        } catch (_) {}
      }
    }

    final avatarUrlByVaultId = <String, String>{};

    for (final v in vaults) {
      final id = (v['id'] ?? '').toString().trim();
      final path = (v['avatar_path'] ?? '').toString().trim();
      if (id.isEmpty || path.isEmpty) continue;

      final url = await _signedVaultAvatarUrl(path);
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
          final direct = await _signedVaultAvatarUrl(path);
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
            'id, family_id, slot_key, name, display_name, birth_year, death_year, created_by, created_at, updated_at, replaced_by_vault_id, about_me_text, avatar_path',
          )
          .eq('family_id', widget.familyId);

      legacyMembers = (legacyRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      legacyMembers = [];
    }

    List<Map<String, dynamic>> relationships = [];
    try {
      final relRes = await _supabase
          .from('family_relationships')
          .select(
            'id, family_id, parent_type, parent_id, child_type, child_id, relationship_kind, created_at',
          )
          .eq('family_id', widget.familyId)
          .order('created_at', ascending: true);

      relationships = (relRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      relationships = [];
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
        avatarUrlByVaultId[id] = url;
      }
    }

    return _FamilyData(
      vaults: vaults,
      members: members,
      relationships: relationships,
      avatarUrlByVaultId: avatarUrlByVaultId,
      legacyMembers: legacyMembers,
      yourVault: myVaultMap,
      yourAvatarUrl: yourAvatarUrl,
      joinContext: joinCtx,
    );
  }

  _RelationshipAnchorSpec? _relationshipAnchorForSlot(String slotKey) {
    switch (slotKey) {
      case kMother:
      case kFather:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: null,
          anchorIsViewer: true,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kMaternalGm:
      case kMaternalGf:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kMother,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kPaternalGm:
      case kPaternalGf:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kFather,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kMaternalGmMother:
      case kMaternalGmFather:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kMaternalGm,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kMaternalGfMother:
      case kMaternalGfFather:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kMaternalGf,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kPaternalGmMother:
      case kPaternalGmFather:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kPaternalGm,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kPaternalGfMother:
      case kPaternalGfFather:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: kPaternalGf,
          anchorIsViewer: false,
          newNodeIsParent: true,
          relationshipKind: 'parent_child',
        );

      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: null,
          anchorIsViewer: true,
          newNodeIsParent: false,
          relationshipKind: 'parent_child',
        );

      case kGrandchild1:
      case kGrandchild2:
      case kGrandchild3:
      case kGrandchild4:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: null,
          anchorIsViewer: false,
          newNodeIsParent: false,
          relationshipKind: 'parent_child',
        );

      case kGreatGrandchild1:
      case kGreatGrandchild2:
      case kGreatGrandchild3:
      case kGreatGrandchild4:
        return const _RelationshipAnchorSpec(
          anchorSlotKey: null,
          anchorIsViewer: false,
          newNodeIsParent: false,
          relationshipKind: 'parent_child',
        );

      default:
        return null;
    }
  }

  bool _supportsLegacyProfile(String slotKey) {
    switch (slotKey) {
      case kMother:
      case kFather:
      case kMaternalGm:
      case kMaternalGf:
      case kPaternalGm:
      case kPaternalGf:
      case kMaternalGmMother:
      case kMaternalGmFather:
      case kMaternalGfMother:
      case kMaternalGfFather:
      case kPaternalGmMother:
      case kPaternalGmFather:
      case kPaternalGfMother:
      case kPaternalGfFather:
        return true;
      default:
        return false;
    }
  }

  String _legacyDialogTitleForSlot(String slotKey, String fallbackTitle) {
    switch (slotKey) {
      case kSpouse1:
        return 'Add legacy spouse';
      case kSibling1:
      case kSibling2:
      case kSibling3:
        return 'Add legacy sibling';
      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
        return 'Add legacy child';
      case kGrandchild1:
      case kGrandchild2:
      case kGrandchild3:
      case kGrandchild4:
        return 'Add legacy grandchild';
      case kGreatGrandchild1:
      case kGreatGrandchild2:
      case kGreatGrandchild3:
      case kGreatGrandchild4:
        return 'Add legacy great-grandchild';
      default:
        return 'Add legacy $fallbackTitle';
    }
  }

  String _legacyDialogDescriptionForSlot(String slotKey) {
    switch (slotKey) {
      case kSpouse1:
        return 'Create a family-owned spouse profile for someone who does not have their own account or vault yet.';
      case kSibling1:
      case kSibling2:
      case kSibling3:
        return 'Create a family-owned sibling profile for someone who does not have their own account or vault yet.';
      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
        return 'Create a family-owned child profile for someone who does not have their own account or vault yet.';
      case kGrandchild1:
      case kGrandchild2:
      case kGrandchild3:
      case kGrandchild4:
        return 'Create a family-owned grandchild profile for someone who does not have their own account or vault yet.';
      case kGreatGrandchild1:
      case kGreatGrandchild2:
      case kGreatGrandchild3:
      case kGreatGrandchild4:
        return 'Create a family-owned great-grandchild profile for someone who does not have their own account or vault yet.';
      default:
        return 'Create a family-owned predecessor profile for someone who does not have their own account or vault.';
    }
  }

  _RelationshipNodeRef? _nodeRefFromPerson(Map<String, dynamic>? person) {
    if (person == null) return null;
    final id = (person['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final isLegacy = person['__legacy'] == true;
    return _RelationshipNodeRef(
      nodeType: isLegacy ? 'legacy' : 'vault',
      nodeId: id,
    );
  }

  Future<void> _linkNewNodeIntoRelationships({
    required String slotKey,
    required String newNodeType,
    required String newNodeId,
  }) async {
    try {
      final plan = _relationshipAnchorForSlot(slotKey);
      if (plan == null) return;

      _RelationshipNodeRef? anchorNode;

      if (plan.anchorIsViewer) {
        final viewer = _currentViewerPerson(_latestData);
        anchorNode = _nodeRefFromPerson(viewer);
      } else {
        Map<String, dynamic>? anchorPerson;

        if (slotKey == kGrandchild1 ||
            slotKey == kGrandchild2 ||
            slotKey == kGrandchild3 ||
            slotKey == kGrandchild4) {
          final children = [
            _latestDisplaySlots[kChild1],
            _latestDisplaySlots[kChild2],
            _latestDisplaySlots[kChild3],
            _latestDisplaySlots[kChild4],
          ];
          if (slotKey == kGrandchild1) anchorPerson = children[0];
          if (slotKey == kGrandchild2) anchorPerson = children[1];
          if (slotKey == kGrandchild3) anchorPerson = children[2];
          if (slotKey == kGrandchild4) anchorPerson = children[3];
        } else if (slotKey == kGreatGrandchild1 ||
            slotKey == kGreatGrandchild2 ||
            slotKey == kGreatGrandchild3 ||
            slotKey == kGreatGrandchild4) {
          final grandChildren = [
            _latestDisplaySlots[kGrandchild1],
            _latestDisplaySlots[kGrandchild2],
            _latestDisplaySlots[kGrandchild3],
            _latestDisplaySlots[kGrandchild4],
          ];
          if (slotKey == kGreatGrandchild1) anchorPerson = grandChildren[0];
          if (slotKey == kGreatGrandchild2) anchorPerson = grandChildren[1];
          if (slotKey == kGreatGrandchild3) anchorPerson = grandChildren[2];
          if (slotKey == kGreatGrandchild4) anchorPerson = grandChildren[3];
        } else {
          final anchorSlotKey = plan.anchorSlotKey;
          if (anchorSlotKey != null) {
            anchorPerson = _latestDisplaySlots[anchorSlotKey];
          }
        }

        anchorNode = _nodeRefFromPerson(anchorPerson);
      }

      if (anchorNode == null || anchorNode.nodeId.trim().isEmpty) return;

      late final String parentType;
      late final String parentId;
      late final String childType;
      late final String childId;

      if (plan.newNodeIsParent) {
        parentType = newNodeType;
        parentId = newNodeId;
        childType = anchorNode.nodeType;
        childId = anchorNode.nodeId;
      } else {
        parentType = anchorNode.nodeType;
        parentId = anchorNode.nodeId;
        childType = newNodeType;
        childId = newNodeId;
      }

      if (parentId.trim().isEmpty || childId.trim().isEmpty) return;

      final existing = await _supabase
          .from('family_relationships')
          .select('id')
          .eq('family_id', widget.familyId)
          .eq('parent_type', parentType)
          .eq('parent_id', parentId)
          .eq('child_type', childType)
          .eq('child_id', childId)
          .limit(1);

      final existingRows = (existing as List).cast<Map<String, dynamic>>();
      if (existingRows.isNotEmpty) return;

      await _supabase.from('family_relationships').insert({
        'family_id': widget.familyId,
        'parent_type': parentType,
        'parent_id': parentId,
        'child_type': childType,
        'child_id': childId,
        'relationship_kind': plan.relationshipKind,
      });
    } catch (_) {}
  }

  void _refresh() {
    setState(() {
      _future = _loadFamilyData();
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This will sign you out and return you to login.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sign out: $e')),
      );
    }
  }

  Future<void> _leaveFamily() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave family?'),
        content: const Text(
          'This will remove you from the family and detach your vault. You can re-join later with an invite.',
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
    final vaultByUser = <String, Map<String, dynamic>>{};
    for (final v in data.vaults) {
      final ownerId = (v['owner_id'] ?? '').toString().trim();
      if (ownerId.isNotEmpty) {
        vaultByUser[ownerId] = v;
      }
    }

    final slotVault = <String, Map<String, dynamic>>{};
    for (final m in data.members) {
      final slotKey = (m['slot_key'] ?? '').toString().trim();
      final userId = (m['user_id'] ?? '').toString().trim();
      if (slotKey.isEmpty || userId.isEmpty) continue;
      final v = vaultByUser[userId];
      if (v != null) slotVault[slotKey] = v;
    }

    return slotVault;
  }

  Map<String, Map<String, dynamic>> _slotToGlobalPersonMap(_FamilyData data) {
    final result = <String, Map<String, dynamic>>{};
    result.addAll(_slotToVaultMap(data));

    for (final legacy in data.legacyMembers) {
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

  String _nodeKeyFromPerson(Map<String, dynamic>? person) {
    if (person == null) return '';
    final id = (person['id'] ?? '').toString().trim();
    if (id.isEmpty) return '';
    final isLegacy = person['__legacy'] == true;
    return '${isLegacy ? 'legacy' : 'vault'}:$id';
  }

  bool _samePerson(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    final ak = _nodeKeyFromPerson(a);
    final bk = _nodeKeyFromPerson(b);
    return ak.isNotEmpty && ak == bk;
  }

  Map<String, dynamic>? _personForNode(
    _FamilyData data,
    String nodeType,
    String nodeId,
  ) {
    if (nodeType == 'vault') {
      for (final v in data.vaults) {
        if ((v['id'] ?? '').toString() == nodeId) return v;
      }
      return null;
    }

    if (nodeType == 'legacy') {
      for (final l in data.legacyMembers) {
        if ((l['id'] ?? '').toString() == nodeId) {
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

  int _slotPriority(String slot) {
    const ordered = [
      kMother,
      kFather,
      kMaternalGm,
      kMaternalGf,
      kPaternalGm,
      kPaternalGf,
      kMaternalGmMother,
      kMaternalGmFather,
      kMaternalGfMother,
      kMaternalGfFather,
      kPaternalGmMother,
      kPaternalGmFather,
      kPaternalGfMother,
      kPaternalGfFather,
      kSpouse1,
      kSibling1,
      kSibling2,
      kSibling3,
      kChild1,
      kChild2,
      kChild3,
      kChild4,
      kGrandchild1,
      kGrandchild2,
      kGrandchild3,
      kGrandchild4,
      kGreatGrandchild1,
      kGreatGrandchild2,
      kGreatGrandchild3,
      kGreatGrandchild4,
    ];
    final idx = ordered.indexOf(slot);
    return idx == -1 ? 999 : idx;
  }

  String _slotForPerson(
    Map<String, Map<String, dynamic>> slotMap,
    Map<String, dynamic>? person,
  ) {
    if (person == null) return '';
    final key = _nodeKeyFromPerson(person);
    if (key.isEmpty) return '';
    for (final entry in slotMap.entries) {
      if (_nodeKeyFromPerson(entry.value) == key) {
        return entry.key;
      }
    }
    return '';
  }

  int _comparePeople(
    Map<String, Map<String, dynamic>> global,
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final sa = _slotForPerson(global, a);
    final sb = _slotForPerson(global, b);

    final pa = _slotPriority(sa);
    final pb = _slotPriority(sb);
    if (pa != pb) return pa.compareTo(pb);

    final na = (((a['display_name'] ?? '').toString().trim().isNotEmpty)
            ? a['display_name']
            : (a['name'] ?? ''))
        .toString()
        .toLowerCase();
    final nb = (((b['display_name'] ?? '').toString().trim().isNotEmpty)
            ? b['display_name']
            : (b['name'] ?? ''))
        .toString()
        .toLowerCase();

    return na.compareTo(nb);
  }

  Map<String, dynamic>? _currentViewerPerson(_FamilyData? data) {
    if (data == null) return null;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    if (data.yourVault != null) return data.yourVault;

    for (final v in data.vaults) {
      if ((v['owner_id'] ?? '').toString().trim() == uid) {
        return v;
      }
    }

    return null;
  }

  Map<String, dynamic>? _yourVault(_FamilyData data) {
    if (data.yourVault != null) return data.yourVault;

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    for (final v in data.vaults) {
      if ((v['owner_id'] ?? '').toString().trim() == uid) return v;
    }
    return null;
  }

  void _addUniquePerson(
    List<Map<String, dynamic>> target,
    Map<String, dynamic>? person,
  ) {
    if (person == null) return;
    final key = _nodeKeyFromPerson(person);
    if (key.isEmpty) return;
    final exists = target.any((e) => _nodeKeyFromPerson(e) == key);
    if (!exists) {
      target.add(person);
    }
  }

  void _addGraphEdge({
    required Map<String, List<Map<String, dynamic>>> parentsByChild,
    required Map<String, List<Map<String, dynamic>>> childrenByParent,
    required Map<String, dynamic>? parent,
    required Map<String, dynamic>? child,
  }) {
    if (parent == null || child == null) return;

    final parentKey = _nodeKeyFromPerson(parent);
    final childKey = _nodeKeyFromPerson(child);
    if (parentKey.isEmpty || childKey.isEmpty) return;

    final parentList = parentsByChild.putIfAbsent(childKey, () => []);
    if (!parentList.any((e) => _nodeKeyFromPerson(e) == parentKey)) {
      parentList.add(parent);
    }

    final childList = childrenByParent.putIfAbsent(parentKey, () => []);
    if (!childList.any((e) => _nodeKeyFromPerson(e) == childKey)) {
      childList.add(child);
    }
  }

  void _buildRelationshipGraph(
    _FamilyData data,
    Map<String, List<Map<String, dynamic>>> parentsByChild,
    Map<String, List<Map<String, dynamic>>> childrenByParent,
  ) {
    for (final row in data.relationships) {
      final kind = (row['relationship_kind'] ?? '').toString().trim();
      if (kind != 'parent_child') continue;

      final parentType = (row['parent_type'] ?? '').toString().trim();
      final parentId = (row['parent_id'] ?? '').toString().trim();
      final childType = (row['child_type'] ?? '').toString().trim();
      final childId = (row['child_id'] ?? '').toString().trim();

      if (parentType.isEmpty ||
          parentId.isEmpty ||
          childType.isEmpty ||
          childId.isEmpty) {
        continue;
      }

      if (parentType == 'invite' || childType == 'invite') continue;

      final parent = _personForNode(data, parentType, parentId);
      final child = _personForNode(data, childType, childId);
      if (parent == null || child == null) continue;

      _addGraphEdge(
        parentsByChild: parentsByChild,
        childrenByParent: childrenByParent,
        parent: parent,
        child: child,
      );
    }
  }

  Map<String, Map<String, dynamic>> _slotToDisplayMap(_FamilyData data) {
    final global = _slotToGlobalPersonMap(data);
    final viewer = _currentViewerPerson(data);

    if (viewer == null) return {};

    final parentsByChild = <String, List<Map<String, dynamic>>>{};
    final childrenByParent = <String, List<Map<String, dynamic>>>{};

    _buildRelationshipGraph(
      data,
      parentsByChild,
      childrenByParent,
    );

    List<Map<String, dynamic>> parentsOf(Map<String, dynamic>? person) {
      if (person == null) return [];
      final key = _nodeKeyFromPerson(person);
      final out = [...(parentsByChild[key] ?? const <Map<String, dynamic>>[])];
      out.sort((a, b) => _comparePeople(global, a, b));
      return out;
    }

    List<Map<String, dynamic>> childrenOf(Map<String, dynamic>? person) {
      if (person == null) return [];
      final key = _nodeKeyFromPerson(person);
      final out = [...(childrenByParent[key] ?? const <Map<String, dynamic>>[])];
      out.sort((a, b) => _comparePeople(global, a, b));
      return out;
    }

    void placePerson(
      Map<String, Map<String, dynamic>> visible,
      List<String> allowedSlots,
      Map<String, dynamic>? person,
    ) {
      if (person == null) return;

      final actualSlot = _slotForPerson(global, person);
      if (actualSlot.isNotEmpty &&
          allowedSlots.contains(actualSlot) &&
          !visible.containsKey(actualSlot)) {
        visible[actualSlot] = person;
        return;
      }

      for (final slot in allowedSlots) {
        if (!visible.containsKey(slot)) {
          visible[slot] = person;
          return;
        }
      }
    }

    final visible = <String, Map<String, dynamic>>{};

    final parents = parentsOf(viewer);
    for (final parent in parents) {
      placePerson(visible, [kMother, kFather], parent);
    }

    final mother = visible[kMother];
    final father = visible[kFather];

    if (mother != null) {
      final maternalGrand = parentsOf(mother);
      for (final person in maternalGrand) {
        placePerson(visible, [kMaternalGm, kMaternalGf], person);
      }

      final maternalGm = visible[kMaternalGm];
      if (maternalGm != null) {
        final maternalGmParents = parentsOf(maternalGm);
        for (final person in maternalGmParents) {
          placePerson(
            visible,
            [kMaternalGmMother, kMaternalGmFather],
            person,
          );
        }
      }

      final maternalGf = visible[kMaternalGf];
      if (maternalGf != null) {
        final maternalGfParents = parentsOf(maternalGf);
        for (final person in maternalGfParents) {
          placePerson(
            visible,
            [kMaternalGfMother, kMaternalGfFather],
            person,
          );
        }
      }
    }

    if (father != null) {
      final paternalGrand = parentsOf(father);
      for (final person in paternalGrand) {
        placePerson(visible, [kPaternalGm, kPaternalGf], person);
      }

      final paternalGm = visible[kPaternalGm];
      if (paternalGm != null) {
        final paternalGmParents = parentsOf(paternalGm);
        for (final person in paternalGmParents) {
          placePerson(
            visible,
            [kPaternalGmMother, kPaternalGmFather],
            person,
          );
        }
      }

      final paternalGf = visible[kPaternalGf];
      if (paternalGf != null) {
        final paternalGfParents = parentsOf(paternalGf);
        for (final person in paternalGfParents) {
          placePerson(
            visible,
            [kPaternalGfMother, kPaternalGfFather],
            person,
          );
        }
      }
    }

    final siblings = <Map<String, dynamic>>[];
    for (final parent in parents) {
      for (final child in childrenOf(parent)) {
        if (_samePerson(child, viewer)) continue;
        _addUniquePerson(siblings, child);
      }
    }
    siblings.sort((a, b) => _comparePeople(global, a, b));
    for (final sibling in siblings) {
      placePerson(visible, [kSibling1, kSibling2, kSibling3], sibling);
    }

    final children = childrenOf(viewer);
    for (final child in children) {
      placePerson(visible, [kChild1, kChild2, kChild3, kChild4], child);
    }

    final placedChildren = [
      visible[kChild1],
      visible[kChild2],
      visible[kChild3],
      visible[kChild4],
    ].whereType<Map<String, dynamic>>().toList();

    final grandChildren = <Map<String, dynamic>>[];
    for (final child in placedChildren) {
      for (final grandChild in childrenOf(child)) {
        _addUniquePerson(grandChildren, grandChild);
      }
    }
    grandChildren.sort((a, b) => _comparePeople(global, a, b));
    for (final grandChild in grandChildren) {
      placePerson(
        visible,
        [kGrandchild1, kGrandchild2, kGrandchild3, kGrandchild4],
        grandChild,
      );
    }

    final placedGrandChildren = [
      visible[kGrandchild1],
      visible[kGrandchild2],
      visible[kGrandchild3],
      visible[kGrandchild4],
    ].whereType<Map<String, dynamic>>().toList();

    final greatGrandChildren = <Map<String, dynamic>>[];
    for (final grandChild in placedGrandChildren) {
      for (final greatGrandChild in childrenOf(grandChild)) {
        _addUniquePerson(greatGrandChildren, greatGrandChild);
      }
    }
    greatGrandChildren.sort((a, b) => _comparePeople(global, a, b));
    for (final greatGrandChild in greatGrandChildren) {
      placePerson(
        visible,
        [
          kGreatGrandchild1,
          kGreatGrandchild2,
          kGreatGrandchild3,
          kGreatGrandchild4,
        ],
        greatGrandChild,
      );
    }

    Map<String, dynamic>? spouse;
    for (final child in placedChildren) {
      final coParents =
          parentsOf(child).where((p) => !_samePerson(p, viewer)).toList();
      if (coParents.isNotEmpty) {
        spouse = coParents.first;
        break;
      }
    }

    if (spouse != null && !_samePerson(spouse, viewer)) {
      placePerson(visible, [kSpouse1], spouse);
    }

    return visible;
  }

  Future<void> _openYourVaultFallback() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      final v = await _supabase
          .from('vaults')
          .select('id, name, display_name, owner_id')
          .eq('owner_id', uid)
          .maybeSingle();
      if (v == null) return;

      final vaultId = (v['id'] ?? '').toString();
      final vaultName = ((v['display_name'] ?? '').toString().trim().isNotEmpty
              ? v['display_name']
              : (v['name'] ?? 'Vault'))
          .toString();
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

      final inserted = await _supabase
          .from('family_invites')
          .insert({
            'family_id': widget.familyId,
            'created_by': user.id,
            'invite_code': code,
            'slot_key': slotKey,
            'expires_at': expiresAt.toIso8601String(),
            'inviter_vault_id': myVaultId,
          })
          .select('id')
          .maybeSingle();

      final inviteId = (inserted?['id'] ?? '').toString().trim();
      if (inviteId.isNotEmpty) {
        await _linkNewNodeIntoRelationships(
          slotKey: slotKey,
          newNodeType: 'invite',
          newNodeId: inviteId,
        );
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

  Future<void> _showLegacyPredecessorDialog({
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
          title: Text(_legacyDialogTitleForSlot(slotKey, title.toLowerCase())),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _legacyDialogDescriptionForSlot(slotKey),
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
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text(
                      'Optional extra details',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    children: [
                      TextField(
                        controller: deathYearController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Death year (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
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
                        final relation = _legacyRelationForSlot(slotKey);
                        final anchorPerson = _legacyAnchorPersonForSlot(slotKey);
                        final anchorRef = _nodeRefFromPerson(anchorPerson);

                        if (relation == null) {
                          throw Exception(
                            'Unsupported legacy relationship for slot: $slotKey',
                          );
                        }

                        if (anchorRef == null) {
                          throw Exception(
                            'Missing anchor person for slot: $slotKey',
                          );
                        }

                        final legacyId = await _supabase.rpc(
                          'create_legacy_relative',
                          params: {
                            'p_family_id': widget.familyId,
                            'p_anchor_type': anchorRef.nodeType,
                            'p_anchor_id': anchorRef.nodeId,
                            'p_relation': relation,
                            'p_name': name,
                            'p_display_name':
                                displayName.isEmpty ? null : displayName,
                            'p_birth_year': birthYear,
                            'p_death_year': deathYear,
                            'p_about_me_text': about.isEmpty ? null : about,
                          },
                        );

                        final createdLegacyId =
                            (legacyId ?? '').toString().trim();
                        if (createdLegacyId.isEmpty) {
                          throw Exception('Failed to create legacy relative');
                        }

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
                'Choose whether this person is a living family member to invite now, or a legacy family profile your family will build together.',
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
                title: const Text('Add legacy family profile'),
                subtitle: const Text(
                  'For someone without their own account/vault yet',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLegacyPredecessorDialog(
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

  bool _canOpenAncestorBranch(String slotKey) {
    return slotKey == kMother ||
        slotKey == kFather ||
        slotKey == kMaternalGm ||
        slotKey == kMaternalGf ||
        slotKey == kPaternalGm ||
        slotKey == kPaternalGf ||
        slotKey == kMaternalGmMother ||
        slotKey == kMaternalGmFather ||
        slotKey == kMaternalGfMother ||
        slotKey == kMaternalGfFather ||
        slotKey == kPaternalGmMother ||
        slotKey == kPaternalGmFather ||
        slotKey == kPaternalGfMother ||
        slotKey == kPaternalGfFather;
  }

  bool _canOpenDescendantBranch(String slotKey) {
    return slotKey == kChild1 ||
        slotKey == kChild2 ||
        slotKey == kChild3 ||
        slotKey == kChild4 ||
        slotKey == kGrandchild1 ||
        slotKey == kGrandchild2 ||
        slotKey == kGrandchild3 ||
        slotKey == kGrandchild4 ||
        slotKey == kGreatGrandchild1 ||
        slotKey == kGreatGrandchild2 ||
        slotKey == kGreatGrandchild3 ||
        slotKey == kGreatGrandchild4;
  }

  String? _branchDirectionForSlot(String slotKey) {
    if (_canOpenAncestorBranch(slotKey)) return 'ancestor';
    if (_canOpenDescendantBranch(slotKey)) return 'descendant';
    return null;
  }

  String _branchLabelForSlot(String slotKey) {
    switch (slotKey) {
      case kMother:
        return 'Mother';
      case kFather:
        return 'Father';
      case kMaternalGm:
      case kPaternalGm:
        return 'Grandmother';
      case kMaternalGf:
      case kPaternalGf:
        return 'Grandfather';
      case kMaternalGmMother:
      case kMaternalGfMother:
      case kPaternalGmMother:
      case kPaternalGfMother:
        return 'Great-grandmother';
      case kMaternalGmFather:
      case kMaternalGfFather:
      case kPaternalGmFather:
      case kPaternalGfFather:
        return 'Great-grandfather';
      case kChild1:
      case kChild2:
      case kChild3:
      case kChild4:
        return 'Child';
      case kGrandchild1:
      case kGrandchild2:
      case kGrandchild3:
      case kGrandchild4:
        return 'Grandchild';
      case kGreatGrandchild1:
      case kGreatGrandchild2:
      case kGreatGrandchild3:
      case kGreatGrandchild4:
        return 'Great-grandchild';
      default:
        return 'Branch';
    }
  }

  Future<void> _openDirectBranchForPerson({
    required String slotKey,
    required Map<String, dynamic> person,
  }) async {
    final direction = _branchDirectionForSlot(slotKey);
    if (direction == null) return;

    final isLegacy = person['__legacy'] == true;
    final nodeId = (person['id'] ?? '').toString().trim();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyBranchScreen(
          familyId: widget.familyId,
          rootLabel: _branchLabelForSlot(slotKey),
          rootSlotKey: slotKey,
          direction: direction,
          rootNodeType: isLegacy ? 'legacy' : 'vault',
          rootNodeId: nodeId.isEmpty ? null : nodeId,
        ),
      ),
    );

    _refresh();
  }

  Future<void> _openVaultFromTree(
    _FamilyData data,
    Map<String, dynamic> v,
  ) async {
    final uid = _supabase.auth.currentUser?.id;
    final ownerId = (v['owner_id'] ?? '').toString();
    final vaultId = (v['id'] ?? '').toString();
    final vaultName = ((v['display_name'] ?? '').toString().trim().isNotEmpty
            ? v['display_name']
            : (v['name'] ?? 'Vault'))
        .toString();

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

      final next = <String, _NodeGeom>{};
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

  Widget _buildGreatGrandparentSlot({
    required String slotKey,
    required Map<String, Map<String, dynamic>> slotVault,
    required _FamilyData data,
  }) {
    return _PersonSlot(
      key: _keyFor(slotKey),
      filled: slotVault[slotKey],
      avatarUrl: data.avatarUrlByVaultId[
          (slotVault[slotKey]?['id'] ?? '').toString()],
      onInvite: () => _openPredecessorAddOptions(
        slotKey: slotKey,
        title: 'Great-grandparent',
      ),
      onOpen: () => _openVaultFromTree(
        data,
        slotVault[slotKey]!,
      ),
      onBranchTap: slotVault[slotKey] == null
          ? null
          : () => _openDirectBranchForPerson(
                slotKey: slotKey,
                person: slotVault[slotKey]!,
              ),
      showAddLabel: 'Add great-grandparent',
    );
  }

  Widget _buildGreatGrandparentPairCard({
    required String title,
    required String leftSlotKey,
    required String rightSlotKey,
    required Map<String, Map<String, dynamic>> slotVault,
    required _FamilyData data,
  }) {
    return _GroupCard(
      title: title,
      child: Row(
        children: [
          Expanded(
            child: _buildGreatGrandparentSlot(
              slotKey: leftSlotKey,
              slotVault: slotVault,
              data: data,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildGreatGrandparentSlot(
              slotKey: rightSlotKey,
              slotVault: slotVault,
              data: data,
            ),
          ),
        ],
      ),
    );
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
            icon: const Icon(Icons.group_remove_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
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
                relationships: [],
                avatarUrlByVaultId: {},
                legacyMembers: [],
                yourVault: null,
                yourAvatarUrl: null,
                joinContext: null,
              );

          final slotVault = _slotToDisplayMap(data);
          _latestData = data;
          _latestDisplaySlots = slotVault;

          final yourVault = _yourVault(data);
          final viewer = _currentViewerPerson(data);

          final yourName = ((viewer?['display_name'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty
                  ? viewer!['display_name']
                  : (viewer?['name'] ?? 'Your vault (you)'))
              .toString();

          final yourVaultId = (viewer?['id'] ?? '').toString();
          final yourAvatarUrl = yourVaultId.isNotEmpty
              ? data.avatarUrlByVaultId[yourVaultId]
              : data.yourAvatarUrl;

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
                                  onToggle: () => setState(() {
                                    _showGreatGrandparents =
                                        !_showGreatGrandparents;
                                  }),
                                ),
                                if (_showGreatGrandparents) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildGreatGrandparentPairCard(
                                              title:
                                                  'Parents of maternal grandmother',
                                              leftSlotKey: kMaternalGmMother,
                                              rightSlotKey: kMaternalGmFather,
                                              slotVault: slotVault,
                                              data: data,
                                            ),
                                            const SizedBox(height: 12),
                                            _buildGreatGrandparentPairCard(
                                              title:
                                                  'Parents of maternal grandfather',
                                              leftSlotKey: kMaternalGfMother,
                                              rightSlotKey: kMaternalGfFather,
                                              slotVault: slotVault,
                                              data: data,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildGreatGrandparentPairCard(
                                              title:
                                                  'Parents of paternal grandmother',
                                              leftSlotKey: kPaternalGmMother,
                                              rightSlotKey: kPaternalGmFather,
                                              slotVault: slotVault,
                                              data: data,
                                            ),
                                            const SizedBox(height: 12),
                                            _buildGreatGrandparentPairCard(
                                              title:
                                                  'Parents of paternal grandfather',
                                              leftSlotKey: kPaternalGfMother,
                                              rightSlotKey: kPaternalGfFather,
                                              slotVault: slotVault,
                                              data: data,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                _SectionHeader(
                                  title: 'Grandparents',
                                  isOpen: _showGrandparents,
                                  onToggle: () => setState(() {
                                    _showGrandparents = !_showGrandparents;
                                  }),
                                ),
                                if (_showGrandparents) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGm),
                                                  filled:
                                                      slotVault[kMaternalGm],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kMaternalGm]
                                                                  ?['id'] ??
                                                              '')
                                                          .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGm,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: () =>
                                                      _openVaultFromTree(
                                                    data,
                                                    slotVault[kMaternalGm]!,
                                                  ),
                                                  onBranchTap: slotVault[
                                                              kMaternalGm] ==
                                                          null
                                                      ? null
                                                      : () =>
                                                          _openDirectBranchForPerson(
                                                            slotKey:
                                                                kMaternalGm,
                                                            person: slotVault[
                                                                kMaternalGm]!,
                                                          ),
                                                  showAddLabel:
                                                      'Add grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGf),
                                                  filled:
                                                      slotVault[kMaternalGf],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kMaternalGf]
                                                                  ?['id'] ??
                                                              '')
                                                          .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kMaternalGf,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: () =>
                                                      _openVaultFromTree(
                                                    data,
                                                    slotVault[kMaternalGf]!,
                                                  ),
                                                  onBranchTap: slotVault[
                                                              kMaternalGf] ==
                                                          null
                                                      ? null
                                                      : () =>
                                                          _openDirectBranchForPerson(
                                                            slotKey:
                                                                kMaternalGf,
                                                            person: slotVault[
                                                                kMaternalGf]!,
                                                          ),
                                                  showAddLabel:
                                                      'Add grandparent',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGm),
                                                  filled:
                                                      slotVault[kPaternalGm],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kPaternalGm]
                                                                  ?['id'] ??
                                                              '')
                                                          .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGm,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: () =>
                                                      _openVaultFromTree(
                                                    data,
                                                    slotVault[kPaternalGm]!,
                                                  ),
                                                  onBranchTap: slotVault[
                                                              kPaternalGm] ==
                                                          null
                                                      ? null
                                                      : () =>
                                                          _openDirectBranchForPerson(
                                                            slotKey:
                                                                kPaternalGm,
                                                            person: slotVault[
                                                                kPaternalGm]!,
                                                          ),
                                                  showAddLabel:
                                                      'Add grandparent',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGf),
                                                  filled:
                                                      slotVault[kPaternalGf],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kPaternalGf]
                                                                  ?['id'] ??
                                                              '')
                                                          .toString()],
                                                  onInvite: () =>
                                                      _openPredecessorAddOptions(
                                                    slotKey: kPaternalGf,
                                                    title: 'Grandparent',
                                                  ),
                                                  onOpen: () =>
                                                      _openVaultFromTree(
                                                    data,
                                                    slotVault[kPaternalGf]!,
                                                  ),
                                                  onBranchTap: slotVault[
                                                              kPaternalGf] ==
                                                          null
                                                      ? null
                                                      : () =>
                                                          _openDirectBranchForPerson(
                                                            slotKey:
                                                                kPaternalGf,
                                                            person: slotVault[
                                                                kPaternalGf]!,
                                                          ),
                                                  showAddLabel:
                                                      'Add grandparent',
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
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kMother]!,
                                          ),
                                          onBranchTap: slotVault[kMother] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kMother,
                                                    person: slotVault[kMother]!,
                                                  ),
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
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kFather]!,
                                          ),
                                          onBranchTap: slotVault[kFather] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kFather,
                                                    person: slotVault[kFather]!,
                                                  ),
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
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kSpouse1,
                                            title: 'Spouse',
                                          ),
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kSpouse1]!,
                                          ),
                                          onBranchTap: null,
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
                                          if (viewer != null) {
                                            await _openVaultFromTree(
                                              data,
                                              viewer,
                                            );
                                          } else if (yourVault != null) {
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
                                              onInvite: () =>
                                                  _openPredecessorAddOptions(
                                                slotKey: kSibling1,
                                                title: 'Sibling',
                                              ),
                                              onOpen: () => _openVaultFromTree(
                                                data,
                                                slotVault[kSibling1]!,
                                              ),
                                              onBranchTap: null,
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
                                              onInvite: () =>
                                                  _openPredecessorAddOptions(
                                                slotKey: kSibling2,
                                                title: 'Sibling',
                                              ),
                                              onOpen: () => _openVaultFromTree(
                                                data,
                                                slotVault[kSibling2]!,
                                              ),
                                              onBranchTap: null,
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
                                              onInvite: () =>
                                                  _openPredecessorAddOptions(
                                                slotKey: kSibling3,
                                                title: 'Sibling',
                                              ),
                                              onOpen: () => _openVaultFromTree(
                                                data,
                                                slotVault[kSibling3]!,
                                              ),
                                              onBranchTap: null,
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
                                  onToggle: () => setState(() {
                                    _showDescendants = !_showDescendants;
                                  }),
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
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kChild1,
                                            title: 'Child',
                                          ),
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kChild1]!,
                                          ),
                                          onBranchTap: slotVault[kChild1] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kChild1,
                                                    person: slotVault[kChild1]!,
                                                  ),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild2),
                                          text: 'Add child',
                                          filled: slotVault[kChild2],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild2]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kChild2,
                                            title: 'Child',
                                          ),
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kChild2]!,
                                          ),
                                          onBranchTap: slotVault[kChild2] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kChild2,
                                                    person: slotVault[kChild2]!,
                                                  ),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild3),
                                          text: 'Add child',
                                          filled: slotVault[kChild3],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild3]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kChild3,
                                            title: 'Child',
                                          ),
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kChild3]!,
                                          ),
                                          onBranchTap: slotVault[kChild3] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kChild3,
                                                    person: slotVault[kChild3]!,
                                                  ),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild4),
                                          text: 'Add child',
                                          filled: slotVault[kChild4],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild4]?['id'] ?? '')
                                                  .toString()],
                                          onInvite: () =>
                                              _openPredecessorAddOptions(
                                            slotKey: kChild4,
                                            title: 'Child',
                                          ),
                                          onOpen: () => _openVaultFromTree(
                                            data,
                                            slotVault[kChild4]!,
                                          ),
                                          onBranchTap: slotVault[kChild4] == null
                                              ? null
                                              : () =>
                                                  _openDirectBranchForPerson(
                                                    slotKey: kChild4,
                                                    person: slotVault[kChild4]!,
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _SectionHeader(
                                    title: 'Grandkids',
                                    isOpen: _showGrandkids,
                                    onToggle: () => setState(() {
                                      _showGrandkids = !_showGrandkids;
                                    }),
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
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGrandchild1,
                                              title: 'Grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGrandchild1]!,
                                            ),
                                            onBranchTap:
                                                slotVault[kGrandchild1] == null
                                                    ? null
                                                    : () =>
                                                        _openDirectBranchForPerson(
                                                          slotKey: kGrandchild1,
                                                          person: slotVault[
                                                              kGrandchild1]!,
                                                        ),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild2),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild2],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild2]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGrandchild2,
                                              title: 'Grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGrandchild2]!,
                                            ),
                                            onBranchTap:
                                                slotVault[kGrandchild2] == null
                                                    ? null
                                                    : () =>
                                                        _openDirectBranchForPerson(
                                                          slotKey: kGrandchild2,
                                                          person: slotVault[
                                                              kGrandchild2]!,
                                                        ),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild3),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild3],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild3]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGrandchild3,
                                              title: 'Grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGrandchild3]!,
                                            ),
                                            onBranchTap:
                                                slotVault[kGrandchild3] == null
                                                    ? null
                                                    : () =>
                                                        _openDirectBranchForPerson(
                                                          slotKey: kGrandchild3,
                                                          person: slotVault[
                                                              kGrandchild3]!,
                                                        ),
                                          ),
                                          _SmallInviteSlot(
                                            key: _keyFor(kGrandchild4),
                                            text: 'Add grandchild',
                                            filled: slotVault[kGrandchild4],
                                            avatarUrl: data.avatarUrlByVaultId[
                                                (slotVault[kGrandchild4]?['id'] ??
                                                        '')
                                                    .toString()],
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGrandchild4,
                                              title: 'Grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGrandchild4]!,
                                            ),
                                            onBranchTap:
                                                slotVault[kGrandchild4] == null
                                                    ? null
                                                    : () =>
                                                        _openDirectBranchForPerson(
                                                          slotKey: kGrandchild4,
                                                          person: slotVault[
                                                              kGrandchild4]!,
                                                        ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  _SectionHeader(
                                    title: 'Great-grandkids',
                                    isOpen: _showGreatGrandkids,
                                    onToggle: () => setState(() {
                                      _showGreatGrandkids =
                                          !_showGreatGrandkids;
                                    }),
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
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGreatGrandchild1,
                                              title: 'Great-grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGreatGrandchild1]!,
                                            ),
                                            onBranchTap: slotVault[
                                                        kGreatGrandchild1] ==
                                                    null
                                                ? null
                                                : () =>
                                                    _openDirectBranchForPerson(
                                                      slotKey:
                                                          kGreatGrandchild1,
                                                      person: slotVault[
                                                          kGreatGrandchild1]!,
                                                    ),
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
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGreatGrandchild2,
                                              title: 'Great-grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGreatGrandchild2]!,
                                            ),
                                            onBranchTap: slotVault[
                                                        kGreatGrandchild2] ==
                                                    null
                                                ? null
                                                : () =>
                                                    _openDirectBranchForPerson(
                                                      slotKey:
                                                          kGreatGrandchild2,
                                                      person: slotVault[
                                                          kGreatGrandchild2]!,
                                                    ),
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
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGreatGrandchild3,
                                              title: 'Great-grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGreatGrandchild3]!,
                                            ),
                                            onBranchTap: slotVault[
                                                        kGreatGrandchild3] ==
                                                    null
                                                ? null
                                                : () =>
                                                    _openDirectBranchForPerson(
                                                      slotKey:
                                                          kGreatGrandchild3,
                                                      person: slotVault[
                                                          kGreatGrandchild3]!,
                                                    ),
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
                                            onInvite: () =>
                                                _openPredecessorAddOptions(
                                              slotKey: kGreatGrandchild4,
                                              title: 'Great-grandchild',
                                            ),
                                            onOpen: () => _openVaultFromTree(
                                              data,
                                              slotVault[kGreatGrandchild4]!,
                                            ),
                                            onBranchTap: slotVault[
                                                        kGreatGrandchild4] ==
                                                    null
                                                ? null
                                                : () =>
                                                    _openDirectBranchForPerson(
                                                      slotKey:
                                                          kGreatGrandchild4,
                                                      person: slotVault[
                                                          kGreatGrandchild4]!,
                                                    ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 54,
                                  child: CustomPaint(
                                    painter: _BottomVinesPainter(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: Text(
                                    'Your tree grows as more people are added.',
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
  final VoidCallback onOpen;
  final VoidCallback? onBranchTap;
  final String showAddLabel;

  const _PersonSlot({
    super.key,
    required this.filled,
    required this.avatarUrl,
    required this.onInvite,
    required this.onOpen,
    required this.onBranchTap,
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
      onTap: has ? onOpen : onInvite,
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
            if (has && onBranchTap != null)
              IconButton(
                tooltip: 'Open branch',
                onPressed: onBranchTap,
                icon: const Icon(Icons.account_tree_outlined, size: 20),
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
  final VoidCallback onOpen;
  final VoidCallback? onBranchTap;

  const _SmallInviteSlot({
    super.key,
    required this.text,
    required this.filled,
    required this.avatarUrl,
    required this.onInvite,
    required this.onOpen,
    required this.onBranchTap,
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
      onTap: has ? onOpen : onInvite,
      child: Container(
        width: 210,
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
            if (has && onBranchTap != null)
              InkWell(
                onTap: onBranchTap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: Colors.black.withOpacity(0.72),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
      line('maternal_gm_mother', 'maternal_gm');
      line('maternal_gm_father', 'maternal_gm');
      line('maternal_gf_mother', 'maternal_gf');
      line('maternal_gf_father', 'maternal_gf');

      line('paternal_gm_mother', 'paternal_gm');
      line('paternal_gm_father', 'paternal_gm');
      line('paternal_gf_mother', 'paternal_gf');
      line('paternal_gf_father', 'paternal_gf');
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
        line('child_1', 'grandchild_1');
        line('child_2', 'grandchild_2');
        line('child_3', 'grandchild_3');
        line('child_4', 'grandchild_4');
      }

      if (showGreatGrandkids) {
        line('grandchild_1', 'greatgrandchild_1');
        line('grandchild_2', 'greatgrandchild_2');
        line('grandchild_3', 'greatgrandchild_3');
        line('grandchild_4', 'greatgrandchild_4');
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

class _JoinContext {
  final String inviterVaultId;
  final String slotKey;

  const _JoinContext({
    required this.inviterVaultId,
    required this.slotKey,
  });
}

class _FamilyData {
  final List<Map<String, dynamic>> vaults;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> relationships;
  final Map<String, String> avatarUrlByVaultId;
  final List<Map<String, dynamic>> legacyMembers;
  final Map<String, dynamic>? yourVault;
  final String? yourAvatarUrl;
  final _JoinContext? joinContext;

  const _FamilyData({
    required this.vaults,
    required this.members,
    required this.relationships,
    required this.avatarUrlByVaultId,
    required this.legacyMembers,
    required this.yourVault,
    required this.yourAvatarUrl,
    required this.joinContext,
  });
}

class _RelationshipNodeRef {
  final String nodeType;
  final String nodeId;

  const _RelationshipNodeRef({
    required this.nodeType,
    required this.nodeId,
  });
}

class _RelationshipAnchorSpec {
  final String? anchorSlotKey;
  final bool anchorIsViewer;
  final bool newNodeIsParent;
  final String relationshipKind;

  const _RelationshipAnchorSpec({
    required this.anchorSlotKey,
    required this.anchorIsViewer,
    required this.newNodeIsParent,
    required this.relationshipKind,
  });
}