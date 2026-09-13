import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/family_invite_share.dart';

void main() {
  test('builds app invite links with normalized codes', () {
    expect(
      familyInviteUri(' abcd 1234 ').toString(),
      'com.everroots.app://join?code=ABCD1234',
    );
  });

  test('builds web invite links that chat apps can auto-link', () {
    expect(
      familyInviteWebUri(' abcd 1234 ').toString(),
      'https://everroots.org/invite/ABCD1234',
    );
  });

  test('puts manual invite code before app link in share text', () {
    final message = familyInviteMessage(' abcd 1234 ');

    expect(message, contains('enter this invite code:\nABCD1234'));
    expect(
      message.indexOf('ABCD1234'),
      lessThan(message.indexOf('https://everroots.org/invite/ABCD1234')),
    );
  });

  test('parses current app invite links', () {
    expect(
      familyInviteCodeFromUri(
        Uri.parse('com.everroots.app://join?code=abcd1234'),
      ),
      'ABCD1234',
    );
  });

  test('parses future web invite links', () {
    expect(
      familyInviteCodeFromUri(Uri.parse('https://everroots.org/invite/xy%20z')),
      'XYZ',
    );
  });

  test('ignores unrelated links', () {
    expect(
      familyInviteCodeFromUri(Uri.parse('https://example.com/invite/abcd')),
      '',
    );
  });

  test('rejects unowned, insecure and lookalike website domains', () {
    for (final link in [
      'https://everroots.app/invite/ABCD1234',
      'https://www.everroots.app/invite/ABCD1234',
      'http://everroots.org/invite/ABCD1234',
      'https://everroots.org.example.com/invite/ABCD1234',
    ]) {
      expect(familyInviteCodeFromUri(Uri.parse(link)), '', reason: link);
    }
    expect(familyInviteMessage('ABCD1234'), isNot(contains('everroots.app')));
  });
}
