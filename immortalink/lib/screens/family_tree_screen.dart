import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'vault_readonly_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String familyId;

  const FamilyTreeScreen({super.key, required this.familyId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final _supabase = Supabase.instance.client;

  static const String _logoPath = 'assets/images/immortalink_logo.png';

  // Slots
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

  bool _showGrandparents = true;
  bool _showDescendants = true;

  // For drawing lines based on actual widget positions
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
      // cache-bust (Flutter web likes caching)
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<_FamilyData> _loadFamilyData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const _FamilyData(
        vaults: [],
        members: [],
        avatarUrlByVaultId: {},
        yourVault: null,
        yourAvatarUrl: null,
      );
    }

    List<Map<String, dynamic>> vaults = [];
    Map<String, dynamic>? myVaultMap;

    // 1) Vaults linked to THIS family (don’t let failure kill everything)
    try {
      final familyVaultRes = await _supabase
          .from('vaults')
          .select('id, name, owner_id, family_id, created_at, avatar_path')
          .eq('family_id', widget.familyId);

      vaults = (familyVaultRes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      vaults = [];
    }

    // 2) Always fetch YOUR vault by owner_id (robust)
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
    } catch (_) {
      // keep going
    }

    // 3) Signed avatar urls for any vaults that have avatar_path
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

    // 4) Special: ensure YOUR avatar url is computed even if list lookups fail
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

    // 5) Family members (slot positions) — if policy breaks, we still show your vault
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

    return _FamilyData(
      vaults: vaults,
      members: members,
      avatarUrlByVaultId: avatarUrlByVaultId,
      yourVault: myVaultMap,
      yourAvatarUrl: yourAvatarUrl,
    );
  }

  void _refresh() {
    setState(() {
      _future = _loadFamilyData();
    });
  }

  Map<String, Map<String, dynamic>> _slotToVaultMap(_FamilyData data) {
    // owner_id -> vault
    final Map<String, Map<String, dynamic>> vaultByUser = {};
    for (final v in data.vaults) {
      final ownerId = (v['owner_id'] ?? '').toString();
      if (ownerId.isNotEmpty) vaultByUser[ownerId] = v;
    }

    // slot_key -> vault
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
          builder: (_) => VaultHomeScreen(vaultId: vaultId, vaultName: vaultName),
        ),
      );

      // IMPORTANT: refresh when returning so avatar updates appear
      _refresh();
    } catch (_) {
      // silent MVP
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

      await _supabase.from('family_invites').insert({
        'family_id': widget.familyId,
        'created_by': user.id,
        'invite_code': code,
        'slot_key': slotKey,
      });

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite created'),
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

  Future<void> _openVaultFromTree(_FamilyData data, Map<String, dynamic> v) async {
    final uid = _supabase.auth.currentUser?.id;
    final ownerId = (v['owner_id'] ?? '').toString();
    final vaultId = (v['id'] ?? '').toString();
    final vaultName = (v['name'] ?? 'Vault').toString();

    if (vaultId.isEmpty) return;

    if (!mounted) return;

    if (uid != null && ownerId == uid) {
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
          builder: (_) => VaultReadOnlyScreen(vaultId: vaultId, vaultName: vaultName),
        ),
      );
    }

    // IMPORTANT: refresh when returning so avatar updates appear
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
                yourVault: null,
                yourAvatarUrl: null,
              );

          final slotVault = _slotToVaultMap(data);

          final yourVault = _yourVault(data);
          final yourName = (yourVault?['name'] ?? 'Your vault (you)').toString();
          final yourVaultId = (yourVault?['id'] ?? '').toString();

          final yourAvatarUrl =
              (data.yourAvatarUrl != null && data.yourAvatarUrl!.trim().isNotEmpty)
                  ? data.yourAvatarUrl
                  : (yourVaultId.isNotEmpty ? data.avatarUrlByVaultId[yourVaultId] : null);

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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                      'Your Family Tree (MVP)',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
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
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                          color: Colors.white.withOpacity(0.22),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _TreeLinesPainter(
                                  geom: _geom,
                                  showGrandparents: _showGrandparents,
                                  showDescendants: _showDescendants,
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                _SectionHeader(
                                  title: 'Grandparents',
                                  isOpen: _showGrandparents,
                                  onToggle: () =>
                                      setState(() => _showGrandparents = !_showGrandparents),
                                ),
                                if (_showGrandparents) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Maternal Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGm),
                                                  filled: slotVault[kMaternalGm],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kMaternalGm]?['id'] ?? '')
                                                          .toString()],
                                                  onInvite: () => _createInvite(
                                                    slotKey: kMaternalGm,
                                                    title: 'Maternal Grandmom',
                                                  ),
                                                  onOpen: (v) => _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandmom',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGf),
                                                  filled: slotVault[kMaternalGf],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kMaternalGf]?['id'] ?? '')
                                                          .toString()],
                                                  onInvite: () => _createInvite(
                                                    slotKey: kMaternalGf,
                                                    title: 'Maternal Granddad',
                                                  ),
                                                  onOpen: (v) => _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add granddad',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _GroupCard(
                                          title: 'Paternal Grandparents',
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGm),
                                                  filled: slotVault[kPaternalGm],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kPaternalGm]?['id'] ?? '')
                                                          .toString()],
                                                  onInvite: () => _createInvite(
                                                    slotKey: kPaternalGm,
                                                    title: 'Paternal Grandmom',
                                                  ),
                                                  onOpen: (v) => _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add grandmom',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGf),
                                                  filled: slotVault[kPaternalGf],
                                                  avatarUrl: data.avatarUrlByVaultId[
                                                      (slotVault[kPaternalGf]?['id'] ?? '')
                                                          .toString()],
                                                  onInvite: () => _createInvite(
                                                    slotKey: kPaternalGf,
                                                    title: 'Paternal Granddad',
                                                  ),
                                                  onOpen: (v) => _openVaultFromTree(data, v),
                                                  showAddLabel: 'Add granddad',
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
                                              (slotVault[kMother]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kMother, title: 'Mom'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                          showAddLabel: 'Add mom',
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      SizedBox(
                                        width: 220,
                                        child: _PersonSlot(
                                          key: _keyFor(kFather),
                                          filled: slotVault[kFather],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kFather]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kFather, title: 'Dad'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                          showAddLabel: 'Add dad',
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
                                              (slotVault[kSpouse1]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kSpouse1, title: 'Spouse'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
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
                                            await _openVaultFromTree(data, yourVault);
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
                                                  (slotVault[kSibling1]?['id'] ?? '').toString()],
                                              onInvite: () => _createInvite(
                                                  slotKey: kSibling1, title: 'Sibling 1'),
                                              onOpen: (v) => _openVaultFromTree(data, v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling2),
                                              filled: slotVault[kSibling2],
                                              avatarUrl: data.avatarUrlByVaultId[
                                                  (slotVault[kSibling2]?['id'] ?? '').toString()],
                                              onInvite: () => _createInvite(
                                                  slotKey: kSibling2, title: 'Sibling 2'),
                                              onOpen: (v) => _openVaultFromTree(data, v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling3),
                                              filled: slotVault[kSibling3],
                                              avatarUrl: data.avatarUrlByVaultId[
                                                  (slotVault[kSibling3]?['id'] ?? '').toString()],
                                              onInvite: () => _createInvite(
                                                  slotKey: kSibling3, title: 'Sibling 3'),
                                              onOpen: (v) => _openVaultFromTree(data, v),
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
                                  onToggle: () =>
                                      setState(() => _showDescendants = !_showDescendants),
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
                                              (slotVault[kChild1]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kChild1, title: 'Child 1'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild2),
                                          text: 'Add child',
                                          filled: slotVault[kChild2],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild2]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kChild2, title: 'Child 2'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild3),
                                          text: 'Add child',
                                          filled: slotVault[kChild3],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild3]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kChild3, title: 'Child 3'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild4),
                                          text: 'Add child',
                                          filled: slotVault[kChild4],
                                          avatarUrl: data.avatarUrlByVaultId[
                                              (slotVault[kChild4]?['id'] ?? '').toString()],
                                          onInvite: () =>
                                              _createInvite(slotKey: kChild4, title: 'Child 4'),
                                          onOpen: (v) => _openVaultFromTree(data, v),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                SizedBox(height: 54, child: CustomPaint(painter: _BottomVinesPainter())),
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
                Icon(Icons.keyboard_arrow_down, color: Colors.black.withOpacity(0.35)),
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
      child: Icon(Icons.person, size: radius, color: Colors.black.withOpacity(0.55)),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(0.55))),
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
                    child: Icon(Icons.add, color: Colors.black.withOpacity(0.65)),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                has ? ((filled!['name'] ?? 'Vault').toString()) : showAddLabel,
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
                    child: Icon(Icons.add, color: Colors.black.withOpacity(0.65), size: 18),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                has ? ((filled!['name'] ?? 'Child').toString()) : text,
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
  final bool showGrandparents;
  final bool showDescendants;

  const _TreeLinesPainter({
    required this.geom,
    required this.showGrandparents,
    required this.showDescendants,
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
      if (c(a) == null || c(b) == null || s(a) == null || s(b) == null) return;
      final p1 = edgePoint(a, b);
      final p2 = edgePoint(b, a);
      canvas.drawLine(p1, p2, paint);
    }

    const you = 'you';

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
    }
  }

  @override
  bool shouldRepaint(covariant _TreeLinesPainter oldDelegate) {
    return oldDelegate.geom != geom ||
        oldDelegate.showGrandparents != showGrandparents ||
        oldDelegate.showDescendants != showDescendants;
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
      ..cubicTo(size.width * 0.22, y1 - 10, size.width * 0.38, y1 + 14,
          size.width * 0.52, y1)
      ..cubicTo(size.width * 0.70, y1 - 16, size.width * 0.84, y1 + 10,
          size.width, y1);

    final path2 = Path()
      ..moveTo(0, y2)
      ..cubicTo(size.width * 0.18, y2 + 8, size.width * 0.42, y2 - 12,
          size.width * 0.60, y2)
      ..cubicTo(size.width * 0.78, y2 + 14, size.width * 0.92, y2 - 6,
          size.width, y2);

    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FamilyData {
  final List<Map<String, dynamic>> vaults;
  final List<Map<String, dynamic>> members;
  final Map<String, String> avatarUrlByVaultId;

  // Explicit “you” (by owner_id), for robustness
  final Map<String, dynamic>? yourVault;
  final String? yourAvatarUrl;

  const _FamilyData({
    required this.vaults,
    required this.members,
    required this.avatarUrlByVaultId,
    required this.yourVault,
    required this.yourAvatarUrl,
  });
}
