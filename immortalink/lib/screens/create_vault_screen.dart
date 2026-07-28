import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _client = Supabase.instance.client;
  final _nameController = TextEditingController();

  bool _loading = true;
  bool _creating = false;
  String? _error;

  Map<String, dynamic>? _existingVault;

  // ✅ Added: human-friendly "10 May 2026" (no time)
  String _formatCreatedDate(dynamic createdAtRaw) {
    final s = (createdAtRaw ?? '').toString().trim();
    if (s.isEmpty) return '';

    final dt = DateTime.tryParse(s);
    if (dt == null) return '';

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final d = dt.toLocal();
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _checkExistingVault();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ✅ Added: ensure we have a valid session so auth.uid() is NOT null in RLS
  Future<void> _ensureSession() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not signed in.');

    // On Flutter web / InPrivate, currentUser can exist but session can be null.
    if (_client.auth.currentSession == null) {
      final refreshed = await _client.auth.refreshSession();
      if (refreshed.session == null) {
        throw Exception('Session expired. Please sign in again.');
      }
    }
  }

  Future<void> _checkExistingVault() async {
    setState(() {
      _loading = true;
      _error = null;
      _existingVault = null;
    });

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'Not signed in.';
        });
        return;
      }

      // ✅ Added: make sure requests include JWT
      await _ensureSession();

      final data = await _client
          .from('vaults')
          .select('id, name, created_at')
          .eq('owner_id', user.id)
          .order('created_at', ascending: false)
          .limit(1);

      if (data is List && data.isNotEmpty) {
        setState(() {
          _existingVault = Map<String, dynamic>.from(data.first);
          _loading = false;
        });
        return;
      }

      setState(() => _loading = false);
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createVault() async {
    setState(() {
      _creating = true;
      _error = null;
    });

    final name = _nameController.text.trim().isEmpty
        ? 'My Vault'
        : _nameController.text.trim();

    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Not signed in.');

      // ✅ Added: make sure requests include JWT
      await _ensureSession();

      await _client.from('vaults').insert({'name': name});

      if (!mounted) return;
      Navigator.pop(context, true); // created
    } on PostgrestException catch (e) {
      // If unique constraint blocks second vault, show friendly message
      setState(() {
        _error =
            e.message.contains('vaults_owner_unique') ||
                e.message.toLowerCase().contains('duplicate') ||
                e.code == '23505'
            ? 'You already have a vault (one vault per account for now).'
            : e.message;
        _creating = false;
      });
      // refresh existing vault check
      await _checkExistingVault();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _creating = false;
      });
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Vault')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _existingVault != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 18),
                  const Icon(Icons.lock, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'You already have a vault.',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'For now, each account has 1 vault to keep things simple.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      title: Text(
                        (_existingVault!['name'] ?? 'Vault').toString(),
                      ),
                      subtitle: Text(() {
                        final created = _formatCreatedDate(
                          _existingVault!['created_at'],
                        );
                        return created.isEmpty ? '' : 'Created: $created';
                      }()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Back to Vaults'),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Vault name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _creating ? null : _createVault,
                      child: Text(_creating ? 'Creating...' : 'Create Vault'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Note: One vault per account for now (we’ll expand later).',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}
