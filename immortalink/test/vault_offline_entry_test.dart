import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vaults_screen.dart';
import 'package:immortalink/services/connection_status.dart';
import 'package:immortalink/widgets/startup_screen.dart';
import 'package:immortalink/widgets/vault_load_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var connected = false;
  var denied = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          if (call.method == 'create') {
            final playerId = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$playerId'),
              (_) async => null,
            );
          }
          return 1;
        },
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
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
        if (denied) {
          return http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'private permission detail',
            }),
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (connected) {
          return http.Response(
            '[]',
            200,
            request: request,
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
      expect(find.byType(StartupScreen), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('supabase.co'), findsNothing);
      expect(find.textContaining('owner_id'), findsNothing);
      expect(find.text('Recently viewed'), findsOneWidget);
      expect(find.byTooltip('Try online'), findsOneWidget);
      expect(find.text('Create your vault'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Recovery must not interrupt reading offline copies. Retry is explicit.
      connected = true;
      await ConnectionStatus.instance.check();
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.byTooltip('Try online'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsNothing);
      expect(find.text('Your Vault'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);

      // A denial after an outage must not route to cached/private content.
      denied = true;
      ConnectionStatus.instance.report(http.ClientException('Previous outage'));
      await tester.pumpWidget(const MaterialApp(home: VaultsScreen()));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsNothing);
      expect(find.textContaining('private permission detail'), findsNothing);
      expect(find.byType(StartupScreen), findsNothing);
      expect(
        tester.widget<VaultLoadFailure>(find.byType(VaultLoadFailure)).error,
        isA<PostgrestException>(),
      );
      expect(find.textContaining('permission'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
