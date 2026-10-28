import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/content_sharing_service.dart';
import 'content_screening_permission.dart';

Future<void> showMemorySharingStatus(
  BuildContext context, {
  required String kind,
  required String targetId,
  SupabaseClient? client,
  String? expectedUserId,
  bool requestAfterSave = false,
  bool enabled = contentScreeningControlsEnabled,
}) async {
  if (!enabled || !context.mounted) return;
  final backend = client ?? Supabase.instance.client;
  final userId = backend.auth.currentUser?.id;
  if (userId == null || (expectedUserId != null && expectedUserId != userId)) {
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SharingDialog(
      service: ContentSharingService(
        client: backend,
        expectedUserId: userId,
        enabled: enabled,
      ),
      kind: kind,
      targetId: targetId,
      requestAfterSave: requestAfterSave,
    ),
  );
}

class _SharingDialog extends StatefulWidget {
  const _SharingDialog({
    required this.service,
    required this.kind,
    required this.targetId,
    required this.requestAfterSave,
  });
  final ContentSharingService service;
  final String kind;
  final String targetId;
  final bool requestAfterSave;

  @override
  State<_SharingDialog> createState() => _SharingDialogState();
}

class _SharingDialogState extends State<_SharingDialog> {
  ContentSharingStatus? _status;
  bool _busy = true;
  bool _permissionOpen = false;
  String? _error;
  bool _declined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial: true));
  }

  String get _failure => widget.service.sameAccount
      ? 'Could not confirm sharing. The memory is saved. Check again before retrying.'
      : 'Your account changed. Close this screen and reopen it.';

  Future<void> _load({bool initial = false}) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.status(widget.kind, widget.targetId);
      if (!mounted) return;
      setState(() {
        _status = result;
        _declined = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = _failure;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        initial &&
        widget.requestAfterSave &&
        _status?.canRequest == true) {
      await _request();
    }
  }

  Future<void> _request() async {
    if (_busy || _status?.canRequest != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _permissionOpen = true;
    });
    try {
      final allowed = await requestContentScreeningPermission(
        context,
        client: widget.service.client,
        expectedUserId: widget.service.expectedUserId,
        enabled: widget.service.enabled,
      );
      if (!mounted) return;
      setState(() => _permissionOpen = false);
      if (!widget.service.sameAccount) throw StateError('Account changed');
      if (!allowed) {
        setState(() => _declined = true);
        return;
      }
      final result = await widget.service.request(widget.kind, widget.targetId);
      if (!mounted) return;
      setState(() {
        _status = result;
        _declined = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = _failure;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _permissionOpen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Memory sharing'),
      titleTextStyle: Theme.of(context).textTheme.titleLarge,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _error ??
                    (_declined
                        ? 'Saved. No new sharing request was sent.'
                        : _status?.message ?? 'Checking sharing status...'),
              ),
            ),
            if (_busy && !_permissionOpen) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh sharing status',
          onPressed: _busy || !widget.service.sameAccount ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        if (_status?.canRequest == true)
          FilledButton.icon(
            onPressed: _busy || !widget.service.sameAccount ? null : _request,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Request sharing'),
          ),
      ],
    ),
  );
}
