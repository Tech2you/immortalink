import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_vault_screen.dart';
import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';

class FamilyBranchScreen extends StatefulWidget {
  final String familyId;
  final String focusSlotKey;
  final String focusTitle;
  final String direction; // 'ancestor' or 'descendant'

  const FamilyBranchScreen({
    super.key,
    required this.familyId,
    required this.focusSlotKey,
    required this.focusTitle,
    required this.direction,
  });

  @override
  State<FamilyBranchScreen> createState() => _FamilyBranchScreenState();
}

class _FamilyBranchScreenState extends State<FamilyBranchScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';

  late Future<_BranchData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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

  Future<_BranchData> _load() async {
    final user = _supabase.auth.currentUser;

    List<Map<String, dynamic>> vaults = [];
    List<Map<String, dynamic>> members = [];
    List<Map<String, dynamic>> legacyMembers = [];

    try {
      final familyVaultRes = await _supabase
          .from('vaults')
          .select('id, name, owner_id, family_id, created_at, avatar_path')
          .eq('family_id', widget.familyId);

      vaults = (familyVaultRes as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    try {
      final memberRes = await _supabase
          .from('family_members')
          .select('user_id, slot_key, role, joined_at')
          .eq('family_id', widget.familyId);

      members = (memberRes as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    try {
      final legacyRes = await _supabase
          .from('legacy_family_members')
          .select(
            'id, family_id, slot_key, name, display_name, birth_year, death_year, created_by, created_at, updated_at, replaced_by_vault_id',
          )
          .eq('family_id', widget.familyId);

      legacyMembers = (legacyRes as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    final Map<String, String> avatarUrlById = {};

    for (final v in vaults) {
      final id = (v['id'] ?? '').toString();
      final path = (v['avatar_path'] ?? '').toString().trim();
      if (id.isEmpty || path.isEmpty) continue;

      final url = await _signedAvatarUrl(path);
      if (url != null && url.trim().isNotEmpty) {
        avatarUrlById[id] = url;
      }
    }

    return _BranchData(
      currentUserId: user?.id,
      vaults: vaults,
      members: members,
      legacyMembers: legacyMembers,
      avatarUrlById: avatarUrlById,
    );
  }

  Map<String, Map<String, dynamic>> _slotToDisplayMap(_BranchData data) {
    final Map<String, Map<String, dynamic>> vaultByUser = {};
    for (final v in data.vaults) {
      final ownerId = (v['owner_id'] ?? '').toString();
      if (ownerId.isNotEmpty) vaultByUser[ownerId] = v;
    }

    final Map<String, Map<String, dynamic>> out = {};
    for (final m in data.members) {
      final slotKey = (m['slot_key'] ?? '').toString().trim();
      final userId = (m['user_id'] ?? '').toString().trim();
      if (slotKey.isEmpty || userId.isEmpty) continue;

      final v = vaultByUser[userId];
      if (v != null) out[slotKey] = v;
    }

    for (final legacy in data.legacyMembers) {
      final slotKey = (legacy['slot_key'] ?? '').toString().trim();
      if (slotKey.isEmpty) continue;
      if (out.containsKey(slotKey)) continue;

      out[slotKey] = {
        ...legacy,
        '__legacy': true,
      };
    }

    return out;
  }

  String? _avatarFor(Map<String, dynamic>? person, _BranchData data) {
    if (person == null) return null;
    final isLegacy = person['__legacy'] == true;
    if (isLegacy) return null;

    final id = (person['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return data.avatarUrlById[id];
  }

  String _labelFor(Map<String, dynamic>? person, String fallback) {
    if (person == null) return fallback;

    final display = (person['display_name'] ?? '').toString().trim();
    final name = (person['name'] ?? '').toString().trim();

    if (display.isNotEmpty) return display;
    if (name.isNotEmpty) return name;
    return fallback;
  }

  String _normalizeAncestorParentSlot(String slotKey) {
    switch (slotKey) {
      case 'mother':
      case 'maternal_gm':
      case 'maternal_ggm':
        return 'mother';
      case 'father':
      case 'maternal_gf':
      case 'maternal_ggf':
        return 'father';
      case 'paternal_gm':
      case 'paternal_ggm':
        return 'mother';
      case 'paternal_gf':
      case 'paternal_ggf':
        return 'father';
      default:
        return '';
    }
  }

  List<String> _ancestorParentsFor(String slotKey) {
    switch (slotKey) {
      case 'mother':
        return ['maternal_gm', 'maternal_gf'];
      case 'father':
        return ['paternal_gm', 'paternal_gf'];
      case 'maternal_gm':
        return ['maternal_ggm', 'maternal_ggf'];
      case 'paternal_gm':
        return ['paternal_ggm', 'paternal_ggf'];
      default:
        return [];
    }
  }

  List<String> _descendantChildrenFor(String slotKey) {
    switch (slotKey) {
      case 'child_1':
      case 'child_2':
      case 'child_3':
      case 'child_4':
        return ['grandchild_1', 'grandchild_2', 'grandchild_3', 'grandchild_4'];
      case 'grandchild_1':
      case 'grandchild_2':
      case 'grandchild_3':
      case 'grandchild_4':
        return [
          'greatgrandchild_1',
          'greatgrandchild_2',
          'greatgrandchild_3',
          'greatgrandchild_4',
        ];
      default:
        return [];
    }
  }

  Future<void> _openPerson(Map<String, dynamic> person) async {
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

      if (!mounted) return;
      setState(() {
        _future = _load();
      });
      return;
    }

    final vaultId = (person['id'] ?? '').toString();
    final vaultName = (person['name'] ?? 'Vault').toString();
    final ownerId = (person['owner_id'] ?? '').toString();
    final uid = _supabase.auth.currentUser?.id;

    if (vaultId.isEmpty) return;

    if (uid != null && uid == ownerId) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VaultHomeScreen(vaultId: vaultId, vaultName: vaultName),
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

    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAncestorMode = widget.direction == 'ancestor';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusTitle),
      ),
      body: FutureBuilder<_BranchData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ??
              const _BranchData(
                currentUserId: null,
                vaults: [],
                members: [],
                legacyMembers: [],
                avatarUrlById: {},
              );

          final slotMap = _slotToDisplayMap(data);

          final focus = slotMap[widget.focusSlotKey];
          final focusLabel = _labelFor(focus, widget.focusTitle);

          final List<Map<String, dynamic>?> topPeople = [];
          final List<Map<String, dynamic>?> bottomPeople = [];

          if (isAncestorMode) {
            final parentSlots = _ancestorParentsFor(widget.focusSlotKey);
            for (final s in parentSlots) {
              topPeople.add(slotMap[s]);
            }
          } else {
            final childSlots = _descendantChildrenFor(widget.focusSlotKey);
            for (final s in childSlots) {
              bottomPeople.add(slotMap[s]);
            }
          }

          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: 0.07,
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
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      isAncestorMode ? 'Ancestor Branch' : 'Descendant Branch',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      focusLabel,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black.withOpacity(0.60),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (topPeople.isNotEmpty) ...[
                    _BranchSectionCard(
                      title: 'Above',
                      child: Row(
                        children: topPeople.map((p) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _BranchPersonCard(
                                label: _labelFor(p, 'Open slot'),
                                avatarUrl: _avatarFor(p, data),
                                isFilled: p != null,
                                onTap: p == null ? null : () => _openPerson(p),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _BranchSectionCard(
                    title: 'Focus',
                    child: Center(
                      child: SizedBox(
                        width: 280,
                        child: _BranchPersonCard(
                          label: focusLabel,
                          avatarUrl: _avatarFor(focus, data),
                          isFilled: focus != null,
                          onTap: focus == null ? null : () => _openPerson(focus),
                          isFocus: true,
                        ),
                      ),
                    ),
                  ),
                  if (bottomPeople.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _BranchSectionCard(
                      title: 'Below',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: bottomPeople.map((p) {
                          return SizedBox(
                            width: 220,
                            child: _BranchPersonCard(
                              label: _labelFor(p, 'Open slot'),
                              avatarUrl: _avatarFor(p, data),
                              isFilled: p != null,
                              onTap: p == null ? null : () => _openPerson(p),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      isAncestorMode
                          ? 'This branch can later keep expanding upward.'
                          : 'This branch can later keep expanding downward.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.50),
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

class _BranchSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _BranchSectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BranchPersonCard extends StatelessWidget {
  final String label;
  final String? avatarUrl;
  final bool isFilled;
  final bool isFocus;
  final VoidCallback? onTap;

  const _BranchPersonCard({
    required this.label,
    required this.avatarUrl,
    required this.isFilled,
    required this.onTap,
    this.isFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: isFocus ? 130 : 96,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
          color: Colors.white.withOpacity(isFocus ? 0.42 : 0.34),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AvatarBubble(
              url: avatarUrl,
              radius: isFocus ? 24 : 18,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isFilled ? FontWeight.w800 : FontWeight.w600,
                fontSize: isFocus ? 16 : 14,
                color: Colors.black.withOpacity(0.80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final String? url;
  final double radius;

  const _AvatarBubble({
    required this.url,
    required this.radius,
  });

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

class _BranchData {
  final String? currentUserId;
  final List<Map<String, dynamic>> vaults;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> legacyMembers;
  final Map<String, String> avatarUrlById;

  const _BranchData({
    required this.currentUserId,
    required this.vaults,
    required this.members,
    required this.legacyMembers,
    required this.avatarUrlById,
  });
}