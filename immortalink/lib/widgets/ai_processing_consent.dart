import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _pendingConsent = <String, Future<bool>>{};

Future<bool> requestAiProcessingConsent(
  BuildContext context, {
  SupabaseClient? client,
  bool settings = false,
}) async {
  final backend = client ?? Supabase.instance.client;
  final userId = backend.auth.currentUser?.id;
  if (userId == null) return false;
  final pending = _pendingConsent[userId];
  if (pending != null) return pending;
  final result = _request(context, backend, userId, settings);
  _pendingConsent[userId] = result;
  try {
    return await result;
  } finally {
    _pendingConsent.remove(userId);
  }
}

Future<bool> _request(
  BuildContext context,
  SupabaseClient backend,
  String userId,
  bool settings,
) async {
  bool current() => context.mounted && backend.auth.currentUser?.id == userId;
  try {
    final allowed = await backend.rpc('has_ai_processing_consent')
        .timeout(const Duration(seconds: 12));
    if (!context.mounted || !current()) return false;
    if (allowed == true && !settings) return true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI data permission'),
        content: const SingleChildScrollView(
          child: Text(
            'Allow Heiro to send your chat questions and relevant saved '
            'profile details, family memories and transcripts to OpenAI to '
            'generate AI replies and suggested questions? Voice notes submitted '
            'for transcription are also sent to OpenAI. This can include personal '
            'information about you and relatives.\n\n'
            'This is optional. Without permission, memories and recordings can '
            'still be saved and read, but AI chat and transcription stay off. '
            'You can withdraw permission in AI data permission settings. '
            'Withdrawal stops future requests; it cannot recall data already sent.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(allowed == true ? 'Turn off AI' : 'Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(allowed == true ? 'Keep enabled' : 'Allow OpenAI processing'),
          ),
        ],
      ),
    );
    if (!current() || choice == null) return false;
    await backend.rpc('set_ai_processing_consent', params: {'p_allowed': choice})
        .timeout(const Duration(seconds: 12));
    return current() && choice;
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not confirm AI permission. No new AI request was sent.')),
      );
    }
    return false;
  }
}
