import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AppActivity { active, memorySaved, inviteAccepted }

typedef ActivitySender =
    Future<bool> Function(AppActivity event, String? subject);

/// Optional measurements. No caller waits for this service and it never reports
/// failures to the app's connection/error UI. Payloads never contain content.
class ActivityTrackingService {
  ActivityTrackingService({
    required this.userId,
    required this.send,
    required this.isCurrentUser,
    required this.preferences,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 30),
    this.enabled = true,
    this.namespace = 'production',
  }) : clock = clock ?? DateTime.now;

  static ActivityTrackingService? current;
  static const buildEnabled = bool.fromEnvironment(
    'HEIRO_ACTIVITY_ENABLED',
    defaultValue: true,
  );
  static const testBuild =
      !kReleaseMode ||
      bool.fromEnvironment('HEIRO_ACTIVITY_TEST_BUILD', defaultValue: false);

  static ActivityTrackingService forUser(String userId) {
    final client = Supabase.instance.client;
    return ActivityTrackingService(
      userId: userId,
      enabled: buildEnabled,
      namespace: testBuild ? 'test' : 'production',
      preferences: SharedPreferences.getInstance,
      isCurrentUser: () => client.auth.currentUser?.id == userId,
      send: (event, subject) async {
        final result = await client.rpc(
          'record_app_activity',
          params: {
            'p_expected_user_id': userId,
            'p_event': switch (event) {
              AppActivity.active => 'active',
              AppActivity.memorySaved => 'memory_saved',
              AppActivity.inviteAccepted => 'invite_accepted',
            },
            'p_subject_id': subject,
            'p_test_build': testBuild,
          },
        );
        // A paused server is handled as complete for this day: no busy retries.
        return result == true;
      },
    );
  }

  final String userId;
  final String namespace;
  final ActivitySender send;
  final bool Function() isCurrentUser;
  final Future<SharedPreferences> Function() preferences;
  final DateTime Function() clock;
  final Duration timeout;
  final Duration retryDelay;
  final bool enabled;
  final Set<AppActivity> _pending = {};
  final Map<AppActivity, Timer> _retries = {};
  final Map<AppActivity, (String, int)> _attempts = {};
  bool _disposed = false;
  bool _foreground = true;
  bool _allowed = true;

  String get preferenceKey => 'activity.allowed.$userId';
  String get _prefix => 'activity.$namespace.$userId';
  bool get _canSend =>
      enabled && !_disposed && _foreground && _allowed && isCurrentUser();

  void record(AppActivity event, {String? subject, String? expectedUserId}) {
    if (expectedUserId != null && expectedUserId != userId) return;
    // Includes synchronous adapters, storage errors and timeout failures.
    unawaited(_record(event, subject).catchError((Object _) {}));
  }

  Future<void> _record(AppActivity event, String? subject) async {
    if (!_canSend || !_pending.add(event)) return;
    try {
      final day = clock().toUtc().toIso8601String().substring(0, 10);
      final previous = _attempts[event];
      final localAttempts = previous?.$1 == day ? previous!.$2 : 0;
      if (localAttempts >= 2) return;
      _attempts[event] = (day, localAttempts + 1);
      final prefs = await preferences().timeout(timeout);
      if (!_canSend || !(prefs.getBool(preferenceKey) ?? true)) return;
      final key = '$_prefix.${event.name}';
      final complete = prefs.getString('$key.complete');
      // Milestones are lifetime observations; active counts are UTC days.
      if (complete == day ||
          (event != AppActivity.active && complete != null)) {
        return;
      }
      final parts = (prefs.getString('$key.attempts') ?? '').split(':');
      final attempts = parts.length == 2 && parts.first == day
          ? int.tryParse(parts.last) ?? 0
          : 0;
      if (attempts >= 2) return;
      // One bounded retry per event/day, persisted across app relaunches.
      await prefs
          .setString('$key.attempts', '$day:${attempts + 1}')
          .timeout(timeout);
      if (!_canSend) return;
      final accepted = await send(event, subject).timeout(timeout);
      if (accepted) {
        await prefs.setString('$key.complete', day).timeout(timeout);
      }
      // false means collection is paused/disabled, not a network failure.
    } catch (_) {
      if (_canSend &&
          (_attempts[event]?.$2 ?? 2) < 2 &&
          !_retries.containsKey(event)) {
        _retries[event] = Timer(retryDelay, () {
          _retries.remove(event);
          record(event, subject: subject);
        });
      }
    } finally {
      _pending.remove(event);
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      for (final timer in _retries.values) {
        timer.cancel();
      }
      _retries.clear();
    } else {
      record(AppActivity.active);
    }
  }

  Future<bool> isAllowed() async =>
      (await preferences().timeout(timeout)).getBool(preferenceKey) ?? true;

  Future<void> setAllowed(bool value) async {
    _allowed = value;
    if (!value) {
      for (final timer in _retries.values) {
        timer.cancel();
      }
      _retries.clear();
    }
    final prefs = await preferences().timeout(timeout);
    if (!await prefs.setBool(preferenceKey, value).timeout(timeout)) {
      throw StateError('Preference could not be saved');
    }
    if (value) record(AppActivity.active);
  }

  void dispose() {
    _disposed = true;
    for (final timer in _retries.values) {
      timer.cancel();
    }
    _retries.clear();
    if (identical(current, this)) current = null;
  }
}
