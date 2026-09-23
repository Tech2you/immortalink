import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/account_deletion_billing_notice.dart';

void main() {
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
      expect(find.textContaining('does not cancel'), findsOneWidget);
      await tester.tap(find.text('Manage Apple subscription'));
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      done.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('does not cancel'), findsOneWidget);
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
      await tester.tap(find.text('Manage Apple subscription'));
      await tester.pumpAndSettle();
      expect(find.textContaining('iPhone Settings'), findsOneWidget);
      expect(find.textContaining('private backend'), findsNothing);
    },
  );
}
