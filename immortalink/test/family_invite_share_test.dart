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
      'https://heiro.app/invite/ABCD1234',
    );
  });

  test('puts manual invite code before app link in share text', () {
    final message = familyInviteMessage(' abcd 1234 ');

    expect(message, contains('join our family on Heiro'));
    expect(message, contains('Open Heiro'));
    expect(message, contains('enter this invite code:\nABCD1234'));
    expect(
      message.indexOf('ABCD1234'),
      lessThan(message.indexOf('https://heiro.app/invite/ABCD1234')),
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

  test('parses Heiro and legacy web invite links', () {
    for (final host in ['heiro.app', 'everroots.org']) {
      for (final path in [
        '/invite/xy%20z',
        '/invite?code=xy%20z',
        '/join?code=xy%20z',
      ]) {
        expect(familyInviteCodeFromUri(Uri.parse('https://$host$path')), 'XYZ');
      }
    }
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
      'http://heiro.app/invite/ABCD1234',
      'https://heiro.app.example.com/invite/ABCD1234',
      'https://heiro.app@evil.example/invite/ABCD1234',
      'https://www.heiro.app/invite/ABCD1234',
    ]) {
      expect(familyInviteCodeFromUri(Uri.parse(link)), '', reason: link);
    }
    expect(familyInviteMessage('ABCD1234'), isNot(contains('everroots.app')));
  });
}
