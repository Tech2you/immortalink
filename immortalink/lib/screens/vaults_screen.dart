import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_vault_screen.dart';
import 'vault_home_screen.dart';

class VaultsScreen extends StatefulWidget {
  const VaultsScreen({super.key});

  @override
  State<VaultsScreen> createState() => _VaultsScreenState();
}

class _VaultsScreenState extends State<VaultsScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _vaultsFuture;

  @override
  void initState() {
    super.initState();
    _vaultsFuture = _fetchVaults();
  }

  Future<List<Map<String, dynamic>>> _fetchVaults() async {
    final data = await supabase
        .from('vaults')
        .select('id, name, created_at')
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void _refresh() {
    setState(() => _vaultsFuture = _fetchVaults());
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
    } catch (_) {}
  }

  Future<void> _goCreateVault() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateVaultScreen()),
    );
    if (created == true) _refresh();
  }

  void _openVault(Map<String, dynamic> v) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          vaultId: v['id'] as String,
          vaultName: v['name'] as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vaults'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goCreateVault,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _vaultsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final vaults = snap.data ?? [];

          if (vaults.isEmpty) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: _goCreateVault,
                icon: const Icon(Icons.add),
                label: const Text('Create your first vault'),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vaults.length,
            itemBuilder: (context, i) {
              final v = vaults[i];
              return Card(
                child: ListTile(
                  title: Text((v['name'] ?? '').toString()),
                  subtitle: Text('Created: ${v['created_at'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openVault(v),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
