import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'family_tree_screen.dart';



class VaultsScreen extends StatefulWidget {
  const VaultsScreen({super.key});

  @override
  State<VaultsScreen> createState() => _VaultsScreenState();
}

class _VaultsScreenState extends State<VaultsScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _vault; // single vault (1 user = 1 vault)

  @override
  void initState() {
    super.initState();
    _loadVault();
  }

  Future<void> _loadVault() async {
    setState(() => _loading = true);

    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _vault = null;
      });
      return;
    }

    final data = await _supabase
        .from('vaults')
        .select('id, name, created_at, family_id')
        .eq('owner_id', user.id)
        .order('created_at', ascending: false)
        .maybeSingle();

    setState(() {
      _vault = data;
      _loading = false;
    });
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
          decoration: const InputDecoration(
            labelText: 'Vault name',
          ),
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

    await _supabase.from('vaults').update({'name': newName}).eq('id', vaultId);
    await _loadVault();
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

    await _supabase.from('vaults').delete().eq('id', vaultId);
    await _loadVault();
  }

  Future<void> _createVault() async {
    final controller = TextEditingController(text: 'My Vault');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create your vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Vault name',
          ),
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

    // IMPORTANT: this assumes your DB already enforces 1 vault/user
    // If it doesn't, it still works but you'll have multiple rows.
    await _supabase.from('vaults').insert({'name': name});
    await _loadVault();
  }

  Future<void> _ensureFamilyAndOpenTree() async {
    // If already in a family, just open tree
    final familyId = _vault?['family_id'] as String?;
    if (familyId != null && familyId.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FamilyTreeScreen(familyId: familyId),
        ),
      );
      return;
    }

    // Otherwise: create a family group + add yourself + attach your vault
    final controller = TextEditingController(text: 'My Family');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite your family'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create your family group first. Later we’ll add WhatsApp invites + paywall.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Family name',
              ),
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
    if (_vault == null) return;

    final familyName = controller.text.trim().isEmpty ? 'My Family' : controller.text.trim();
    final vaultId = _vault!['id'] as String;

    // 1) create family group
    final family = await _supabase
        .from('family_groups')
        .insert({'name': familyName})
        .select('id')
        .single();

    final newFamilyId = family['id'] as String;

    // 2) add yourself as owner
    final userId = _supabase.auth.currentUser!.id;
    await _supabase.from('family_members').insert({
      'family_id': newFamilyId,
      'user_id': userId,
      'role': 'owner',
    });

    // 3) attach vault to family
    await _supabase.from('vaults').update({'family_id': newFamilyId}).eq('id', vaultId);

    await _loadVault();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyTreeScreen(familyId: newFamilyId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyId = _vault?['family_id'] as String?;
    final inFamily = familyId != null && familyId.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F0F7),
      appBar: AppBar(
        title: Text(_vault == null ? 'Your Vault' : 'Your Vault'),
        backgroundColor: const Color(0xFFF7F0F7),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadVault,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background watermark (same vibe as memories screen)
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
                    : Column(
                        children: [
                          // Invite / View family button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _ensureFamilyAndOpenTree,
                              icon: Icon(inFamily ? Icons.account_tree : Icons.group_add),
                              label: Text(inFamily ? 'View your family tree' : 'Invite your family'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Vault card
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              title: Text(_vault!['name'] ?? ''),
                              subtitle: Text('Created: ${_vault!['created_at']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Rename',
                                    onPressed: () => _renameVault(_vault!['id'], _vault!['name']),
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteVault(_vault!['id']),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'Open',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => VaultHomeScreen(
                                            vaultId: _vault!['id'],
                                            vaultName: _vault!['name'],
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )),
          ),
        ],
      ),
    );
  }
}
