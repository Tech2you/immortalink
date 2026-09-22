import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/family_tree_settings_menu.dart';

void main() {
  testWidgets('gear exposes each action and dispatches the selected action', (
    tester,
  ) async {
    FamilyTreeAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              FamilyTreeSettingsMenu(
                onSelected: (action) => selected = action,
                canRecenter: true,
                canLeave: true,
                canEditName: true,
              ),
            ],
          ),
        ),
      ),
    );
    const labels = [
      'Recenter',
      'Refresh',
      'Leave family',
      'Change family photo',
      'Change family name',
    ];
    const actions = [
      FamilyTreeAction.recenter,
      FamilyTreeAction.refresh,
      FamilyTreeAction.leave,
      FamilyTreeAction.photo,
      FamilyTreeAction.name,
    ];
    for (var i = 0; i < labels.length; i++) {
      await tester.tap(find.byTooltip('Family tree settings'));
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(labels[i]));
      await tester.pumpAndSettle();
      expect(selected, actions[i]);
    }
  });

  testWidgets('non-owner cannot rename; large text fits a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              FamilyTreeSettingsMenu(
                onSelected: (_) {},
                canRecenter: true,
                canLeave: true,
                canEditName: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Family tree settings'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<FamilyTreeAction>>(
      find.ancestor(
        of: find.text('Change family name'),
        matching: find.byType(PopupMenuItem<FamilyTreeAction>),
      ),
    );
    expect(item.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
