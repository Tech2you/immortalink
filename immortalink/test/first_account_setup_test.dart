import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/services/first_account_setup.dart';
import 'package:immortalink/screens/first_account_setup_screen.dart';

void main() {
  test('only explicitly enrolled new accounts see setup', () {
    expect(needsFirstAccountSetup(null), false);
    expect(needsFirstAccountSetup({}), false);
    expect(needsFirstAccountSetup({'full_name': 'Frank'}), false);
    expect(needsFirstAccountSetup({firstAccountSetupKey: 'pending'}), true);
    expect(needsFirstAccountSetup({firstAccountSetupKey: 'complete'}), false);
  });

  test('resume supports all steps and rejects invalid metadata', () {
    for (var step = 0; step < 4; step++) {
      expect(firstAccountSetupStep({firstAccountSetupStepKey: step}), step);
    }
    for (final invalid in [null, -1, 4, '2', true]) {
      expect(firstAccountSetupStep({firstAccountSetupStepKey: invalid}), 0);
    }
  });

  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('setup remains scrollable and usable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 640),
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Scaffold(
              body: SetupStepLayout(
                step: 3,
                title: 'Your family tree',
                children: [
                  OutlinedButton.icon(
                    onPressed: () => tapped = true,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Add family and share invites'),
                  ),
                  const SizedBox(height: 300),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Go to my vault'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), null);
      await tester.tap(find.text('Add family and share invites'));
      expect(tapped, true);
      await tester.ensureVisible(find.text('Go to my vault'));
      expect(tester.takeException(), null);
    });
  }
}
