import 'dart:convert';

import 'package:flutter/material.dart';

const String _defaultEverRootFamilyUpgradeMessage =
    'Ever Roots Family unlocks relatives in your family tree, family invites, '
    'Family Feed sharing, and higher memory, photo, voice, storage, and AI '
    'limits. Subscriptions will be available after App Store billing is '
    'connected.';

bool isEverRootFamilyUpgradeError(Object error) {
  final text = error.toString();
  return text.contains('ERR_EVERROOT_FAMILY_REQUIRED') ||
      text.contains('ERR_EVERROOT_FREE_FAMILY_LIMIT') ||
      text.contains('ERR_EVERROOT_MEMBER_LIMIT') ||
      text.contains('Start Ever Roots Family') ||
      text.contains('Start EverRoot Family') ||
      text.contains('EverRoot Free includes one personal family tree');
}

Future<void> showEverRootFamilyUpgradePrompt(
  BuildContext context, {
  String? message,
}) {
  final body =
      cleanEverRootUpgradeMessage(message) ??
      _defaultEverRootFamilyUpgradeMessage;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ever Roots Family'),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String everRootUpgradeMessageFromError(Object error) {
  return cleanEverRootUpgradeMessage(error.toString()) ??
      _defaultEverRootFamilyUpgradeMessage;
}

String? cleanEverRootUpgradeMessage(String? rawMessage) {
  final text = rawMessage?.trim();
  if (text == null || text.isEmpty) return null;

  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final message = decoded['message']?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return _normalizeEverRootsName(message);
      }
    }
  } on FormatException {
    // PostgREST may also surface errors as a plain object string.
  }

  final quotedMessage = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
  if (quotedMessage != null) {
    final message = quotedMessage.group(1)?.trim();
    if (message != null && message.isNotEmpty) {
      return _normalizeEverRootsName(message);
    }
  }

  final plainMessage = RegExp(r'message:\s*([^,}]+)').firstMatch(text);
  if (plainMessage != null) {
    final message = plainMessage.group(1)?.trim();
    if (message != null && message.isNotEmpty) {
      return _normalizeEverRootsName(message);
    }
  }

  return _normalizeEverRootsName(text);
}

String _normalizeEverRootsName(String text) {
  return text
      .replaceAll('EverRoot Family', 'Ever Roots Family')
      .replaceAll('EverRoot Free', 'Ever Roots Free')
      .replaceAll('Start EverRoot', 'Start Ever Roots');
}
