import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// HTTP is provided by supabase_flutter; used to isolate the database in tests.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:immortalink/screens/legacy_vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'multi_photo_picker_test.dart' show FakePhotoPicker;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> row;
  Map<String, dynamic>? saved;
  var loads = 0;
  List<Map<String, dynamic>> memories = [];

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
        if (request.url.path.endsWith('/legacy_memories')) {
          return http.Response(
            jsonEncode(memories),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/legacy_family_members')) {
          if (request.method == 'GET') loads++;
          if (request.method == 'PATCH') {
            saved = jsonDecode(request.body) as Map<String, dynamic>;
            row.addAll(saved!);
            return http.Response('', 204, request: request);
          }
          return http.Response(
            jsonEncode(row),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  setUp(() {
    row = {
      'id': 'relative',
      'family_id': 'family',
      'name': 'Child not added yet',
      'display_name': 'Child not added yet',
    };
    saved = null;
    memories = [];
  });

  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> open(WidgetTester tester, {bool edit = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LegacyVaultScreen(
          legacyMemberId: 'relative',
          familyId: 'family',
          editProfile: edit,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Edit profile'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join('\n'),
    );
  }

  testWidgets('pulling the vault down refreshes its contents', (tester) async {
    await open(tester);
    final before = loads;
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();
    expect(loads, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new legacy memory offers camera and cancellation keeps the editor',
    (tester) async {
      final previous = ImagePickerPlatform.instance;
      final picker = FakePhotoPicker();
      ImagePickerPlatform.instance = picker;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await open(tester);
        await tester.ensureVisible(find.text('Write memory'));
        await tester.tap(find.text('Write memory'));
        await tester.pumpAndSettle();
        expect(find.text('New memory'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'Take photo'),
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Take photo'));
        await tester.pumpAndSettle();
        expect(picker.captures, 1);
        expect(find.text('New memory'), findsOneWidget);
        expect(saved, isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        ImagePickerPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'saved legacy memory editor and its media picker exclude camera',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        memories = [
          {
            'id': 'saved-memory',
            'body': 'Existing story',
            'prompt_text': 'A day at the beach',
            'life_stage': 'mid',
          },
        ];
        await open(tester);
        await tester.ensureVisible(find.byTooltip('Memory options'));
        await tester.tap(find.byTooltip('Memory options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit memory'));
        await tester.pumpAndSettle();
        final editor = find.byType(Dialog);
        expect(
          find.descendant(of: editor, matching: find.text('Take photo')),
          findsNothing,
        );
        final addMedia = find.descendant(
          of: editor,
          matching: find.text('Add media'),
        );
        expect(addMedia, findsOneWidget);
        await tester.ensureVisible(addMedia);
        await tester.tap(addMedia);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Photos'), findsOneWidget);
        expect(find.text('Videos'), findsOneWidget);
        expect(find.text('Take photo'), findsNothing);
        expect(saved, isNull);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Edit profile reveals the name field and saves both names', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Name *');
    expect(field.hitTestable(), findsOneWidget);
    await tester.enterText(field, 'dirk');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Save').first);
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(saved?['name'], 'dirk');
    expect(saved?['display_name'], 'dirk');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tree Edit profile opens directly at the editable name', (
    tester,
  ) async {
    await open(tester, edit: true);
    expect(
      find.widgetWithText(TextField, 'Name *').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
