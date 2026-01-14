import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/logo_watermark.dart';
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
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _memories = [];
  String _vaultName = '';

  @override
  void initState() {
    super.initState();
    _vaultName = widget.vaultName;
    _loadMemories();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _client
          .from('memories')
          .select('id, vault_id, life_stage, prompt_text, body, created_at')
          .eq('vault_id', widget.vaultId)
          .order('created_at', ascending: false);

      setState(() {
        _memories = List<Map<String, dynamic>>.from(data);
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

  Future<void> _openAddMemory({String? initialLifeStage}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMemoryScreen(
          vaultId: widget.vaultId,
          initialLifeStage: initialLifeStage,
        ),
      ),
    );

    if (saved == true) {
      await _loadMemories();
      _toast('Memory saved.');
    }
  }

  Future<void> _renameVault() async {
    final controller = TextEditingController(text: _vaultName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename vault'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Vault name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await _client.from('vaults').update({'name': newName}).eq('id', widget.vaultId);
      setState(() => _vaultName = newName);
      _toast('Vault renamed.');
    } on PostgrestException catch (e) {
      _toast('Rename failed: ${e.message}');
    } catch (e) {
      _toast('Rename failed: $e');
    }
  }

  Future<void> _editMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();

    final promptController =
        TextEditingController(text: (m['prompt_text'] ?? '').toString());
    final bodyController =
        TextEditingController(text: (m['body'] ?? '').toString());

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Prompt (question)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'prompt_text': promptController.text.trim(),
              'body': bodyController.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final newPromptText = (result['prompt_text'] ?? '').trim();
    final newBody = (result['body'] ?? '').trim();

    if (newPromptText.isEmpty) {
      _toast('Prompt cannot be empty.');
      return;
    }
    if (newBody.isEmpty) {
      _toast('Answer cannot be empty.');
      return;
    }

    try {
      await _client.from('memories').update({
        'prompt_text': newPromptText,
        'body': newBody,
      }).eq('id', memoryId);

      await _loadMemories();
      _toast('Memory updated.');
    } on PostgrestException catch (e) {
      _toast('Update failed: ${e.message}');
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> m) async {
    final memoryId = (m['id'] ?? '').toString();
    final prompt = (m['prompt_text'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete memory?'),
        content: Text('Delete this memory permanently?\n\n$prompt'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _client.from('memories').delete().eq('id', memoryId);
      await _loadMemories();
      _toast('Memory deleted.');
    } on PostgrestException catch (e) {
      _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  String _prettyStage(String s) {
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
    final tileBg = Theme.of(context).colorScheme.surface.withOpacity(0.72);

    return Scaffold(
      appBar: AppBar(
        title: Text(_vaultName),
        actions: [
          IconButton(
            tooltip: 'Rename vault',
            icon: const Icon(Icons.edit),
            onPressed: _renameVault,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMemories,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddMemory(initialLifeStage: 'early'),
        child: const Icon(Icons.add),
      ),
      body: LogoWatermark(
        opacity: 0.03,
        size: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Load failed: $_error'))
                  : _memories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('No memories yet.'),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () =>
                                    _openAddMemory(initialLifeStage: 'early'),
                                child: const Text('Add your first memory'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _memories.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, i) {
                            final m = _memories[i];
                            final stage = (m['life_stage'] ?? '').toString();
                            final prompt = (m['prompt_text'] ?? '').toString();
                            final body = (m['body'] ?? '').toString();

                            return ListTile(
                              tileColor: tileBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: Chip(label: Text(_prettyStage(stage))),
                              title:
                                  Text(prompt.isEmpty ? '(No prompt)' : prompt),
                              subtitle: Text(
                                body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _editMemory(m),
                              trailing: IconButton(
                                tooltip: 'Delete memory',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteMemory(m),
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}
