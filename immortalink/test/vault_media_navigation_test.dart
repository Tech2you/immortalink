import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/screens/vault_home_screen.dart';
import 'package:immortalink/screens/vault_readonly_screen.dart';
import 'package:immortalink/widgets/vault_media.dart';
import 'package:immortalink/widgets/vault_media_gallery.dart';
import 'package:immortalink/widgets/vault_section_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final photos = [
    {'path': 'owner/one.jpg'},
    {'path': 'owner/two.jpg'},
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => 1,
      );
    }
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        http.Response json(Object? value) => http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        final path = request.url.path;
        if (path.endsWith('/token')) {
          return json({
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'viewer',
              'aud': 'authenticated',
              'email': 'test@example.com',
              'created_at': '2026-11-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          });
        }
        if (path.endsWith('/vaults')) {
          return json(
            request.url.queryParameters['limit'] == '1'
                ? [
                    {'id': 'vault'},
                  ]
                : {
                    'name': 'Person',
                    'display_name': 'Person',
                    'owner_id': 'viewer',
                    'family_id': null,
                  },
          );
        }
        if (path.endsWith('/read_shared_vault_media')) {
          return json({'highlights': photos});
        }
        if (path.endsWith('/vault_highlight_photos')) {
          return json(photos);
        }
        if (path.endsWith('/object/sign/vault_photos')) {
          return json([
            for (final row in photos)
              {
                'path': row['path'],
                'signedURL':
                    '/object/sign/vault_photos/${row['path']}?token=test',
              },
          ]);
        }
        if (path.contains('/object/sign/vault_photos/')) {
          return json({
            'signedURL': '${path.replaceFirst('/storage/v1', '')}?token=test',
          });
        }
        if (path.endsWith('/vault_core_voice_note')) return json(null);
        if (path.endsWith('/memories') &&
            request.url.queryParameters.containsKey('prompt_key')) {
          return json(null);
        }
        return json([]);
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final member in [false, true]) {
    testWidgets(
      '${member ? "family member" : "own"} highlights and Media open at the tapped item',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: member
                ? const VaultReadOnlyScreen(
                    vaultId: 'vault',
                    vaultName: 'Person',
                  )
                : const VaultHomeScreen(vaultId: 'vault', vaultName: 'Person'),
          ),
        );
        await tester.pumpAndSettle();
        final second = find.byWidgetPredicate(
          (widget) => widget is VaultMedia && widget.url.contains('two.jpg'),
        );
        await tester.ensureVisible(second);
        await tester.tap(second);
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
        final mediaTab = find.descendant(
          of: find.byType(VaultSectionPicker),
          matching: find.text('Media'),
        );
        await tester.ensureVisible(mediaTab);
        await tester.tap(mediaTab);
        await tester.pumpAndSettle();
        final grid = find.byKey(
          ValueKey(member ? 'member-media-1' : 'vault-media-1'),
        );
        await tester.ensureVisible(grid);
        await tester.tap(grid);
        await tester.pumpAndSettle();
        expect(find.byType(VaultMediaGallery), findsOneWidget);
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
