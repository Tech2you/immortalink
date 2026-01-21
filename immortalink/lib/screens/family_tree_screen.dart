import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String familyId;

  const FamilyTreeScreen({super.key, required this.familyId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final _supabase = Supabase.instance.client;

  // Must match pubspec EXACTLY
  static const String _logoPath = 'assets/images/immortalink_logo.png';

  // Slots (new system)
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

  // Collapsible sections
  bool _showGrandparents = true;
  bool _showDescendants = true;

  // For drawing lines based on actual widget positions
  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _nodeKeys = {};
  Map<String, _NodeGeom> _geom = {};

  // Data caches
  late Future<_FamilyData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadFamilyData();
  }

  Future<_FamilyData> _loadFamilyData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return _FamilyData(vaults: const [], members: const []);
    }

    // Vaults in family
    final vaultRes = await _supabase
        .from('vaults')
        .select('id, name, owner_id, family_id, created_at')
        .eq('family_id', widget.familyId);

    final vaults = (vaultRes as List).cast<Map<String, dynamic>>();

    // Members (slot placements live here)
    final memberRes = await _supabase
        .from('family_members')
        .select('user_id, slot_key, role, joined_at')
        .eq('family_id', widget.familyId);

    final members = (memberRes as List).cast<Map<String, dynamic>>();

    return _FamilyData(vaults: vaults, members: members);
  }

  void _refresh() {
    setState(() {
      _future = _loadFamilyData();
    });
  }

  Map<String, Map<String, dynamic>> _slotToVaultMap(_FamilyData data) {
    // Build lookup: user_id -> vault
    final Map<String, Map<String, dynamic>> vaultByUser = {};
    for (final v in data.vaults) {
      final ownerId = v['owner_id'] as String?;
      if (ownerId != null) vaultByUser[ownerId] = v;
    }

    // Build slot_key -> vault
    final Map<String, Map<String, dynamic>> slotVault = {};
    for (final m in data.members) {
      final slotKey = m['slot_key'] as String?;
      final userId = m['user_id'] as String?;
      if (slotKey == null || userId == null) continue;
      final v = vaultByUser[userId];
      if (v != null) slotVault[slotKey] = v;
    }

    return slotVault;
  }

  Map<String, dynamic>? _yourVault(_FamilyData data) {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    for (final v in data.vaults) {
      if (v['owner_id'] == uid) return v;
    }
    return null;
  }

  // Generate a readable invite code (MVP)
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusing O/0/I/1
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

  void _openVault(Map<String, dynamic> v) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          vaultId: v['id'] as String,
          vaultName: (v['name'] as String?) ?? 'Vault',
        ),
      ),
    );
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
          )
        ],
      ),
      body: FutureBuilder<_FamilyData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data ?? _FamilyData(vaults: const [], members: const []);
          final slotVault = _slotToVaultMap(data);

          final yourVault = _yourVault(data);
          final yourName = (yourVault?['name'] as String?) ?? 'Your vault (you)';

          // Build UI then compute actual line endpoints
          _recalcGeometry();

          return Stack(
            children: [
              // Background watermark
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

                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Family ID: ${widget.familyId}',
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
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
                                // GRANDPARENTS ROW
                                _SectionHeader(
                                  title: 'Grandparents',
                                  isOpen: _showGrandparents,
                                  onToggle: () => setState(() => _showGrandparents = !_showGrandparents),
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
                                                  label: 'Grandmom',
                                                  filled: slotVault[kMaternalGm],
                                                  onInvite: () => _createInvite(slotKey: kMaternalGm, title: 'Maternal Grandmom'),
                                                  onOpen: (v) => _openVault(v),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kMaternalGf),
                                                  label: 'Granddad',
                                                  filled: slotVault[kMaternalGf],
                                                  onInvite: () => _createInvite(slotKey: kMaternalGf, title: 'Maternal Granddad'),
                                                  onOpen: (v) => _openVault(v),
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
                                                  label: 'Grandmom',
                                                  filled: slotVault[kPaternalGm],
                                                  onInvite: () => _createInvite(slotKey: kPaternalGm, title: 'Paternal Grandmom'),
                                                  onOpen: (v) => _openVault(v),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: _PersonSlot(
                                                  key: _keyFor(kPaternalGf),
                                                  label: 'Granddad',
                                                  filled: slotVault[kPaternalGf],
                                                  onInvite: () => _createInvite(slotKey: kPaternalGf, title: 'Paternal Granddad'),
                                                  onOpen: (v) => _openVault(v),
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

                                // PARENTS ROW (directly above your vault)
                                _GroupCard(
                                  title: 'Parents',
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 220,
                                        child: _PersonSlot(
                                          key: _keyFor(kMother),
                                          label: 'Mom',
                                          filled: slotVault[kMother],
                                          onInvite: () => _createInvite(slotKey: kMother, title: 'Mom'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      SizedBox(
                                        width: 220,
                                        child: _PersonSlot(
                                          key: _keyFor(kFather),
                                          label: 'Dad',
                                          filled: slotVault[kFather],
                                          onInvite: () => _createInvite(slotKey: kFather, title: 'Dad'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // SPOUSE / YOU / SIBLINGS ROW
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _GroupCard(
                                        title: 'Spouse',
                                        child: _PersonSlot(
                                          key: _keyFor(kSpouse1),
                                          label: 'Spouse',
                                          filled: slotVault[kSpouse1],
                                          onInvite: () => _createInvite(slotKey: kSpouse1, title: 'Spouse'),
                                          onOpen: (v) => _openVault(v),
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
                                        subtitle: 'Ross',
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
                                              label: 'Sibling',
                                              filled: slotVault[kSibling1],
                                              onInvite: () => _createInvite(slotKey: kSibling1, title: 'Sibling 1'),
                                              onOpen: (v) => _openVault(v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling2),
                                              label: 'Sibling',
                                              filled: slotVault[kSibling2],
                                              onInvite: () => _createInvite(slotKey: kSibling2, title: 'Sibling 2'),
                                              onOpen: (v) => _openVault(v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                            const SizedBox(height: 10),
                                            _PersonSlot(
                                              key: _keyFor(kSibling3),
                                              label: 'Sibling',
                                              filled: slotVault[kSibling3],
                                              onInvite: () => _createInvite(slotKey: kSibling3, title: 'Sibling 3'),
                                              onOpen: (v) => _openVault(v),
                                              showAddLabel: 'Add sibling',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // DESCENDANTS
                                _SectionHeader(
                                  title: 'Descendants',
                                  isOpen: _showDescendants,
                                  onToggle: () => setState(() => _showDescendants = !_showDescendants),
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
                                          onInvite: () => _createInvite(slotKey: kChild1, title: 'Child 1'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild2),
                                          text: 'Add child',
                                          filled: slotVault[kChild2],
                                          onInvite: () => _createInvite(slotKey: kChild2, title: 'Child 2'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild3),
                                          text: 'Add child',
                                          filled: slotVault[kChild3],
                                          onInvite: () => _createInvite(slotKey: kChild3, title: 'Child 3'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                        _SmallInviteSlot(
                                          key: _keyFor(kChild4),
                                          text: 'Add child',
                                          filled: slotVault[kChild4],
                                          onInvite: () => _createInvite(slotKey: kChild4, title: 'Child 4'),
                                          onOpen: (v) => _openVault(v),
                                        ),
                                      ],
                                    ),
                                  ),
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

                                // Debug list (optional)
                                _DebugList(data: data),
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

class _YourVaultCard extends StatelessWidget {
  final String name;
  final String subtitle;

  const _YourVaultCard({
    super.key,
    required this.name,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.black.withOpacity(0.08),
                child: const Icon(Icons.person, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
    );
  }
}

class _PersonSlot extends StatelessWidget {
  final String label;
  final Map<String, dynamic>? filled;
  final VoidCallback onInvite;
  final void Function(Map<String, dynamic> v) onOpen;
  final String? showAddLabel;

  const _PersonSlot({
    super.key,
    required this.label,
    required this.filled,
    required this.onInvite,
    required this.onOpen,
    this.showAddLabel,
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
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black.withOpacity(0.08),
              child: Icon(has ? Icons.person : Icons.add, color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                has ? ((filled!['name'] as String?) ?? label) : (showAddLabel ?? 'Add $label'),
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
  final VoidCallback onInvite;
  final void Function(Map<String, dynamic> v) onOpen;

  const _SmallInviteSlot({
    super.key,
    required this.text,
    required this.filled,
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
            Icon(has ? Icons.person : Icons.add, color: Colors.black.withOpacity(0.65)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                has ? ((filled!['name'] as String?) ?? 'Child') : text,
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black.withOpacity(0.75)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugList extends StatelessWidget {
  final _FamilyData data;
  const _DebugList({required this.data});

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final vaults = data.vaults;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white.withOpacity(0.30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Vaults in this family (debug list)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (vaults.isEmpty)
            const Text('No vaults found for this family yet.')
          else
            ...vaults.map((v) {
              final name = (v['name'] as String?) ?? 'Unnamed';
              final isYou = uid != null && v['owner_id'] == uid;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 18, color: Colors.black.withOpacity(0.6)),
                    const SizedBox(width: 10),
                    Text(isYou ? '$name (you)' : name),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/* =======================
   Lines Painter (real positions)
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

      // rectangle intersection scaling
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

    // IDs
    const you = 'you';

    // Grandparents to parents
    if (showGrandparents) {
      line('maternal_gm', 'mother');
      line('maternal_gf', 'mother');
      line('paternal_gm', 'father');
      line('paternal_gf', 'father');
    }

    // Parents to you
    line('mother', you);
    line('father', you);

    // Spouse to you
    line('spouse_1', you);

    // Siblings to you
    line('sibling_1', you);
    line('sibling_2', you);
    line('sibling_3', you);

    // You to children
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
      ..cubicTo(size.width * 0.22, y1 - 10, size.width * 0.38, y1 + 14, size.width * 0.52, y1)
      ..cubicTo(size.width * 0.70, y1 - 16, size.width * 0.84, y1 + 10, size.width, y1);

    final path2 = Path()
      ..moveTo(0, y2)
      ..cubicTo(size.width * 0.18, y2 + 8, size.width * 0.42, y2 - 12, size.width * 0.60, y2)
      ..cubicTo(size.width * 0.78, y2 + 14, size.width * 0.92, y2 - 6, size.width, y2);

    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FamilyData {
  final List<Map<String, dynamic>> vaults;
  final List<Map<String, dynamic>> members;

  const _FamilyData({required this.vaults, required this.members});
}
