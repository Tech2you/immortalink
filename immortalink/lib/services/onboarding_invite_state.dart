import 'package:shared_preferences/shared_preferences.dart';

const pendingFamilyInviteCodePreferenceKey = 'pending_family_invite_code';

String normalizeInviteCode(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

Future<String> pendingFamilyInviteCode() async {
  final prefs = await SharedPreferences.getInstance();
  return normalizeInviteCode(
    prefs.getString(pendingFamilyInviteCodePreferenceKey) ?? '',
  );
}

Future<void> savePendingFamilyInviteCode(String value) async {
  final code = normalizeInviteCode(value);
  final prefs = await SharedPreferences.getInstance();
  if (code.isEmpty) {
    await prefs.remove(pendingFamilyInviteCodePreferenceKey);
    return;
  }
  await prefs.setString(pendingFamilyInviteCodePreferenceKey, code);
}

Future<void> clearPendingFamilyInviteCode() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(pendingFamilyInviteCodePreferenceKey);
}
