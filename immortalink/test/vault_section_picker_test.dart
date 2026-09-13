import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/vault_section_picker.dart';

void main() {
  for (final width in [288.0, 358.0, 736.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('tabs fit width $width at text scale $scale', (tester) async {
        int selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: VaultSectionPicker(
                      selected: 0,
                      onChanged: (value) => selected = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(find.text('Memories')).maxLines, 1);
        await tester.tap(find.text('Media'));
        expect(selected, 2);
      });
    }
  }
}
