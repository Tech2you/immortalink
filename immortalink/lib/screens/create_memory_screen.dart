import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prompts.dart';

class CreateMemoryScreen extends StatefulWidget {
  final String vaultId;

  const CreateMemoryScreen({super.key, required this.vaultId});

  @override
  State<CreateMemoryScreen> createState() => _CreateMemoryScreenState();
}

class _CreateMemoryScreenState extends State<CreateMemoryScreen> {
  final supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final _bodyController = TextEditingController();

  String _lifeStage = 'early';
  MemoryPrompt? _prompt;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _prompt = memoryPrompts.firstWhere((p) => p.lifeStage == _lifeStage);
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  List<MemoryPrompt> get _stagePrompts =>
      memoryPrompts.where((p) => p.lifeStage == _lifeStage).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in.')),
      );
      return;
    }

    if (_prompt == null) return;

    setState(() => _loading = true);

    try {
      final p = _prompt!;
      await supabase.from('memories').insert({
        'vault_id': widget.vaultId,
        'owner_id': user.id,
        'life_stage': _lifeStage,
        'prompt_key': p.key,
        'prompt_text': p.text,
        'body': _bodyController.text.trim(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _stagePrompts;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Memory')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _lifeStage,
                decoration: const InputDecoration(
                  labelText: 'Life stage',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'early', child: Text('Early life')),
                  DropdownMenuItem(value: 'mid', child: Text('Mid life')),
                  DropdownMenuItem(value: 'late', child: Text('Late life')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _lifeStage = v;
                    _prompt = memoryPrompts.firstWhere((p) => p.lifeStage == v);
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemoryPrompt>(
                value: _prompt,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  border: OutlineInputBorder(),
                ),
                items: prompts
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.text),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _prompt = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyController,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Your memory',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Write something';
                  if (t.length < 20) return 'Try add a bit more detail (20+ chars)';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
