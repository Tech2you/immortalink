import 'package:supabase_flutter/supabase_flutter.dart';

import 'content_screening_config.dart';

enum ContentSharingState {
  disabled,
  archive,
  notRequested,
  ready,
  permissionRequired,
  queued,
  checking,
  held,
  shared,
  paused,
  unsupported,
  inputLimit,
  limited,
  unavailable,
}

class ContentSharingStatus {
  const ContentSharingStatus(this.state, {this.canRequest = false});

  final ContentSharingState state;
  final bool canRequest;

  static ContentSharingStatus parse(dynamic data) {
    const states = {
      'disabled': ContentSharingState.disabled,
      'archive': ContentSharingState.archive,
      'not_requested': ContentSharingState.notRequested,
      'ready': ContentSharingState.ready,
      'permission_required': ContentSharingState.permissionRequired,
      'queued': ContentSharingState.queued,
      'checking': ContentSharingState.checking,
      'held': ContentSharingState.held,
      'shared': ContentSharingState.shared,
      'paused': ContentSharingState.paused,
      'unsupported': ContentSharingState.unsupported,
      'input_limit': ContentSharingState.inputLimit,
      'unavailable': ContentSharingState.unavailable,
    };
    if (data is! Map || data['can_request'] is! bool) {
      throw const FormatException('Invalid sharing status');
    }
    final state = states[data['state']];
    if (state == null ||
        (data['can_request'] == true &&
            state != ContentSharingState.ready &&
            state != ContentSharingState.permissionRequired)) {
      throw const FormatException('Invalid sharing status');
    }
    return ContentSharingStatus(state, canRequest: data['can_request'] as bool);
  }

  String get message => switch (state) {
    ContentSharingState.disabled => 'Sharing checks are not active.',
    ContentSharingState.archive =>
      'Existing archive. This memory has not been sent for safety checks.',
    ContentSharingState.notRequested => 'Saved. Sharing is turned off.',
    ContentSharingState.ready => 'Saved. Not yet shared with family.',
    ContentSharingState.permissionRequired =>
      'Saved, but not shared. Safety-check permission is needed from every contributor.',
    ContentSharingState.queued =>
      'Saved. Waiting for safety checks before sharing.',
    ContentSharingState.checking => 'Saved. Safety checks are in progress.',
    ContentSharingState.held =>
      'Saved, but held from sharing. A review is required. Do not upload it again.',
    ContentSharingState.shared => 'Available to family members with access.',
    ContentSharingState.paused =>
      'Saved, but not shared. Safety checks are temporarily paused.',
    ContentSharingState.unsupported =>
      'Saved, but not shared. Voice recordings and this media format cannot be checked yet.',
    ContentSharingState.inputLimit =>
      'Saved, but not shared. The text or media exceeds the checking limits, or the memory is empty.',
    ContentSharingState.limited =>
      'Saved, but not shared. Checks are busy. Retry sharing later; do not upload again.',
    ContentSharingState.unavailable =>
      'Sharing status is unavailable. No new sharing has been confirmed.',
  };
}

class ContentSharingService {
  ContentSharingService({
    required this.client,
    required this.expectedUserId,
    this.enabled = contentScreeningControlsEnabled,
  });

  final SupabaseClient client;
  final String expectedUserId;
  final bool enabled;
  static const _timeout = Duration(seconds: 12);

  bool get sameAccount => client.auth.currentUser?.id == expectedUserId;

  void _check(String kind) {
    if (!sameAccount) throw StateError('Account changed');
    if (kind != 'memory' && kind != 'legacy_memory') {
      throw ArgumentError.value(kind, 'kind');
    }
  }

  Map<String, dynamic> _params(String kind, String targetId) => {
    'p_kind': kind,
    'p_target': targetId,
    'p_expected_user_id': expectedUserId,
  };

  Future<ContentSharingStatus> status(String kind, String targetId) async {
    if (!enabled) {
      return const ContentSharingStatus(ContentSharingState.disabled);
    }
    _check(kind);
    final data = await client
        .rpc('get_content_sharing_status', params: _params(kind, targetId))
        .timeout(_timeout);
    _check(kind);
    return ContentSharingStatus.parse(data);
  }

  Future<ContentSharingStatus> request(String kind, String targetId) async {
    if (!enabled) {
      return const ContentSharingStatus(ContentSharingState.disabled);
    }
    _check(kind);
    final data = await client
        .rpc('request_content_screening', params: _params(kind, targetId))
        .timeout(_timeout);
    _check(kind);
    if (data is! Map || data['code'] is! String) {
      throw const FormatException('Invalid sharing request result');
    }
    if (data['code'] == 'QUEUE_LIMIT') {
      return const ContentSharingStatus(
        ContentSharingState.limited,
        canRequest: true,
      );
    }
    // A request acknowledgement is not publication. Read the current server state.
    return status(kind, targetId);
  }
}
