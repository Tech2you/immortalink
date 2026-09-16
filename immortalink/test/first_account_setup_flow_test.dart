import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:immortalink/screens/first_account_setup_screen.dart';
import 'package:immortalink/services/first_account_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic>? vault;
  var metadata = <String, dynamic>{};
  var inserts = 0;
  var failProgress = false;
  Map<String, dynamic> user() => {
    'id': 'new-user',
    'aud': 'authenticated',
    'email': 'test@example.com',
    'created_at': '2026-09-15T00:00:00Z',
    'app_metadata': {},
    'user_metadata': metadata,
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        Object? body;
        if (request.url.path.endsWith('/token')) {
          body = {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': user(),
          };
        } else if (request.url.path.endsWith('/user')) {
          if (request.method == 'PUT') {
            if (failProgress) {
              return http.Response(
                '{"message":"Test save failure"}',
                400,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            metadata.addAll(
              Map<String, dynamic>.from(jsonDecode(request.body)['data']),
            );
          }
          body = user();
        } else if (request.url.path.endsWith('/vaults')) {
          if (request.method == 'POST') {
            inserts++;
            vault = {
              'id': 'vault',
              ...Map<String, dynamic>.from(jsonDecode(request.body)),
            };
          } else if (request.method == 'PATCH') {
            vault!.addAll(Map<String, dynamic>.from(jsonDecode(request.body)));
          }
          body = request.method == 'GET'
              ? (vault == null ? <Object>[] : [vault])
              : vault;
        } else {
          body = <Object>[];
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() async {
    vault = null;
    inserts = 0;
    failProgress = false;
    metadata = {firstAccountSetupKey: 'pending'};
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'unused-test-password',
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FirstAccountSetupScreen(),
                ),
              ),
              child: const Text('Open setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
  }

  testWidgets('back preserves vault, optional skips finish once', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Frank');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your profile photo'),
      findsOneWidget,
      reason:
          'inserts=$inserts metadata=$metadata vault=$vault '
          '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
    );
    expect(inserts, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Frank',
    );
    await tester.enterText(find.byType(TextField), 'Frank Smith');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(inserts, 1);
    expect(vault!['name'], 'Frank Smith');
    expect(vault!['display_name'], 'Frank Smith');
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Your first memory'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Your family tree'), findsOneWidget);
    await tester.tap(find.text('Go to my vault'));
    await tester.pumpAndSettle();
    expect(find.text('Open setup'), findsOneWidget);
    expect(needsFirstAccountSetup(metadata), false);
    expect(tester.takeException(), null);
  });

  testWidgets('skip setup creates no vault and is persisted', (tester) async {
    await open(tester);
    await tester.tap(find.text('Skip setup'));
    await tester.pumpAndSettle();
    expect(inserts, 0);
    expect(needsFirstAccountSetup(metadata), false);
    expect(find.text('Open setup'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('retry after progress failure does not create another vault', (
    tester,
  ) async {
    await open(tester);
    failProgress = true;
    await tester.enterText(find.byType(TextField), 'Frank');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(inserts, 1);
    expect(needsFirstAccountSetup(metadata), true);
    expect(find.textContaining('Could not save this step'), findsOneWidget);
    failProgress = false;
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(inserts, 1);
    expect(find.text('Your profile photo'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('new session resumes saved step and existing vault', (
    tester,
  ) async {
    vault = {'id': 'vault', 'name': 'Frank', 'display_name': 'Frank'};
    metadata[firstAccountSetupStepKey] = 2;
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'unused-test-password',
    );
    await open(tester);
    expect(find.text('Your first memory'), findsOneWidget);
    expect(inserts, 0);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Your profile photo'), findsOneWidget);
    expect(metadata[firstAccountSetupStepKey], 1);
    expect(tester.takeException(), null);
  });
}
