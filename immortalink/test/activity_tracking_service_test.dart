import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:immortalink/services/activity_tracking_service.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late List<AppActivity> calls;
  late bool current;
  final trackers = <ActivityTrackingService>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 30, 12);
    calls = [];
    current = true;
  });
  tearDown(() {
    for (final tracker in trackers) {
      tracker.dispose();
    }
    trackers.clear();
  });
  ActivityTrackingService make({
    ActivitySender? send,
    bool enabled = true,
    String user = 'a',
    String namespace = 'test',
    Future<SharedPreferences> Function()? storage,
  }) {
    final tracker = ActivityTrackingService(
      userId: user,
      send:
          send ??
          (event, _) async {
            calls.add(event);
            return true;
          },
      isCurrentUser: () => current,
      preferences: storage ?? () async => prefs,
      clock: () => now,
      enabled: enabled,
      namespace: namespace,
    );
    trackers.add(tracker);
    return tracker;
  }

  testWidgets(
    'coalesces concurrent activity and persists one UTC day across relaunch',
    (tester) async {
      final t = make();
      for (var i = 0; i < 10; i++) {
        t.record(AppActivity.active);
      }
      await tester.pump();
      t.record(AppActivity.active);
      await tester.pump();
      t.dispose();
      final next = make();
      next.record(AppActivity.active);
      await tester.pump();
      expect(calls, [AppActivity.active]);
      now = now.add(const Duration(days: 1));
      next.record(AppActivity.active);
      await tester.pump();
      expect(calls.length, 2);
    },
  );
  testWidgets(
    'timeout is silent with at most one retry and no relaunch retry storm',
    (tester) async {
      Future<bool> stalled(AppActivity event, String? _) {
        calls.add(event);
        return Completer<bool>().future;
      }

      final t = make(send: stalled);
      t.record(AppActivity.active);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 60));
      expect(calls.length, 2);
      expect(tester.takeException(), isNull);
      t.dispose();
      make(send: stalled).record(AppActivity.active);
      await tester.pump();
      expect(calls.length, 2);
    },
  );
  testWidgets(
    'storage failure has bounded retries and never escapes to app UI',
    (tester) async {
      var reads = 0;
      make(
        storage: () async {
          reads++;
          throw StateError('disk unavailable');
        },
      ).record(AppActivity.active);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 60));
      expect(reads, 2);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'sign-out while preferences load prevents sending; mismatched save is ignored',
    (tester) async {
      final pending = Completer<SharedPreferences>();
      final t = make(storage: () => pending.future);
      t.record(AppActivity.active);
      await tester.pump();
      current = false;
      pending.complete(prefs);
      await tester.pump();
      expect(calls, isEmpty);
      current = true;
      final next = make(user: 'b');
      next.record(
        AppActivity.memorySaved,
        subject: 'memory-a',
        expectedUserId: 'a',
      );
      await tester.pump();
      expect(calls, isEmpty);
    },
  );
  testWidgets('background and disposal cancel scheduled retries', (
    tester,
  ) async {
    final t = make(
      send: (e, _) async {
        calls.add(e);
        throw StateError('offline');
      },
    );
    t.record(AppActivity.active);
    await tester.pump();
    t.setForeground(false);
    await tester.pump(const Duration(minutes: 1));
    expect(calls.length, 1);
    t.setForeground(true);
    await tester.pump();
    t.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(calls.length, 2);
  });
  testWidgets(
    'milestones deduplicate across days, accounts and test/production remain separate',
    (tester) async {
      final t = make();
      t.record(AppActivity.memorySaved, subject: 'memory');
      await tester.pump();
      t.dispose();
      now = now.add(const Duration(days: 1));
      make().record(AppActivity.memorySaved, subject: 'another');
      await tester.pump();
      expect(calls.length, 1);
      make(user: 'b').record(AppActivity.memorySaved, subject: 'b-memory');
      await tester.pump();
      make(
        namespace: 'production',
      ).record(AppActivity.memorySaved, subject: 'production-memory');
      await tester.pump();
      expect(calls.length, 3);
    },
  );
  testWidgets(
    'compile switch and per-account opt-out prevent sends; opt-in is reversible',
    (tester) async {
      make(enabled: false).record(AppActivity.active);
      await tester.pump();
      expect(calls, isEmpty);
      final t = make();
      await t.setAllowed(false);
      t.record(AppActivity.active);
      await tester.pump();
      expect(calls, isEmpty);
      t.dispose();
      final next = make();
      next.record(AppActivity.active);
      await tester.pump();
      expect(calls, isEmpty);
      await next.setAllowed(true);
      await tester.pump();
      expect(calls.length, 1);
    },
  );
  testWidgets(
    'server pause never marks a milestone completed or schedules background retries',
    (tester) async {
      make(
        send: (e, _) async {
          calls.add(e);
          return false;
        },
      ).record(AppActivity.inviteAccepted, subject: 'family');
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(calls.length, 1);
      expect(
        prefs.getString('activity.test.a.inviteAccepted.complete'),
        isNull,
      );
    },
  );
}
