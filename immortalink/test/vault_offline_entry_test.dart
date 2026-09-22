import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => 1,
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'test-token',
              'refresh_token': 'test-refresh',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'test-user',
                'aud': 'authenticated',
                'email': 'test@example.com',
                'created_at': '2026-09-15T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        throw http.ClientException(
          'Failed host lookup: private-host.supabase.co owner_id=test-user',
          request.url,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'real vault screen reaches cached content after offline startup',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VaultsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('supabase.co'), findsNothing);
      expect(find.textContaining('owner_id'), findsNothing);
      expect(find.text('Recently viewed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
