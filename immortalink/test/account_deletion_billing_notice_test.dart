import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/vaults_screen.dart'
    show AccountDeletionConfirmationDialog;
import 'package:immortalink/widgets/account_deletion_billing_notice.dart';

void main() {
  for (final checkFails in [false, true]) {
    testWidgets(
      'immediate deletion remains available without Apple cancellation ($checkFails)',
      (tester) async {
        String? result;
        var manageCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => AccountDeletionConfirmationDialog(
                        onManage: () async {
                          manageCalls++;
                        },
                        checkActiveSubscription: () async {
                          if (checkFails) throw StateError('offline');
                          return true;
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(
          tester.getTopLeft(find.byType(AccountDeletionBillingNotice)).dy,
          lessThan(
            tester.getTopLeft(find.byType(AccountDeletionDataNotice)).dy,
          ),
        );
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'fixture password');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        expect(result, 'fixture password');
        expect(manageCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'deletion distinguishes personal data from shared legacy contributions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AccountDeletionDataNotice()),
          ),
        ),
      );
      expect(
        find.textContaining('permanently deletes your account, personal vault'),
        findsOneWidget,
      );
      expect(
        find.textContaining('stay with the remaining family members'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving a family warns that Apple billing continues', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountDeletionBillingNotice(
            leavingFamily: true,
            onManage: () async {},
          ),
        ),
      ),
    );
    expect(find.textContaining('Leaving this family'), findsOneWidget);
    expect(
      find.textContaining('does not cancel an Apple subscription'),
      findsOneWidget,
    );
    expect(find.textContaining('Deleting your account'), findsNothing);
  });

  testWidgets(
    'billing warning stays visible and manage is not a cancellation confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final done = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountDeletionBillingNotice(
                onManage: () {
                  calls++;
                  return done.future;
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('does not cancel an Apple subscription'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel subscription with Apple'));
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      done.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.textContaining('does not cancel an Apple subscription'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed Apple sheet gives manual cancellation path without raw error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountDeletionBillingNotice(
              onManage: () async => throw StateError('private backend detail'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cancel subscription with Apple'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Could not open Apple subscriptions. Cancel in iPhone Settings',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private backend'), findsNothing);
    },
  );

  testWidgets('active purchaser gets explicit billing warning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountDeletionBillingNotice(
            onManage: () async {},
            checkActiveSubscription: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You have an active Apple subscription'), findsOneWidget);
    expect(
      find.textContaining('Apple will continue charging you'),
      findsOneWidget,
    );
    expect(
      find.textContaining('you must cancel later in iPhone Settings'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel subscription with Apple'));
    await tester.pumpAndSettle();
    expect(find.text('You have an active Apple subscription'), findsOneWidget);
    expect(
      find.textContaining('Opening it alone does not cancel'),
      findsOneWidget,
    );
    expect(find.textContaining('already cancelled'), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'unknown or absent coverage never claims billing stopped ($fails)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountDeletionBillingNotice(
                onManage: () async {},
                checkActiveSubscription: () async {
                  if (fails) throw StateError('private backend detail');
                  return false;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('You have an active Apple subscription'),
          findsNothing,
        );
        expect(
          find.text('Apple billing does not stop automatically'),
          findsOneWidget,
        );
        expect(find.text('Cancel subscription with Apple'), findsOneWidget);
        expect(find.textContaining('private backend'), findsNothing);
      },
    );
  }

  testWidgets('late coverage response after closing is ignored', (
    tester,
  ) async {
    final response = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountDeletionBillingNotice(
              onManage: () async {},
              checkActiveSubscription: () => response.future,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    response.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'warning and cancellation button fit a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: AccountDeletionConfirmationDialog(
              onManage: () async {},
              checkActiveSubscription: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel subscription with Apple'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cancel subscription with Apple').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
