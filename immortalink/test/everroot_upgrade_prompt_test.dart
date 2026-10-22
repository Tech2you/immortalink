import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/everroot_upgrade_prompt.dart';

void main() {
  test(
    'normalizes historical plan display names without changing error codes',
    () {
      expect(
        cleanEverRootUpgradeMessage('EverRoot Family or Ever Roots Legacy'),
        'Heiro Family or Heiro Legacy',
      );
      expect(
        cleanEverRootUpgradeMessage(
          '{"message":"Start EverRoot with Ever Roots Family"}',
        ),
        'Start Heiro with Heiro Family',
      );
      expect(
        cleanEverRootUpgradeMessage('ERR_EVERROOT_STORAGE_LIMIT'),
        'ERR_EVERROOT_STORAGE_LIMIT',
      );
    },
  );

  group('EverRoot quota messages', () {
    test('burst cooldown is friendly and is not an upgrade prompt', () {
      const error = 'ERR_EVERROOT_USAGE_BURST: private implementation detail';
      expect(isEverRootFamilyUpgradeError(error), isFalse);
      final message = everRootQuotaMessageFromError(error);
      expect(message, isNot(contains('private implementation')));
      expect(message, isNot(contains('ERR_')));
      expect(message, contains('wait'));
    });
    test('read-only message preserves access and hides technical details', () {
      const error = 'ERR_EVERROOT_READ_ONLY: internal https://private.example';
      expect(isEverRootFamilyUpgradeError(error), isTrue);
      final message = everRootQuotaMessageFromError(error);
      expect(message, contains('Existing memories are still available'));
      expect(message, isNot(contains('private.example')));
      expect(message, isNot(contains('ERR_')));
    });
    test('does not treat invite/member growth limits as upgrade prompts', () {
      expect(
        isEverRootFamilyUpgradeError('ERR_EVERROOT_INVITE_LIMIT'),
        isFalse,
      );
      expect(
        isEverRootFamilyUpgradeError('ERR_EVERROOT_MEMBER_LIMIT'),
        isFalse,
      );
      expect(
        isEverRootFamilyUpgradeError('ERR_EVERROOT_FAMILY_REQUIRED'),
        isFalse,
      );
    });

    test('still treats expensive usage limits as upgrade prompts', () {
      expect(
        isEverRootFamilyUpgradeError('ERR_EVERROOT_STORAGE_LIMIT'),
        isTrue,
      );
      expect(isEverRootFamilyUpgradeError('ERR_EVERROOT_AI_LIMIT'), isTrue);
      expect(
        isEverRootFamilyUpgradeError('ERR_EVERROOT_TRANSCRIPTION_LIMIT'),
        isTrue,
      );
    });

    test('returns friendly invite quota copy', () {
      expect(
        everRootQuotaMessageFromError('ERR_EVERROOT_INVITE_COOLDOWN'),
        'Please wait a moment before creating another invite.',
      );
      expect(
        everRootQuotaMessageFromError('ERR_EVERROOT_MEMBER_LIMIT'),
        contains('real family member allowance'),
      );
    });

    test('returns family storage upgrade copy for storage upload failures', () {
      expect(
        everRootUploadErrorMessage('ERR_EVERROOT_STORAGE_LIMIT'),
        contains('sponsor'),
      );
      expect(
        everRootUploadErrorMessage('ERR_EVERROOT_STORAGE_LIMIT'),
        contains('storage allowance'),
      );
    });

    test('formats storage usage for plan dialogs', () {
      expect(formatEverRootStorageBytes(524288000), '500 MB');
      expect(
        everRootStorageUsageMessage(
          usedBytes: 419430400,
          limitBytes: 524288000,
        ),
        '400 MB of 500 MB used (80%)',
      );
    });
  });
}
