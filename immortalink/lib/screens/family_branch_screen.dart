import 'package:flutter/material.dart';
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

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _vaults = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _legacyMembers = [];
  final Map<String, String> _avatarUrlByVaultId = {};

  @override
  void initState() {
    super.initState();
    _load();
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
            'id, family_id, slot_key, name, display_name, birth_year, death_year, created_at, updated_at, replaced_by_vault_id',
          )
          .eq('family_id', widget.familyId);

      final vaults = (vaultRes as List).cast<Map<String, dynamic>>();
      final members = (memberRes as List).cast<Map<String, dynamic>>();
      final legacyMembers = (legacyRes as List).cast<Map<String, dynamic>>();

      final avatarMap = <String, String>{};
      for (final v in vaults) {
        final id = (v['id'] ?? '').toString();
        final path = (v['avatar_path'] ?? '').toString().trim();
        if (id.isEmpty || path.isEmpty) continue;
        final url = await _signedAvatarUrl(path);
        if (url != null && url.trim().isNotEmpty) {
          avatarMap[id] = url;
        }
      }

      if (!mounted) return;
      setState(() {
        _vaults = vaults;
        _members = members;
        _legacyMembers = legacyMembers;
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
      if (slotKey.isEmpty) continue;
      result.putIfAbsent(slotKey, () => {
            ...legacy,
            '__legacy': true,
          });
    }

    return result;
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
        slotKey == 'paternal_gf';
  }

  bool _canOpenDescendantBranch(String slotKey) {
    return slotKey == 'child_1' ||
        slotKey == 'child_2' ||
        slotKey == 'child_3' ||
        slotKey == 'child_4' ||
        slotKey == 'grandchild_1' ||
        slotKey == 'grandchild_2' ||
        slotKey == 'grandchild_3' ||
        slotKey == 'grandchild_4';
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
    if (person['__legacy'] == true) return null;
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
                                      subtitle: isAncestor
                                          ? 'This branch focuses on one ancestral line.'
                                          : 'This branch focuses on one descendant line.',
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
                                        title: isAncestor
                                            ? 'One generation further back'
                                            : 'Next generation in this line',
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
                                                      slotKey:
                                                          config.primarySlots[i],
                                                      person: primaryPeople[i]!,
                                                    ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (config.secondarySlots.isNotEmpty) ...[
                                      const SizedBox(height: 18),
                                      _BranchSectionTitle(
                                        title: isAncestor
                                            ? 'Further ancestors'
                                            : 'Future descendants',
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
                                            avatarUrl:
                                                _avatarFor(secondaryPeople[i]),
                                            onTap: secondaryPeople[i] == null
                                                ? null
                                                : () => _openBranchOptions(
                                                      slotKey:
                                                          config.secondarySlots[i],
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
                                          'This branch view is now recursive, so you can keep opening deeper branches from here without changing the main family tree home screen.',
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