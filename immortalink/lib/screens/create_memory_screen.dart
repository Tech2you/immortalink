import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prompts.dart';

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

  final _bodyController = TextEditingController();
  final _customPromptController = TextEditingController();

  bool _saving = false;
  String? _error;

  String _lifeStage = 'early';
  MemoryPrompt? _prompt;

  bool _useCustomPrompt = false;

  @override
  void initState() {
    super.initState();
    _lifeStage = widget.initialLifeStage ?? 'early';
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  List<MemoryPrompt> get _stagePrompts =>
      memoryPrompts.where((p) => p.lifeStage == _lifeStage).toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() {
        _saving = false;
        _error = 'Please write something for your memory.';
      });
      return;
    }

    // Determine prompt_key + prompt_text based on selection
    String promptKey;
    String promptText;

    if (_useCustomPrompt) {
      promptText = _customPromptController.text.trim();
      if (promptText.isEmpty) {
        setState(() {
          _saving = false;
          _error = 'Please enter your custom prompt/title.';
        });
        return;
      }
      // stable enough for MVP; keeps NOT NULL satisfied
      promptKey = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    } else {
      if (_prompt == null) {
        setState(() {
          _saving = false;
          _error = 'Please choose a prompt.';
        });
        return;
      }
      promptKey = _prompt!.id;      // ✅ correct: id
      promptText = _prompt!.text;   // ✅ correct: text
    }

    try {
      await _client.from('memories').insert({
        'vault_id': widget.vaultId,
        'life_stage': _lifeStage,
        'prompt_key': promptKey,
        'prompt_text': promptText,
        'body': body,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompts = _stagePrompts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Memory'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Life stage selector
            DropdownButtonFormField<String>(
              value: _lifeStage,
              decoration: const InputDecoration(
                labelText: 'Life stage',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'early', child: Text('Early')),
                DropdownMenuItem(value: 'mid', child: Text('Mid')),
                DropdownMenuItem(value: 'late', child: Text('Late')),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _lifeStage = v;
                        _prompt = null;
                        _useCustomPrompt = false;
                        _customPromptController.clear();
                      });
                    },
            ),
            const SizedBox(height: 14),

            // Prompt selector + custom option
            DropdownButtonFormField<String>(
              value: _useCustomPrompt
                  ? '__custom__'
                  : (_prompt?.id), // store id
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              items: [
                ...prompts.map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      p.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const DropdownMenuItem(
                  value: '__custom__',
                  child: Text('✍️ Write your own memory (custom prompt)'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        if (value == '__custom__') {
                          _useCustomPrompt = true;
                          _prompt = null;
                        } else {
                          _useCustomPrompt = false;
                          _prompt = prompts.firstWhere(
                            (p) => p.id == value,
                            orElse: () => prompts.first,
                          );
                        }
                      });
                    },
            ),
            const SizedBox(height: 12),

            if (_useCustomPrompt) ...[
              TextField(
                controller: _customPromptController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Custom prompt / title',
                  hintText: 'e.g. “My biggest lesson at university”',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _bodyController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Your memory',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 10),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save Memory'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
