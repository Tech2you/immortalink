import 'package:flutter/material.dart';
import '../widgets/heiro_surface.dart';

class EditAboutScreen extends StatefulWidget {
  const EditAboutScreen({
    super.key,
    required this.initialText,
    required this.onChanged,
    required this.onSave,
  });

  final String initialText;
  final ValueChanged<String> onChanged;
  final Future<void> Function(String) onSave;

  @override
  State<EditAboutScreen> createState() => _EditAboutScreenState();
}

class _EditAboutScreenState extends State<EditAboutScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(_text.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => HeiroSurface(
    child: PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit about me'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextField(
                    controller: _text,
                    onChanged: widget.onChanged,
                    readOnly: _saving,
                    autofocus: true,
                    minLines: 6,
                    maxLines: null,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      labelText: 'About me',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        "Couldn't save your changes. Your text is still here.",
                        style: TextStyle(color: Color(0xFFAF2929)),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
