import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prompts.dart';

class CreateMemoryScreen extends StatefulWidget {
  final String vaultId;
  final String? initialLifeStage; // 'early' | 'mid' | 'late'

  const CreateMemoryScreen({
    super.key,
    required this.vaultId,
    this.initialLifeStage,
  });

  @override
  State<CreateMemoryScreen> createState() => _CreateMemoryScreenState();
}

class _CreateMemoryScreenState extends State<CreateMemoryScreen> {
  final _bodyController = TextEditingController();
  bool _saving = false;

  late String _lifeStage; // 'early' | 'mid' | 'late'
  MemoryPrompt? _prompt;

  @override
  void initState() {
    super.initState();

    const allowed = {'early', 'mid', 'late'};
    final incoming = widget.initialLifeStage;
    _lifeStage = (incoming != null && allowed.contains(incoming)) ? incoming : 'early';
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  List<MemoryPrompt> get _stagePrompts =>
      memoryPrompts.where((p) => p.lifeStage == _lifeStage).toList();

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveMemory() async {
    final body = _bodyController.text.trim();

    if (_prompt == null) {
      _toast('Pick a prompt first.');
      return;
    }
    if (body.isEmpty) {
      _toast('Write something before saving.');
      return;
    }

    setState(() => _saving = true);

    try {
      final client = Supabase.instance.client;

      // ✅ Must include every NOT NULL column in your table
      // ✅ prompt_key must be _prompt!.id (stable key)
      final payload = <String, dynamic>{
        'vault_id': widget.vaultId,
        'life_stage': _lifeStage,
        'prompt_key': _prompt!.id,
        'prompt_text': _prompt!.text,
        'body': body,
      };

      await client.from('memories').insert(payload);

      if (!mounted) return;
      Navigator.pop(context, true); // true = saved OK
    } on PostgrestException catch (e) {
      // This will show RLS issues, NOT NULL issues, etc.
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
        title: const Text('Add Memory'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Life stage selector
              Row(
                children: [
                  const Text('Life stage:'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _lifeStage,
                    items: const [
                      DropdownMenuItem(value: 'early', child: Text('Early')),
                      DropdownMenuItem(value: 'mid', child: Text('Mid')),
                      DropdownMenuItem(value: 'late', child: Text('Late')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _lifeStage = v;
                        _prompt = null; // reset prompt when stage changes
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Prompt selector
              DropdownButtonFormField<String>(
                value: _prompt?.id,
                items: prompts
                    .map((p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            p.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  border: OutlineInputBorder(),
                ),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() {
                    _prompt = prompts.firstWhere((p) => p.id == id);
                  });
                },
              ),

              const SizedBox(height: 12),

              // Body
              Expanded(
                child: TextField(
                  controller: _bodyController,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: 'Your memory',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    hintText: 'Write the memory here…',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveMemory,
                  child: Text(_saving ? 'Saving…' : 'Save Memory'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
