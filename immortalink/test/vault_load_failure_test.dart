import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/utils/public_error.dart';
import 'package:immortalink/widgets/vault_load_failure.dart';

void main() {
  const secret = 'private-host.supabase.co user-123 token=secret';
  test(
    'public errors never echo backend details or arbitrary exception text',
    () {
      final errors = <Object>[
        http.ClientException(
          secret,
          Uri.parse(
            'https://private-host.supabase.co/rest/v1/vaults?owner_id=user-123',
          ),
        ),
        TimeoutException(secret),
        const AuthException(secret),
        const PostgrestException(
          message: secret,
          code: '42501',
          details: secret,
          hint: secret,
        ),
        const PostgrestException(message: secret, code: '500'),
        StateError(secret),
      ];
      for (final error in errors) {
        final message = publicErrorMessage(error);
        expect(message, isNot(contains('supabase')));
        expect(message, isNot(contains('user-123')));
        expect(message, isNot(contains('secret')));
      }
      expect(
        isConnectionFailure(
          const PostgrestException(
            message: 'ClientException offline',
            code: '42501',
          ),
        ),
        isFalse,
      );
      expect(
        isConnectionFailure(const AuthException('SocketException offline')),
        isFalse,
      );
    },
  );
  testWidgets(
    'offline failure offers cached access and retry on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retried = 0;
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: VaultLoadFailure(
                  error: http.ClientException(secret),
                  onRetry: () => retried++,
                  onRecentlyViewed: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Unable to connect'), findsOneWidget);
      expect(find.textContaining('supabase'), findsNothing);
      await tester.ensureVisible(find.text('Recently viewed'));
      await tester.tap(find.text('Recently viewed'));
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      expect(opened, 1);
      expect(retried, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
