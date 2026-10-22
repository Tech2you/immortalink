import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/content_safety_service.dart';
import '../utils/public_error.dart';

String safetyErrorMessage(Object error) {
  if (error is PostgrestException && error.message == 'SAFETY_REPORT_LIMIT') {
    return 'Too many reports in a short time. Please try again later or contact support.';
  }
  return publicErrorMessage(error);
}

Future<bool> showContentReport(
  BuildContext context, {
  required String kind,
  required String targetId,
  String? familyId,
  ContentSafetyService? service,
}) async {
  final backend = service ?? ContentSafetyService();
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ContentReportDialog(
          submit: (reason, details) => backend.report(
            kind: kind,
            targetId: targetId,
            familyId: familyId,
            reason: reason,
            details: details,
          ),
        ),
      ) ??
      false;
}

class ContentReportDialog extends StatefulWidget {
  const ContentReportDialog({super.key, required this.submit});

  final Future<void> Function(String reason, String details) submit;

  @override
  State<ContentReportDialog> createState() => _ContentReportDialogState();
}

class MemoryReportMenu extends StatelessWidget {
  const MemoryReportMenu({super.key, required this.memoryId, this.service});

  final String memoryId;
  final ContentSafetyService? service;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Memory options',
    icon: const Icon(Icons.more_horiz),
    enabled: memoryId.isNotEmpty,
    onSelected: (_) => showContentReport(
      context,
      kind: 'memory',
      targetId: memoryId,
      service: service,
    ),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'report', child: Text('Report memory or media')),
    ],
  );
}

class _ContentReportDialogState extends State<ContentReportDialog> {
  static const _reasons = {
    'harassment': 'Harassment or abuse',
    'sexual_content': 'Sexual content',
    'violence': 'Violence or threats',
    'privacy': 'Privacy or consent',
    'spam': 'Spam or scam',
    'other': 'Something else',
  };
  final _details = TextEditingController();
  String? _reason;
  String? _error;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(_reason!, _details.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) setState(() => _error = safetyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(_sent ? 'Report received' : 'Report content'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: _sent
              ? const Text(
                  'Your report is in the review queue. Reporting does not delete family memories.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: _reasons.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _reason = value),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _details,
                      enabled: !_busy,
                      maxLength: 1000,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Details (optional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
        ),
      ),
      actions: _sent
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _busy || _reason == null ? null : _submit,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Send report'),
              ),
            ],
    ),
  );
}

Future<bool> confirmMemberBlock(
  BuildContext context, {
  required String memberId,
  required String memberName,
  required bool blocked,
  ContentSafetyService? service,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${blocked ? 'Block' : 'Unblock'} $memberName?'),
      content: Text(
        blocked
            ? 'Your personal vaults will be hidden from each other. Contributions attributed to this member will be hidden from you. Family membership, shared storage and saved memories are not deleted.'
            : 'Their available vault and contributions will be visible to you again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(blocked ? 'Block' : 'Unblock'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await (service ?? ContentSafetyService()).setBlocked(memberId, blocked);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(safetyErrorMessage(error))));
    }
    return false;
  }
}
