import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prompts.dart';
import '../services/indexing_service.dart';

class CreateMemoryScreen extends StatefulWidget {
  final String vaultId;
  final String? initialLifeStage;

  const CreateMemoryScreen({
    super.key,
    required this.vaultId,
    this.initialLifeStage,
  });

  @override
  State<CreateMemoryScreen> createState() => _CreateMemoryScreenState();
}

class _CreateMemoryScreenState extends State<CreateMemoryScreen> {
  final _client = Supabase.instance.client;

  late String _stage;
  String? _selectedPromptId;
  bool _saving = false;

  final _promptController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final init = (widget.initialLifeStage ?? 'early').trim();
    _stage = init.isEmpty ? 'early' : init;
    _syncPromptSelectionToStage();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<MemoryPrompt> get _stagePrompts =>
      memoryPrompts.where((p) => p.lifeStage == _stage).toList();

  void _syncPromptSelectionToStage() {
    final stageIds = _stagePrompts.map((e) => e.id).toSet();
    if (_selectedPromptId != null && !stageIds.contains(_selectedPromptId)) {
      _selectedPromptId = null;
    }
    if (_selectedPromptId == null && _stagePrompts.isNotEmpty) {
      _selectedPromptId = _stagePrompts.first.id;
      _promptController.text = _stagePrompts.first.text;
    }
  }

  String _promptKey(String promptText) {
    // If chosen from prompt list, use that stable ID
    final chosen = _selectedPromptId?.trim();
    if (chosen != null && chosen.isNotEmpty) return chosen;

    // Otherwise generate a stable-ish key for custom prompt text
    // (Don’t use millis; keeps key stable if user edits body only)
    final t = promptText.trim().toLowerCase();
    final hash = t.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return 'custom_$hash';
  }

  Future<void> _save() async {
    if (_saving) return;

    final promptText = _promptController.text.trim();
    final body = _bodyController.text.trim();

    if (promptText.isEmpty) {
      _toast('Prompt cannot be empty.');
      return;
    }
    if (body.isEmpty) {
      _toast('Answer cannot be empty.');
      return;
    }

    final promptKey = _promptKey(promptText);

    setState(() => _saving = true);

    try {
      final inserted = await _client
          .from('memories')
          .insert({
            'vault_id': widget.vaultId,
            'life_stage': _stage,
            'prompt_key': promptKey, // ✅ FIX
            'prompt_text': promptText,
            'body': body,
          })
          .select('id')
          .single();

      final memoryId = (inserted['id'] ?? '').toString();
      if (memoryId.isEmpty) throw Exception('Insert succeeded but no id returned');

      // ✅ indexing should NOT block saving
      IndexingService.indexMemory(vaultId: widget.vaultId, memoryId: memoryId)
          .catchError((e) {
        debugPrint('Indexing failed: $e');
        _toast('Saved, but indexing failed (AI may miss it).');
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _stagePrompts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add memory'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Saving…' : 'Save',
              style: TextStyle(
                color: _saving
                    ? Colors.black38
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              value: _stage,
              decoration: const InputDecoration(
                labelText: 'Life stage',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'early', child: Text('Early life')),
                DropdownMenuItem(value: 'mid', child: Text('Mid life')),
                DropdownMenuItem(value: 'late', child: Text('Late life')),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _stage = v;
                        _syncPromptSelectionToStage();
                      });
                    },
            ),
            const SizedBox(height: 14),
            const Text('Choose a prompt',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: prompts.map((p) {
                final selected = _selectedPromptId == p.id;
                return ChoiceChip(
                  selected: selected,
                  label: Text(p.text),
                  onSelected: _saving
                      ? null
                      : (_) {
                          setState(() {
                            _selectedPromptId = p.id;
                            _promptController.text = p.text;
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _promptController,
              maxLines: 3,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Prompt (question)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_selectedPromptId != null) {
                  setState(() => _selectedPromptId = null);
                }
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bodyController,
              maxLines: 10,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
