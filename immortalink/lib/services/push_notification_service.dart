import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pushDeviceIdPreferenceKey = 'ever_roots_push_device_id';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.ensureFirebaseInitialized();
}

enum PushNotificationTarget { familyFeed }

class PushNotificationIntent {
  final PushNotificationTarget target;
  final String? familyId;

  const PushNotificationIntent.familyFeed({this.familyId})
    : target = PushNotificationTarget.familyFeed;
}

class PushNotificationService {
  PushNotificationService._();

  static final ValueNotifier<PushNotificationIntent?> intent =
      ValueNotifier<PushNotificationIntent?>(null);

  static bool _firebaseInitialized = false;
  static bool _messageHandlersAttached = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  static bool get _supportsFirebaseMessaging {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static Future<bool> ensureFirebaseInitialized() async {
    if (!_supportsFirebaseMessaging) return false;
    if (_firebaseInitialized) return true;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _firebaseInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Firebase initialization skipped: $e');
      return false;
    }
  }

  static Future<void> configureMessageHandlers() async {
    if (_messageHandlersAttached) return;
    final ready = await ensureFirebaseInitialized();
    if (!ready) return;

    _messageHandlersAttached = true;

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }
  }

  static Future<void> registerForCurrentUser() async {
    final ready = await ensureFirebaseInitialized();
    if (!ready) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await configureMessageHandlers();

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _saveToken(token.trim(), user.id);
      }

      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
          .listen((nextToken) async {
            final currentUser = Supabase.instance.client.auth.currentUser;
            if (currentUser == null || nextToken.trim().isEmpty) return;
            try {
              await _saveToken(nextToken.trim(), currentUser.id);
            } catch (e) {
              debugPrint('Push token refresh skipped: $e');
            }
          });
    } catch (e) {
      debugPrint('Push notification registration skipped: $e');
    }
  }

  static Future<void> clearLocalTokenRegistration() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  static Future<void> notifyFamilyMemoryAdded(String memoryId) async {
    await _notifyFamilyEvent(
      type: 'memory_added',
      body: {'memory_id': memoryId},
    );
  }

  static Future<void> notifyFamilyJoined(String familyId) async {
    await _notifyFamilyEvent(
      type: 'family_joined',
      body: {'family_id': familyId},
    );
  }

  static Future<void> _notifyFamilyEvent({
    required String type,
    required Map<String, String> body,
  }) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.trim().isEmpty) return;

    try {
      await Supabase.instance.client.functions
          .invoke(
            'send_family_notification',
            headers: {
              'Authorization': 'Bearer $token',
              'authorization': 'Bearer $token',
            },
            body: {'type': type, ...body},
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Family push notification skipped: $e');
    }
  }

  static Future<void> _saveToken(String token, String userId) async {
    final deviceId = await _deviceId();
    await Supabase.instance.client.from('user_push_tokens').upsert({
      'user_id': userId,
      'token': token,
      'device_id': deviceId,
      'platform': defaultTargetPlatform.name,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_pushDeviceIdPreferenceKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final created = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(_pushDeviceIdPreferenceKey, created);
    return created;
  }

  static void _handleMessageTap(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString();
    if (type != 'family_feed') return;

    final familyId = (message.data['family_id'] ?? '').toString().trim();
    intent.value = PushNotificationIntent.familyFeed(
      familyId: familyId.isEmpty ? null : familyId,
    );
  }
}
