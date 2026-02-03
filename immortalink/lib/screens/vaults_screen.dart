import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_home_screen.dart';
import 'family_tree_screen.dart';
import 'join_family_screen.dart';

class VaultsScreen extends StatefulWidget {
  const VaultsScreen({super.key});

  @override
  State<VaultsScreen> createState() => _VaultsScreenState();
}

class _VaultsScreenState extends State<VaultsScreen> {void _openJoinFamilyScreen() {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const JoinFamilyScreen()),
  ).then((_) => _loadVault()); // optional refresh
}

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _vault; // single vault (1 user = 1 vault)
  String? _vaultAvatarUrl; // signed url for display (private bucket)

  @override
  void initState() {
    super.initState();
    _loadVault();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _signedAvatarUrl(String path) async {
    try {
      final signed =
          await _supabase.storage.from('avatars').createSignedUrl(path, 60 * 60);

      // ✅ cache-bust safely (handles both with/without existing query string)
      final sep = signed.contains('?') ? '&' : '?';
      return '$signed${sep}t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVault() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _vault = null;
          _vaultAvatarUrl = null;
        });
        return;
      }

      final data = await _supabase
          .from('vaults')
          .select('id, name, created_at, family_id, avatar_path')
          .eq('owner_id', user.id)
          .order('created_at', ascending: false)
          .maybeSingle()
          .timeout(const Duration(seconds: 12)); // ✅ prevents infinite hang

      String? signedUrl;
      final path = (data?['avatar_path'] as String?)?.trim();
      if (path != null && path.isNotEmpty) {
        signedUrl = await _signedAvatarUrl(path)
            .timeout(const Duration(seconds: 12)); // ✅ prevents hang
      }

      if (!mounted) return;
      setState(() {
        _vault = data;
        _vaultAvatarUrl = signedUrl;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error =
            'Timed out loading vault. Check internet / Supabase URL/keys / blocked requests.';
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Postgrest: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false); // ✅ always clears spinner
    }
  }

  void _openVaultHome() {
    if (_vault == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          vaultId: (_vault!['id'] ?? '').toString(),
          vaultName: (_vault!['name'] ?? '').toString(),
        ),
      ),
    ).then((_) => _loadVault()); // refresh after edits
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
          decoration: const InputDecoration(labelText: 'Vault name'),
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

    try {
      await _supabase
          .from('vaults')
          .update({'name': newName})
          .eq('id', vaultId)
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault renamed.');
    } on TimeoutException {
      _toast('Rename timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Rename failed: ${e.message}');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _deleteVault(String vaultId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vault?'),
        content:
            const Text('This will permanently delete the vault and its memories.'),
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

    try {
      await _supabase
          .from('vaults')
          .delete()
          .eq('id', vaultId)
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault deleted.');
    } on TimeoutException {
      _toast('Delete timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
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
          decoration: const InputDecoration(labelText: 'Vault name'),
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

    try {
      await _supabase
          .from('vaults')
          .insert({'name': name})
          .timeout(const Duration(seconds: 12));

      await _loadVault();
      _toast('Vault created.');
    } on TimeoutException {
      _toast('Create timed out. Try again.');
    } on PostgrestException catch (e) {
      _toast('Create failed: ${e.message}');
    } catch (e) {
      _toast('Create failed: $e');
    }
  }

  Future<void> _ensureFamilyAndOpenTree() async {
    final familyId = (_vault?['family_id'] as String?)?.trim();
    if (familyId != null && familyId.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FamilyTreeScreen(familyId: familyId)),
      );
      return;
    }

    final controller = TextEditingController(text: 'My Family');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite your family'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create your family group first. Next we’ll do slot invites.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Family name'),
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

   final familyName =
    controller.text.trim().isEmpty ? 'My Family' : controller.text.trim();
final vaultId = (_vault!['id'] ?? '').toString();

try {
 final newFamilyId = await _supabase
    .rpc('create_family_group_and_link_vault', params: {
      'p_family_name': familyName,
    })
    .timeout(const Duration(seconds: 12));

final newFamilyIdStr = (newFamilyId ?? '').toString();
if (newFamilyIdStr.isEmpty) throw Exception('Failed to create family id');

await _loadVault();

if (!mounted) return;
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => FamilyTreeScreen(familyId: newFamilyIdStr),
  ),
);


} on TimeoutException {
  _toast('Family setup timed out. Try again.');
} on PostgrestException catch (e) {
  _toast('Family setup failed: ${e.message}');
} catch (e) {
  _toast('Family setup failed: $e');
}
  }

  @override
  Widget build(BuildContext context) {
    final familyId = (_vault?['family_id'] as String?)?.trim();
    final inFamily = familyId != null && familyId.isNotEmpty;

    final hasAvatar =
        _vaultAvatarUrl != null && _vaultAvatarUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F0F7),
      appBar: AppBar(
        title: const Text('Your Vault'),
        backgroundColor: const Color(0xFFF7F0F7),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadVault,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Join family',
            onPressed: _openJoinFamilyScreen,
            icon: const Icon(Icons.group_add),
          ),
        ],
      ),
      body: Stack(
        children: [
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
                : (_error != null)
                    ? Center(child: Text('Load failed: $_error'))
                    : (_vault == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('No vault yet',
                                    style: TextStyle(fontSize: 18)),
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
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _ensureFamilyAndOpenTree,
                                  icon: Icon(inFamily
                                      ? Icons.account_tree
                                      : Icons.group_add),
                                  label: Text(inFamily
                                      ? 'View your family tree'
                                      : 'Invite your family'),
                                ),
                              ),
                              if (!inFamily) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _openJoinFamilyScreen,
                                    icon: const Icon(Icons.vpn_key),
                                    label: const Text('Join with invite code'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  onTap: _openVaultHome,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor:
                                        Colors.black.withOpacity(0.08),
                                    backgroundImage: hasAvatar
                                        ? NetworkImage(_vaultAvatarUrl!)
                                        : null,
                                    child: !hasAvatar
                                        ? Icon(Icons.person,
                                            size: 18,
                                            color:
                                                Colors.black.withOpacity(0.6))
                                        : null,
                                  ),
                                  title: Text((_vault!['name'] ?? '').toString()),
                                  subtitle: Text('Created: ${_vault!['created_at']}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rename',
                                        onPressed: () => _renameVault(
                                          (_vault!['id'] ?? '').toString(),
                                          (_vault!['name'] ?? '').toString(),
                                        ),
                                        icon: const Icon(Icons.edit),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteVault(
                                          (_vault!['id'] ?? '').toString(),
                                        ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                      IconButton(
                                        tooltip: 'Open',
                                        onPressed: _openVaultHome,
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
