import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VaultCompanionScreen extends StatefulWidget {
  final String vaultId;
  final String displayName;

  const VaultCompanionScreen({
    super.key,
    required this.vaultId,
    required this.displayName,
  });

  @override
  State<VaultCompanionScreen> createState() => _VaultCompanionScreenState();
}

class _VaultCompanionScreenState extends State<VaultCompanionScreen> {
  final _client = Supabase.instance.client;

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  bool _accepted = false;
  bool _sending = false;

  final List<_ChatMsg> _msgs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDisclaimer());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _showDisclaimer() async {
    bool localAccept = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Before you chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This chat is an AI voice inspired by ${widget.displayName}\'s vault content.\n\n'
                'It may be inaccurate or incomplete, and it is not the real person.\n\n'
                'Only people with vault access can use it.\n\n'
                'By continuing, you agree to use it respectfully.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: localAccept,
                onChanged: (v) => setInner(() => localAccept = v ?? false),
                title: const Text('I understand and want to continue'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: localAccept ? () => Navigator.pop(ctx) : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    setState(() => _accepted = true);

    _msgs.add(_ChatMsg(
      role: _Role.assistant,
      text: 'Ask me anything. I’ll answer as thoughtfully as I can, based on what’s in this vault.',
    ));
    setState(() {});
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 60));
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 300,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    if (!_accepted) return;

    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // ✅ Must have a session so Supabase can attach Authorization
    final session = _client.auth.currentSession;
    if (session == null) {
      setState(() {
        _msgs.add(_ChatMsg(
          role: _Role.assistant,
          text: 'You are not signed in (session missing). Please sign in again.',
        ));
      });
      return;
    }

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: _Role.user, text: text));
      _controller.clear();
    });

    await _scrollToBottom();

    try {
      // ✅ This includes Authorization automatically
      final res = await _client.functions.invoke(
        'vault_ai_chat',
        body: {
          'vault_id': widget.vaultId,
          'message': text,
          'display_name': widget.displayName,
        },
      );

      final data = res.data;

      String answer = '';
      if (data is Map) {
        answer = (data['answer'] ?? '').toString().trim();
        if (answer.isEmpty && data['error'] != null) {
          answer = 'Error: ${data['error']}';
        }
      } else if (data is String) {
        answer = data.trim();
      }

      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: _Role.assistant,
          text: answer.isEmpty ? '(No answer returned)' : answer,
        ));
      });
    } on FunctionException catch (e) {
      // ✅ Edge Function error (401/403/500 etc)
      final msg = (e.details ?? e.toString()).toString();
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: _Role.assistant,
          text: 'Function error: $msg',
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: _Role.assistant,
          text: 'Sorry — something went wrong generating a reply. ($e)',
        ));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      await _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Ask ${widget.displayName}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                final isUser = m.role == _Role.user;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 560),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                          : Theme.of(context).colorScheme.surface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Text(m.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: _accepted && !_sending,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask a question…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_accepted && !_sending) ? _send : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Role { user, assistant }

class _ChatMsg {
  final _Role role;
  final String text;

  _ChatMsg({required this.role, required this.text});
}
