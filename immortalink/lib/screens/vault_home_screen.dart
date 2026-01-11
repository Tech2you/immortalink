import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'create_memory_screen.dart';

class VaultHomeScreen extends StatefulWidget {
  final String vaultId;
  final String vaultName;

  const VaultHomeScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
  });

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  final supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _memoriesFuture;

  @override
  void initState() {
    super.initState();
    _memoriesFuture = _fetchMemories();
  }

  Future<List<Map<String, dynamic>>> _fetchMemories() async {
    final data = await supabase
        .from('memories')
        .select('id, life_stage, prompt_text, body, created_at')
        .eq('vault_id', widget.vaultId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void _refresh() => setState(() => _memoriesFuture = _fetchMemories());

  Future<void> _addMemory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(vaultId: widget.vaultId),
      ),
    );
    if (created == true) _refresh();
  }

  String _stageLabel(String s) {
    switch (s) {
      case 'early':
        return 'Early life';
      case 'mid':
        return 'Mid life';
      case 'late':
        return 'Late life';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.vaultName)),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _memoriesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: _addMemory,
                icon: const Icon(Icons.add),
                label: const Text('Add your first memory'),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final stage = (r['life_stage'] ?? '').toString();
              final prompt = (r['prompt_text'] ?? '').toString();
              final body = (r['body'] ?? '').toString();

              final preview = body.length > 160
                  ? '${body.substring(0, 160)}…'
                  : body;

              return Card(
                child: ListTile(
                  title: Text(_stageLabel(stage)),
                  subtitle: Text('$prompt\n\n$preview'),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
