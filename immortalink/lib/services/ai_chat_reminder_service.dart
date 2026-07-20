import 'package:shared_preferences/shared_preferences.dart';

class AiChatReminderService {
  static const int reminderLoginInterval = 10;

  static String _loginCountKey(String userId) => 'ai_chat_login_count_$userId';
  static String _lastAcceptedKey(String userId) =>
      'ai_chat_warning_last_accepted_$userId';
  static String _neverShowKey(String userId) =>
      'ai_chat_warning_never_show_$userId';

  static Future<void> recordSuccessfulLogin(String userId) async {
    if (userId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _loginCountKey(userId);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  static Future<bool> shouldShow(String userId) async {
    if (userId.trim().isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_neverShowKey(userId)) ?? false) return false;

    final lastAccepted = prefs.getInt(_lastAcceptedKey(userId));
    if (lastAccepted == null) return true;
    final loginCount = prefs.getInt(_loginCountKey(userId)) ?? 0;
    return loginCount - lastAccepted >= reminderLoginInterval;
  }

  static Future<void> accept(
    String userId, {
    required bool neverShowAgain,
  }) async {
    if (userId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_neverShowKey(userId), neverShowAgain);
    await prefs.setInt(
      _lastAcceptedKey(userId),
      prefs.getInt(_loginCountKey(userId)) ?? 0,
    );
  }
}
