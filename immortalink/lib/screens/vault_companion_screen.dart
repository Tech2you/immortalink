// lib/screens/vault_companion_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VaultCompanionScreen extends StatefulWidget {
  final String? vaultId;
  final String displayName;

  // ✅ legacy support
  final String? legacyMemberId;
  final String? familyId;

  const VaultCompanionScreen({
    super.key,
    this.vaultId,
    required this.displayName,
    this.legacyMemberId,
    this.familyId,
  });

  bool get isLegacy =>
      (legacyMemberId ?? '').trim().isNotEmpty &&
      (familyId ?? '').trim().isNotEmpty;

  @override
  State<VaultCompanionScreen> createState() => _VaultCompanionScreenState();
}

class _VaultCompanionScreenState extends State<VaultCompanionScreen> {
  final _client = Supabase.instance.client;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

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
    _focus.dispose();
    super.dispose();
  }

  Future<void> _showDisclaimer() async {
    bool localAccept = false;

    final intro = widget.isLegacy
        ? 'This chat is an AI voice inspired by ${widget.displayName}\'s saved family memories, notes, and legacy profile.\n\n'
              'It may be inaccurate or incomplete, and it is not the real person.\n\n'
              'Only family members with access can use it.\n\n'
              'By continuing, you agree to use it respectfully.'
        : 'This chat is an AI voice inspired by ${widget.displayName}\'s vault content.\n\n'
              'It may be inaccurate or incomplete, and it is not the real person.\n\n'
              'Only people with vault access can use it.\n\n'
              'By continuing, you agree to use it respectfully.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Before you chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(intro),
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
    _focus.requestFocus();
    await _scrollToBottom();
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 400,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Map<String, String> _authHeadersOrEmpty() {
    final session = _client.auth.currentSession;
    final token = session?.accessToken?.trim();
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'Bearer $token', 'authorization': 'Bearer $token'};
  }

  String _safeExtract(dynamic v) => (v ?? '').toString().trim();

  void _sendQuick(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _send();
  }

  Future<void> _send() async {
    if (!_accepted) return;

    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final session = _client.auth.currentSession;
    if (session == null) {
      setState(() {
        _msgs.add(
          _ChatMsg(
            role: _Role.assistant,
            text:
                'You are not signed in (session missing). Please sign in again.',
          ),
        );
      });
      return;
    }

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: _Role.user, text: text));
      _msgs.add(_ChatMsg(role: _Role.assistant, text: '', isTyping: true));
      _controller.clear();
    });

    _focus.requestFocus();
    await _scrollToBottom();

    try {
      final headers = _authHeadersOrEmpty();

      final body = widget.isLegacy
          ? {
              'legacyMemberId': widget.legacyMemberId,
              'legacy_member_id': widget.legacyMemberId,
              'familyId': widget.familyId,
              'family_id': widget.familyId,
              'question': text,
              'prompt': text,
              'message': text,
              'displayName': widget.displayName,
              'display_name': widget.displayName,
            }
          : {
              'vaultId': widget.vaultId,
              'vault_id': widget.vaultId,
              'familyId': widget.familyId,
              'family_id': widget.familyId,
              'question': text,
              'prompt': text,
              'message': text,
              'displayName': widget.displayName,
              'display_name': widget.displayName,
            };

      final res = await _client.functions
          .invoke('vault_ai_chat', headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (res.status != 200) {
        final d = res.data;
        final err = (d is Map)
            ? _safeExtract(d['error'] ?? d['message'] ?? d['details'])
            : _safeExtract(d);
        throw Exception(
          'Function HTTP ${res.status}${err.isEmpty ? '' : ': $err'}',
        );
      }

      final data = res.data;

      String answer = '';
      String debug = '';

      if (data is Map) {
        answer = _safeExtract(data['answer'] ?? data['reply']);
        debug = _safeExtract(data['debug']);
        if (answer.isEmpty) {
          final err = _safeExtract(
            data['error'] ?? data['message'] ?? data['details'],
          );
          if (err.isNotEmpty) answer = 'Error: $err';
        }
      } else if (data is String) {
        answer = data.trim();
      }

      if (answer.isEmpty) {
        answer = debug.isNotEmpty
            ? 'No answer returned. Debug: $debug'
            : '(No answer returned)';
      }

      if (!mounted) return;
      setState(() {
        final idx = _msgs.lastIndexWhere(
          (m) => m.role == _Role.assistant && m.isTyping,
        );
        if (idx != -1) {
          _msgs[idx] = _ChatMsg(role: _Role.assistant, text: answer);
        } else {
          _msgs.add(_ChatMsg(role: _Role.assistant, text: answer));
        }
      });
    } on FunctionException catch (e) {
      final msg = (e.details ?? e.toString()).toString();
      if (!mounted) return;
      setState(() {
        final idx = _msgs.lastIndexWhere(
          (m) => m.role == _Role.assistant && m.isTyping,
        );
        final text = 'Function error: $msg';
        if (idx != -1) {
          _msgs[idx] = _ChatMsg(role: _Role.assistant, text: text);
        } else {
          _msgs.add(_ChatMsg(role: _Role.assistant, text: text));
        }
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        final idx = _msgs.lastIndexWhere(
          (m) => m.role == _Role.assistant && m.isTyping,
        );
        final text =
            'Sorry — the AI took too long to respond. Please try again.';
        if (idx != -1) {
          _msgs[idx] = _ChatMsg(role: _Role.assistant, text: text);
        } else {
          _msgs.add(_ChatMsg(role: _Role.assistant, text: text));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _msgs.lastIndexWhere(
          (m) => m.role == _Role.assistant && m.isTyping,
        );
        final text = 'Sorry — something went wrong generating a reply. ($e)';
        if (idx != -1) {
          _msgs[idx] = _ChatMsg(role: _Role.assistant, text: text);
        } else {
          _msgs.add(_ChatMsg(role: _Role.assistant, text: text));
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _focus.requestFocus();
      await _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isLegacy
        ? 'Legacy Companion • ${widget.displayName}'
        : 'Vault Companion • ${widget.displayName}';

    final bgTop = Theme.of(context).colorScheme.surface;
    final bgBottom = Theme.of(context).colorScheme.surface.withOpacity(0.55);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildHeaderHint(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: _buildChatList(context),
                ),
              ),
            ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderHint(BuildContext context) {
    final hint = widget.isLegacy
        ? 'Ask me anything. I’ll answer as thoughtfully as I can, based on the saved legacy memories, notes, and family context.'
        : 'Ask me anything. I’ll answer as thoughtfully as I can, based on what’s in this vault.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        color: Theme.of(context).colorScheme.surface.withOpacity(0.70),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hint,
              style: TextStyle(color: Colors.black.withOpacity(0.70)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(BuildContext context) {
    if (_msgs.isEmpty) {
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        children: [_QuickPrompts(onTap: _sending ? null : _sendQuick)],
      );
    }

    final showQuickPrompts = _msgs.length <= 1;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: _msgs.length + (showQuickPrompts ? 1 : 0),
      itemBuilder: (_, i) {
        if (showQuickPrompts && i == 1) {
          return _QuickPrompts(onTap: _sending ? null : _sendQuick);
        }

        final msgIndex = showQuickPrompts ? (i == 0 ? 0 : i - 1) : i;
        final m = _msgs[msgIndex];
        final isUser = m.role == _Role.user;

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 620),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                  : Theme.of(context).colorScheme.surface.withOpacity(0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Colors.black.withOpacity(0.04),
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: m.isTyping
                ? const _TypingDots()
                : SelectableText(m.text, style: const TextStyle(height: 1.25)),
          ),
        );
      },
    );
  }

  Widget _buildComposer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _focus,
                    controller: _controller,
                    enabled: _accepted && !_sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _accepted ? 'Ask a question…' : 'Loading…',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.85),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  width: 56,
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
      ),
    );
  }
}

enum _Role { user, assistant }

class _ChatMsg {
  final _Role role;
  final String text;
  final bool isTyping;

  _ChatMsg({required this.role, required this.text, this.isTyping = false});
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  int _dot = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted) return;
      setState(() => _dot = (_dot + 1) % 4);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dot;
    return Text(
      'Typing$dots',
      style: TextStyle(
        color: Colors.black.withOpacity(0.60),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final void Function(String text)? onTap;

  const _QuickPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = <String>[
      'Where did you grow up?',
      'What should I know about you?',
      'What were you like as a child?',
      'What mattered most to you?',
      'How are we related?',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((t) {
            return ActionChip(
              label: Text(t),
              onPressed: onTap == null ? null : () => onTap!(t),
            );
          }).toList(),
        ),
      ),
    );
  }
}
