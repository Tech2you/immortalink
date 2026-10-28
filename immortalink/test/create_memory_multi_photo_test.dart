import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:immortalink/screens/create_memory_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'multi_photo_picker_test.dart' show FakePhotoPicker;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List bytes;
  var writes = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          if (call.method == 'create') {
            final id = (call.arguments as Map)['playerId'];
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          }
          return 1;
        },
      );
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(Colors.teal, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        Object? body = [];
        if (request.url.path.endsWith('/token')) {
          body = {
            'access_token': 'test',
            'refresh_token': 'test',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'user-a',
              'aud': 'authenticated',
              'created_at': '2026-10-26T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.method != 'GET') {
          writes++;
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
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
    'new memory accepts 20, remaining picker slots shrink, removal frees one',
    (tester) async {
      final previous = ImagePickerPlatform.instance;
      final picker = FakePhotoPicker();
      ImagePickerPlatform.instance = picker;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        picker.files.addAll(
          List.generate(19, (i) => XFile.fromData(bytes, path: 'photo-$i.png')),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: CreateMemoryScreen(
              vaultId: 'vault',
              displayName: 'Demo Person',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add media'));
        await tester.tap(find.text('Add media'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Photos'));
        await tester.pumpAndSettle();
        expect(picker.options?.limit, 20);
        expect(find.text('19 / 20 selected'), findsOneWidget);
        picker.files
          ..clear()
          ..add(XFile.fromData(bytes, path: 'last.png'));
        await tester.ensureVisible(find.text('More media'));
        await tester.tap(find.text('More media'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Photos'));
        await tester.pumpAndSettle();
        expect(picker.singleOptions, isNotNull);
        expect(find.text('20 / 20 selected'), findsOneWidget);
        await tester.ensureVisible(find.text('More media'));
        await tester.tap(find.text('More media'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This batch has 20 items. Remove one before selecting more.',
          ),
          findsOneWidget,
        );
        expect(find.text('Photos'), findsNothing);
        await tester.ensureVisible(find.byTooltip('Remove media 1'));
        await tester.tap(find.byTooltip('Remove media 1'));
        await tester.pumpAndSettle();
        expect(find.text('19 / 20 selected'), findsOneWidget);
        expect(writes, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        ImagePickerPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
