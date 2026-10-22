import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vault_readonly_screen.dart';
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
        Object? data = [];
        if (request.url.path.endsWith('/vaults')) {
          data = {
            'id': 'vault',
            'owner_id': 'owner',
            'family_id': 'family',
            'display_name': 'QA owner',
            'name': 'QA owner',
          };
        } else if (request.url.path.endsWith('/memories')) {
          data = request.url.queryParameters['prompt_key'] == 'eq.about_me'
              ? null
              : [
                  {
                    'id': 'memory',
                    'vault_id': 'vault',
                    'prompt_text': 'QA memory',
                    'body': 'Harmless test memory',
                    'created_at': '2026-10-21T10:00:00Z',
                  },
                ];
        } else if (request.url.path.endsWith('/read_shared_vault_media')) {
          data = <String, dynamic>{};
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  for (final detail in [false, true]) {
    testWidgets(
      'shared vault ${detail ? 'detail' : 'card'} offers an item report without editing',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(
            home: VaultReadOnlyScreen(
              vaultId: 'vault',
              vaultName: 'QA owner',
              familyId: 'family',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Harmless test memory'));
        await tester.pumpAndSettle();
        if (detail) {
          await tester.tap(find.text('Harmless test memory'));
          await tester.pumpAndSettle();
        }
        final menu = detail
            ? find.descendant(
                of: find.byType(Dialog),
                matching: find.byTooltip('Memory options'),
              )
            : find.byTooltip('Memory options');
        expect(menu, findsOneWidget);
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Report memory or media'), findsOneWidget);
        expect(find.text('Edit memory'), findsNothing);
        expect(find.text('Delete memory'), findsNothing);
        await tester.tap(find.text('Report memory or media'));
        await tester.pumpAndSettle();
        expect(find.text('Report content'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
