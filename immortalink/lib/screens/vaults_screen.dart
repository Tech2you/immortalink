import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';
import 'create_vault_screen.dart';
import 'vault_home_screen.dart';

class VaultsScreen extends StatefulWidget {
  const VaultsScreen({super.key});

  @override
  State<VaultsScreen> createState() => _VaultsScreenState();
}

class _VaultsScreenState extends State<VaultsScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vaults = [];

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadVaults() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _client
          .from('vaults')
          .select('id, name, created_at')
          .order('created_at', ascending: false);

      setState(() {
        _vaults = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCreateVault() async {
    if (_vaults.isNotEmpty) {
      _toast('One vault per account for now.');
      return;
    }

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateVaultScreen()),
    );

    if (created == true) {
      await _loadVaults();
      if (!mounted) return;

      // auto-open the only vault (nice UX)
      if (_vaults.isNotEmpty) {
        await _openVault(_vaults.first);
      } else {
        _toast('Vault created.');
      }
    }
  }

  Future<void> _openVault(Map<String, dynamic> v) async {
    final vaultId = (v['id'] ?? '').toString();
    final vaultName = (v['name'] ?? 'Vault').toString();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          vaultId: vaultId,
          vaultName: vaultName,
        ),
      ),
    );

    await _loadVaults();
  }

  @override
  Widget build(BuildContext context) {
    final hasVault = _vaults.isNotEmpty;
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVaults,
          ),
        ],
      ),
      floatingActionButton: hasVault
          ? null // ✅ hide + once vault exists
          : FloatingActionButton(
              onPressed: _openCreateVault,
              child: const Icon(Icons.add),
            ),
      body: LogoWatermark(
        opacity: 0.06,
        size: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        'Load failed: $_error',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _vaults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('No vault yet.'),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _openCreateVault,
                                child: const Text('Create your vault'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _vaults.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final v = _vaults[index];
                            final name = (v['name'] ?? 'Vault').toString();
                            final createdAt = (v['created_at'] ?? '').toString();

                            return ListTile(
                              tileColor: tileBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: Text(name),
                              subtitle: Text(
                                createdAt.isEmpty ? '' : 'Created: $createdAt',
                              ),
                              onTap: () => _openVault(v),
                              trailing: const Icon(Icons.chevron_right),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}
