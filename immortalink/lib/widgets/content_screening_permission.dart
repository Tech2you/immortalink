import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/content_screening_config.dart';
import 'legal_links.dart';

export '../services/content_screening_config.dart';

final _pending = <SupabaseClient, Map<String, Future<bool>>>{};

Future<bool> requestContentScreeningPermission(
  BuildContext context, {
  SupabaseClient? client,
  String? expectedUserId,
  bool settings = false,
  bool enabled = contentScreeningControlsEnabled,
}) async {
  if (!enabled || !context.mounted) return false;
  final backend = client ?? Supabase.instance.client;
  final userId = backend.auth.currentUser?.id;
  if (userId == null || (expectedUserId != null && expectedUserId != userId)) {
    return false;
  }
  final requests = _pending.putIfAbsent(backend, () => {});
  final existing = requests[userId];
  if (existing != null) return existing;
  final request = showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _PermissionDialog(backend: backend, userId: userId, settings: settings),
  ).then((value) => value == true && backend.auth.currentUser?.id == userId);
  requests[userId] = request;
  try {
    return await request;
  } finally {
    requests.remove(userId);
    if (requests.isEmpty) _pending.remove(backend);
  }
}

class _Permission {
  const _Permission(this.allowed, this.policy, this.revision);
  final bool allowed;
  final String policy;
  final BigInt revision;

  static _Permission parse(dynamic data) {
    if (data is! Map ||
        data['allowed'] is! bool ||
        data['policy_version'] is! String ||
        (data['policy_version'] as String).isEmpty ||
        data['revision'] is! String ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(data['revision'] as String)) {
      throw const FormatException('Invalid permission response');
    }
    final revision = BigInt.parse(data['revision'] as String);
    if (revision > BigInt.parse('9223372036854775807') ||
        (data['allowed'] == true && revision == BigInt.zero)) {
      throw const FormatException('Invalid permission revision');
    }
    return _Permission(
      data['allowed'] as bool,
      data['policy_version'] as String,
      revision,
    );
  }
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog({
    required this.backend,
    required this.userId,
    required this.settings,
  });
  final SupabaseClient backend;
  final String userId;
  final bool settings;

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  _Permission? _permission;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  bool get _sameAccount => widget.backend.auth.currentUser?.id == widget.userId;
  bool get _currentPolicy =>
      _permission?.policy == contentScreeningPolicyVersion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _checkAccount() {
    if (!mounted) return false;
    if (_sameAccount) return true;
    setState(() {
      _loading = false;
      _saving = false;
      _permission = null;
      _error = 'Your account changed. Close this screen and reopen it.';
    });
    return false;
  }

  Future<void> _load() async {
    if (!_checkAccount()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.backend
          .rpc('get_content_screening_permission')
          .timeout(const Duration(seconds: 12));
      if (!mounted || !_checkAccount()) return;
      final permission = _Permission.parse(data);
      if (permission.allowed &&
          permission.policy == contentScreeningPolicyVersion &&
          !widget.settings) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _permission = permission);
    } catch (_) {
      if (!_checkAccount()) return;
      setState(() {
        _permission = null;
        _error = 'Could not load permission. Try again, or turn off checks.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(bool allowed) async {
    if (_saving || _loading || !_checkAccount()) return;
    if (allowed && !_currentPolicy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.backend
          .rpc(
            'set_content_screening_permission',
            params: {
              'p_allowed': allowed,
              'p_policy_version': contentScreeningPolicyVersion,
              'p_expected_user_id': widget.userId,
            },
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted || !_checkAccount()) return;
      final saved = _Permission.parse(data);
      if (saved.allowed != allowed ||
          saved.revision <= (_permission?.revision ?? BigInt.zero) ||
          (allowed && saved.policy != contentScreeningPolicyVersion)) {
        throw const FormatException('Permission change not confirmed');
      }
      Navigator.pop(context, allowed);
    } catch (_) {
      if (!_checkAccount()) return;
      setState(() {
        _error = allowed
            ? 'Could not confirm this change. Check your connection and retry.'
            : 'Could not confirm withdrawal. Checks may still be enabled. '
                  'Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _saving;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Sharing safety'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Allow Heiro to send new text and photos you choose to share '
                'with family to OpenAI for safety checks? They may contain '
                'personal information about you or relatives. Flagged additions '
                'may be held for restricted human review.\n\n'
                'Private drafts and existing archives are not scanned. This '
                'permission does not cover voice recordings or videos, or '
                'enable AI chat or transcription.\n\n'
                'You can decline or turn off future checks here. Declining '
                'does not allow unchecked sharing. Withdrawal cannot recall '
                'data already sent.',
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => openLegalLink(context, LegalDestination.privacy),
                child: const Text('Privacy Policy'),
              ),
              if (busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _saving ? 'Saving permission...' : 'Checking permission...',
                ),
              ],
              if (_permission != null && !_currentPolicy)
                const Text(
                  'The disclosure has changed. Update Heiro before enabling '
                  'checks. You can still turn them off.',
                ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_permission == null && !busy && _sameAccount)
                TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: busy || !_sameAccount ? null : () => _save(false),
            child: Text(
              _permission?.allowed == false && _currentPolicy
                  ? 'Decline'
                  : 'Turn off checks',
            ),
          ),
          FilledButton(
            onPressed: busy || !_sameAccount || !_currentPolicy
                ? null
                : () => _save(true),
            child: Text(
              _permission?.allowed == true
                  ? 'Keep enabled'
                  : 'Allow safety checks',
            ),
          ),
        ],
      ),
    );
  }
}
