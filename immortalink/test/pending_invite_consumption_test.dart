import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:immortalink/services/onboarding_invite_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('presented invite does not return on another sign-in', () async {
    await savePendingFamilyInviteCode(' abc123 ');
    await clearPendingFamilyInviteCode(expectedCode: 'ABC123');
    expect(await pendingFamilyInviteCode(), isEmpty);
  });
  test('finishing an older invite does not erase a new invite', () async {
    await savePendingFamilyInviteCode('NEW123');
    await clearPendingFamilyInviteCode(expectedCode: 'OLD123');
    expect(await pendingFamilyInviteCode(), 'NEW123');
  });
}
