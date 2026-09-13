import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/onboarding_invite_state.dart';

Uri familyInviteUri(String code) {
  final normalized = normalizeInviteCode(code);
  return Uri(
    scheme: 'com.everroots.app',
    host: 'join',
    queryParameters: {'code': normalized},
  );
}

Uri familyInviteWebUri(String code) {
  final normalized = normalizeInviteCode(code);
  return Uri.https('everroots.org', '/invite/$normalized');
}

String familyInviteMessage(String code) {
  final normalized = normalizeInviteCode(code);
  return [
    "I've invited you to join our family on Ever Roots.",
    '',
    'Open Ever Roots and enter this invite code:',
    normalized,
    '',
    'Invite link:',
    familyInviteWebUri(normalized).toString(),
  ].join('\n');
}

String familyInviteCodeFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final isEverRootsHost = host == 'everroots.org';

  final isAppJoinLink =
      scheme == 'com.everroots.app' && (host == 'join' || path == '/join');
  final isWebJoinLink =
      scheme == 'https' &&
      isEverRootsHost &&
      (path == '/join' || path == '/invite' || path.startsWith('/invite/'));

  if (!isAppJoinLink && !isWebJoinLink) return '';

  final queryCode =
      uri.queryParameters['code'] ??
      uri.queryParameters['invite'] ??
      uri.queryParameters['invite_code'];
  final pathCode = path.startsWith('/invite/') ? uri.pathSegments.last : '';

  return normalizeInviteCode(queryCode ?? pathCode);
}

Future<void> copyInviteLink(String code) async {
  await Clipboard.setData(
    ClipboardData(text: familyInviteWebUri(code).toString()),
  );
}

Future<void> copyInviteCode(String code) async {
  await Clipboard.setData(ClipboardData(text: normalizeInviteCode(code)));
}

Future<void> copyInviteMessage(String code) async {
  await Clipboard.setData(ClipboardData(text: familyInviteMessage(code)));
}

Future<void> shareInvite(String code) async {
  final normalized = normalizeInviteCode(code);
  if (normalized.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(
      text: familyInviteMessage(normalized),
      subject: 'Join my family on Ever Roots',
    ),
  );
}

String _formatInviteExpiry(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

Future<void> showFamilyInviteDialog({
  required BuildContext context,
  required String title,
  required String code,
  required DateTime expiresAt,
  String? slotLabel,
}) async {
  final normalized = normalizeInviteCode(code);
  if (normalized.isEmpty) return;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final subduedText = theme.textTheme.bodyMedium?.copyWith(
    color: colorScheme.onSurface.withValues(alpha: 0.62),
  );

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (slotLabel != null && slotLabel.trim().isNotEmpty) ...[
              Text(slotLabel.trim()),
              const SizedBox(height: 12),
            ],
            const Text('Ask them to open Ever Roots and enter this code.'),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.primaryContainer.withValues(alpha: 0.34),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.38),
                ),
              ),
              child: SelectableText(
                normalized,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await copyInviteCode(normalized);
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Invite code copied')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy code'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Expires ${_formatInviteExpiry(expiresAt)}. The code still works if the link opens in a browser.',
              style: subduedText,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => shareInvite(normalized),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share invite'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  await copyInviteMessage(normalized);
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Invite message copied')),
                  );
                },
                icon: const Icon(Icons.text_snippet_outlined),
                label: const Text('Copy full invite message'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  await copyInviteLink(normalized);
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Invite link copied')),
                  );
                },
                icon: const Icon(Icons.link),
                label: const Text('Copy invite link'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
