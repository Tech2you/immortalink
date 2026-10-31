import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:immortalink/screens/usage_statistics_screen.dart';
import 'package:immortalink/services/activity_tracking_service.dart';

void main() {
  testWidgets(
    'usage control remains readable at 320px with large text and stops future sends',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final tracker = ActivityTrackingService(
        userId: 'test-user',
        send: (e, s) async {
          calls++;
          return true;
        },
        isCurrentUser: () => true,
        preferences: SharedPreferences.getInstance,
      );
      ActivityTrackingService.current = tracker;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tracker.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const UsageStatisticsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      tracker.record(AppActivity.active);
      await tester.pump();
      expect(calls, 0);
      expect(await tracker.isAllowed(), false);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
