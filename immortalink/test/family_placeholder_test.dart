import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/family_placeholder.dart';

void main() {
  test('renamed placeholders use the saved name and are no longer yellow', () {
    final name = familyProfileName({
      'name': 'dirk',
      'display_name': 'Child not added yet',
    }, 'Family member');
    expect(name, 'dirk');
    expect(isUnfilledFamilyProfile(name), isFalse);
  });

  test('real display names and unfilled placeholders are preserved', () {
    expect(
      familyProfileName({'name': 'Dirk', 'display_name': 'Dad'}, ''),
      'Dad',
    );
    final placeholder = familyProfileName({
      'name': 'Parent not added yet',
      'display_name': 'Parent not added yet',
    }, 'Family member');
    expect(isUnfilledFamilyProfile(placeholder), isTrue);
    expect(
      familyProfileName({'name': ' Dirk ', 'display_name': ''}, ''),
      'Dirk',
    );
    expect(familyProfileName({}, 'Family member'), 'Family member');
  });

  test('all generated missing relatives are placeholders', () {
    for (final relation in [
      'Parent',
      'Grandparent',
      'Child',
      'Grandchild',
      'Predecessor',
      'Descendant',
      'Great-grandchild',
    ]) {
      expect(isUnfilledFamilyProfile('$relation not added yet'), isTrue);
    }
    expect(isUnfilledFamilyProfile('  GRANDPARENT  not added yet '), isTrue);
    expect(isUnfilledFamilyProfile('Patricia'), isFalse);
    expect(isUnfilledFamilyProfile('Greta'), isFalse);
  });
}
