import 'dart:convert';

import 'package:flutter/material.dart';

const String _defaultEverRootFamilyUpgradeMessage =
    'Ever Roots Family unlocks relatives in your family tree, family invites, '
    'Family Feed sharing, and higher memory, photo, voice, storage, and AI '
    'limits. Subscriptions will be available after App Store billing is '
    'connected.';

bool isEverRootFamilyUpgradeError(Object error) {
  final text = error.toString();
  return text.contains('ERR_EVERROOT_STORAGE_LIMIT') ||
      text.contains('ERR_EVERROOT_PHOTO_LIMIT') ||
      text.contains('ERR_EVERROOT_VOICE_LIMIT') ||
      text.contains('ERR_EVERROOT_MEMORY_LIMIT') ||
      text.contains('ERR_EVERROOT_LEGACY_LIMIT') ||
      text.contains('ERR_EVERROOT_AI_LIMIT') ||
      text.contains('ERR_EVERROOT_TRANSCRIPTION_LIMIT');
}

bool isEverRootQuotaError(Object error) {
  return error.toString().contains('ERR_EVERROOT_');
}

String everRootQuotaMessageFromError(Object error) {
  final text = error.toString();
  final message = _friendlyQuotaMessage(text);

  if (text.contains('ERR_EVERROOT_INVITE_COOLDOWN')) {
    return 'Please wait a moment before creating another invite.';
  }
  if (text.contains('ERR_EVERROOT_INVITE_LIMIT')) {
    return message ??
        'This family has used this month\'s invite allowance. Try again later.';
  }
  if (text.contains('ERR_EVERROOT_MEMBER_LIMIT')) {
    return message ??
        'This family has reached its real family member allowance.';
  }
  if (text.contains('ERR_EVERROOT_FREE_FAMILY_LIMIT')) {
    return 'You already have a primary free family tree. You can still join relatives when the invite does not need to become your primary tree.';
  }
  if (text.contains('ERR_EVERROOT_FAMILY_REQUIRED')) {
    return 'Family invites are being enabled for free families. Please update the app and try again.';
  }

  return message ?? 'This Ever Roots action reached a family allowance.';
}

String? _friendlyQuotaMessage(String text) {
  final message = cleanEverRootUpgradeMessage(text);
  if (message == null || message.contains('ERR_EVERROOT_')) return null;
  return message;
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
