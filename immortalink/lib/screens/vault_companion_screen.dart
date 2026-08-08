// lib/screens/vault_companion_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_chat_reminder_service.dart';

class VaultCompanionScreen extends StatefulWidget {
  final String? vaultId;
  final String displayName;
  final String? avatarUrl;

  // ✅ legacy support
  final String? legacyMemberId;
  final String? familyId;

  const VaultCompanionScreen({
    super.key,
    this.vaultId,
    required this.displayName,
    this.avatarUrl,
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
  bool _loadingIcebreakers = false;
  String? _icebreakerError;

  final List<_ChatMsg> _msgs = [];
  final List<String> _icebreakers = [];

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

  Future<void> _showDisclaimer({bool force = false}) async {
    final userId = _client.auth.currentUser?.id ?? '';
    var shouldShow = true;
    if (!force) {
      try {
        shouldShow = await AiChatReminderService.shouldShow(userId);
      } catch (_) {
        shouldShow = true;
      }
    }
    if (!force && !shouldShow) {
      if (!mounted) return;
      setState(() => _accepted = true);
      unawaited(_loadIcebreakers());
      _focus.requestFocus();
      return;
    }

    bool localAccept = false;
    bool neverShowAgain = false;

    final source = widget.isLegacy
        ? '${widget.displayName}\'s saved family memories, notes and legacy profile'
        : '${widget.displayName}\'s saved memories and voice notes';

    if (!mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('A quick note before you chat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This AI companion is created from $source. It can help you explore their stories, but it may misunderstand details or say something inaccurate.\n\n'
                'It is not ${widget.displayName} and should not replace their own words. Please treat this conversation and their memories with care.',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: localAccept,
                onChanged: (v) => setInner(() => localAccept = v ?? false),
                title: const Text(
                  'I understand this is AI and its answers may be inaccurate.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: neverShowAgain,
                onChanged: (v) => setInner(() => neverShowAgain = v ?? false),
                title: const Text('Don\'t show this reminder again'),
                subtitle: const Text(
                  'Otherwise, we will gently remind you again after 10 sign-ins.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            if (force)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Close'),
              ),
            FilledButton(
              onPressed: localAccept ? () => Navigator.pop(ctx, true) : null,
              child: const Text('I understand — start chatting'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || agreed != true) return;

    try {
      await AiChatReminderService.accept(
        userId,
        neverShowAgain: neverShowAgain,
      );
    } catch (_) {
      // The chat can continue even if this device cannot save the preference.
    }
    if (!mounted) return;
    setState(() => _accepted = true);
    unawaited(_loadIcebreakers());
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
    final token = session?.accessToken.trim();
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'Bearer $token', 'authorization': 'Bearer $token'};
  }

  String _safeExtract(dynamic v) => (v ?? '').toString().trim();

  Future<void> _loadIcebreakers() async {
    if (!_accepted || _loadingIcebreakers) return;

    final session = _client.auth.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() => _icebreakerError = 'Sign in again to load icebreakers.');
      return;
    }

    setState(() {
      _loadingIcebreakers = true;
      _icebreakerError = null;
    });

    try {
      final headers = _authHeadersOrEmpty();
      final body = widget.isLegacy
          ? {
              'mode': 'icebreakers',
              'intent': 'icebreakers',
              'legacyMemberId': widget.legacyMemberId,
              'legacy_member_id': widget.legacyMemberId,
              'familyId': widget.familyId,
              'family_id': widget.familyId,
              'displayName': widget.displayName,
              'display_name': widget.displayName,
            }
          : {
              'mode': 'icebreakers',
              'intent': 'icebreakers',
              'vaultId': widget.vaultId,
              'vault_id': widget.vaultId,
              'familyId': widget.familyId,
              'family_id': widget.familyId,
              'displayName': widget.displayName,
              'display_name': widget.displayName,
            };

      final res = await _client.functions
          .invoke('vault_ai_chat', headers: headers, body: body)
          .timeout(const Duration(seconds: 45));

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
      final loaded = <String>[];
      if (data is Map && data['icebreakers'] is List) {
        for (final item in data['icebreakers'] as List) {
          final text = _safeExtract(item);
          if (text.isNotEmpty) loaded.add(text);
        }
      }

      if (!mounted) return;
      setState(() {
        _icebreakers
          ..clear()
          ..addAll(loaded.take(4));
        _icebreakerError = loaded.isEmpty
            ? 'Could not load personalised icebreakers yet.'
            : null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _icebreakerError = 'Icebreakers took too long to load.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _icebreakerError = 'Could not load personalised icebreakers yet.';
      });
    } finally {
      if (mounted) setState(() => _loadingIcebreakers = false);
    }
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 4,
        title: Row(
          children: [
            _companionAvatar(radius: 19),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'AI memory companion',
                    style: TextStyle(fontSize: 12, color: Color(0xFF786F7C)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About this AI companion',
            onPressed: () => _showDisclaimer(force: true),
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFBFF), Color(0xFFF4EAF7)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
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

  Widget _companionAvatar({double radius = 20}) {
    final trimmed = widget.displayName.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    final avatar = (widget.avatarUrl ?? '').trim();
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFE9D6F2),
            backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
            child: avatar.isEmpty
                ? Text(
                    initial,
                    style: TextStyle(
                      color: const Color(0xFF69417F),
                      fontSize: radius * 0.85,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.72,
              height: radius * 0.72,
              decoration: BoxDecoration(
                color: const Color(0xFF77558D),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: radius * 0.42,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyConversationIntro() {
    return Column(
      children: [
        Center(child: _companionAvatar(radius: 42)),
        const SizedBox(height: 15),
        Text(
          'Chat with ${widget.displayName}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 26),
        const Text(
          'Icebreakers',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF756C79),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildChatList(BuildContext context) {
    if (_msgs.isEmpty) {
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(18, 30, 18, 20),
        children: [
          _emptyConversationIntro(),
          const SizedBox(height: 10),
          _QuickPrompts(
            prompts: _icebreakers,
            isLoading: _loadingIcebreakers,
            errorText: _icebreakerError,
            onRefresh: (_accepted && !_sending && !_loadingIcebreakers)
                ? _loadIcebreakers
                : null,
            onTap: _sending ? null : _sendQuick,
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
      itemCount: _msgs.length,
      itemBuilder: (_, i) {
        final m = _msgs[i];
        final isUser = m.role == _Role.user;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                _companionAvatar(radius: 15),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  constraints: const BoxConstraints(maxWidth: 560),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF77558D) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 5),
                      bottomRight: Radius.circular(isUser ? 5 : 20),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 12,
                        color: Color(0x11000000),
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: m.isTyping
                      ? _TypingDots(name: widget.displayName)
                      : SelectableText(
                          m.text,
                          style: TextStyle(
                            height: 1.35,
                            color: isUser ? Colors.white : Colors.black87,
                          ),
                        ),
                ),
              ),
            ],
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
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 4, 5, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  color: Color(0x18000000),
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _focus,
                    controller: _controller,
                    enabled: _accepted && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _accepted
                          ? 'Message ${widget.displayName}…'
                          : 'Preparing your conversation…',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(
                  height: 46,
                  width: 46,
                  child: IconButton.filled(
                    onPressed: (_accepted && !_sending) ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
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
  final String name;

  const _TypingDots({required this.name});

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
      '${widget.name} is thinking$dots',
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.60),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final List<String> prompts;
  final bool isLoading;
  final String? errorText;
  final Future<void> Function()? onRefresh;
  final void Function(String text)? onTap;

  const _QuickPrompts({
    required this.prompts,
    required this.isLoading,
    required this.errorText,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackItems = <String>[
      'Where did you grow up?',
      'What should I know about you?',
      'What were you like as a child?',
      'What mattered most to you?',
      'How are we related?',
      'What memory always makes you smile?',
    ];
    final items = prompts.isEmpty ? fallbackItems : prompts;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                prompts.isEmpty ? 'Try asking' : 'Personalised starters',
                style: const TextStyle(
                  color: Color(0xFF756C79),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: 'Refresh icebreakers',
                  onPressed: onRefresh,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          if (errorText != null && prompts.isEmpty) ...[
            const SizedBox(height: 2),
            Text(
              errorText!,
              style: const TextStyle(color: Color(0xFF8A7D8F), fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Align(
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
        ],
      ),
    );
  }
}
