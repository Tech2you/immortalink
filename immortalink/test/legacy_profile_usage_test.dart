import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/legacy_profile_usage.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required int cap,
    int? count,
    VoidCallback? onViewPlans,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LegacyProfileUsage(
                limits: {'legacy_people': cap},
                usage: {if (count != null) 'legacy_people': count},
                onViewPlans: onViewPlans,
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final cap in [50, 100, 200, 500, 600, 1000]) {
    testWidgets('counter $cap uses server count and pooled allowance', (
      tester,
    ) async {
      await show(tester, cap: cap, count: 6);
      expect(find.text('6 of $cap used'), findsOneWidget);
      expect(find.text('View contribution options'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(6 / cap, .001),
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final cap in [50, 100, 500, 600]) {
    testWidgets('full $cap opens contribution options', (tester) async {
      var opened = 0;
      await show(tester, cap: cap, count: cap, onViewPlans: () => opened++);
      expect(find.textContaining('profile slots'), findsOneWidget);
      await tester.tap(find.text('View contribution options'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'expired contributions retain the count and offer more capacity',
    (tester) async {
      await show(tester, cap: 100, count: 251, onViewPlans: () {}, scale: 1.7);
      expect(find.text('251 of 100 used'), findsOneWidget);
      expect(
        find.textContaining('Existing profiles remain available'),
        findsOneWidget,
      );
      expect(find.text('View contribution options'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('missing count is unknown, not zero or full', (tester) async {
    await show(tester, cap: 50);
    expect(find.text('Profile usage is unavailable.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('View contribution options'), findsNothing);
  });
}
