import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immortalink/services/memory_media_batch.dart';
import 'package:immortalink/utils/media_upload_policy.dart';
import 'package:immortalink/widgets/memory_media_upload_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

late Uint8List photoBytes;

class BatchServer {
  late final SupabaseClient client = SupabaseClient(
    'http://localhost:54321',
    'test',
    httpClient: MockClient(handle),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final uploads = <String>[];
  final rows = <String, Map<String, dynamic>>{};
  final uploadHeaders = <Map<String, String>>[];
  final objects = <String>{};
  int insertCalls = 0;
  int? failIndex;
  bool loseUploadResponse = false;
  bool loseInsertResponse = false;
  bool quota = false;
  bool deny = false;
  Completer<void>? wait;
  int active = 0;
  int maxActive = 0;

  Future<http.Response> handle(http.Request request) async {
    http.Response json(Object? value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    if (request.url.path.endsWith('/token')) {
      return json({
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
      });
    }
    if (request.url.path.endsWith('/logout')) return json({});
    if (request.url.path.startsWith('/storage/v1/object/')) {
      final path = request.url.path.split('/').skip(5).join('/');
      uploads.add(path);
      uploadHeaders.add(request.headers);
      active++;
      if (active > maxActive) maxActive = active;
      try {
        if (wait != null) await wait!.future;
        if (objects.contains(path)) {
          return json({
            'statusCode': '409',
            'error': 'Duplicate',
            'message': 'Already exists',
          }, 409);
        }
        if (path.endsWith('_$failIndex.png')) {
          throw http.ClientException('Connection interrupted');
        }
        objects.add(path);
        if (loseUploadResponse) {
          loseUploadResponse = false;
          throw http.ClientException('Response lost');
        }
        return json({'Key': path});
      } finally {
        active--;
      }
    }
    if (request.url.path.startsWith('/rest/v1/')) {
      if (request.method == 'GET') {
        final path = request.url.queryParameters['path']?.substring(3);
        return json(
          rows.containsKey(path)
              ? [
                  {'id': path},
                ]
              : [],
        );
      }
      insertCalls++;
      if (deny) return json({'code': '42501', 'message': 'Denied'}, 403);
      if (quota) {
        return json({
          'code': 'P0001',
          'message': 'ERR_EVERROOT_STORAGE_LIMIT',
        }, 400);
      }
      final row = jsonDecode(request.body) as Map<String, dynamic>;
      rows[row['path'] as String] = row;
      if (loseInsertResponse) {
        loseInsertResponse = false;
        throw http.ClientException('Insert response lost');
      }
      return http.Response('', 201, request: request);
    }
    throw StateError('Unexpected request: ${request.method} ${request.url}');
  }

  Future<void> signIn() => client.auth.signInWithPassword(
    email: 'test@example.com',
    password: 'test-only',
  );
  MemoryMediaBatch batch(int count, {bool legacy = false}) => MemoryMediaBatch(
    client: client,
    target: legacy
        ? MemoryMediaTarget.legacy(
            familyId: 'family',
            memberId: 'member',
            memoryId: 'memory',
          )
        : MemoryMediaTarget.personal(vaultId: 'vault', memoryId: 'memory'),
    media: List.generate(
      count,
      (i) => PendingMemoryMedia(
        name: 'photo-$i.png',
        bytes: photoBytes,
        extension: 'png',
        contentType: 'image/png',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const imagePath = String.fromEnvironment('PHOTO_QA_IMAGE');
    if (imagePath.isNotEmpty) {
      photoBytes = await File(imagePath).readAsBytes();
    } else {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xFF23A5A0), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 4);
      photoBytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
    }
    const fontPath = String.fromEnvironment('PHOTO_QA_FONT');
    if (fontPath.isNotEmpty) {
      final data = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final name in ['Roboto', 'Ahem']) {
        await (FontLoader(name)..addFont(Future.value(data))).load();
      }
    }
    const iconPath = String.fromEnvironment('PHOTO_QA_ICONS');
    if (iconPath.isNotEmpty) {
      final data = ByteData.sublistView(await File(iconPath).readAsBytes());
      await (FontLoader('MaterialIcons')..addFont(Future.value(data))).load();
    }
  });
  late BatchServer server;
  setUp(() async {
    server = BatchServer();
    await server.signIn();
  });
  tearDown(() => server.client.dispose());

  test('20 photos upload sequentially without overwrites', () async {
    final batch = server.batch(20);
    server.wait = Completer<void>();
    final work = batch.upload();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.uploads, hasLength(1));
    server.wait!.complete();
    await work;
    expect(batch.savedCount, 20);
    expect(batch.complete, isTrue);
    expect(server.maxActive, 1);
    expect(server.rows, hasLength(20));
    expect(server.uploads.toSet(), hasLength(20));
    expect(
      server.uploads.every(
        (p) => p.startsWith('user-a/vault/memories/memory/'),
      ),
      isTrue,
    );
    expect(server.uploadHeaders.every((h) => h['x-upsert'] == 'false'), isTrue);
    await batch.upload();
    expect(server.uploads, hasLength(20));
    await server.batch(20).upload();
    expect(
      server.rows,
      hasLength(40),
      reason: '20 is a batch cap, not memory lifetime cap',
    );
  });

  test('invalid count and oversize never reach the network', () {
    expect(() => server.batch(21), throwsA(isA<MediaUploadException>()));
    expect(() => server.batch(0), throwsA(isA<MediaUploadException>()));
    expect(
      () => MemoryMediaBatch(
        client: server.client,
        target: MemoryMediaTarget.personal(
          vaultId: 'vault',
          memoryId: 'memory',
        ),
        media: [
          PendingMemoryMedia(
            name: 'large.png',
            extension: 'png',
            contentType: 'image/png',
            bytes: Uint8List(MediaUploadPolicy.photoMaxBytes + 1),
          ),
        ],
      ),
      throwsA(isA<MediaUploadException>()),
    );
    expect(server.uploads, isEmpty);
  });

  test('partial upload retries missing items only with stable paths', () async {
    final batch = server.batch(3);
    server.failIndex = 1;
    await batch.upload();
    expect(batch.savedCount, 1);
    expect(server.uploads, hasLength(2));
    final failedPath = server.uploads.last;
    server.failIndex = null;
    await batch.upload();
    expect(batch.complete, isTrue);
    expect(server.uploads, hasLength(4));
    expect(server.uploads[2], failedPath);
    expect(server.insertCalls, 3);
  });

  test(
    'lost storage response recovers only its own existing random path',
    () async {
      final batch = server.batch(2);
      server.loseUploadResponse = true;
      await batch.upload();
      expect(batch.savedCount, 0);
      await batch.upload();
      expect(batch.savedCount, 2);
      expect(server.objects, hasLength(2));
      expect(server.uploads[0], server.uploads[1]);
      expect(server.insertCalls, 2);
    },
  );

  test('lost insert response is reconciled instead of duplicated', () async {
    final batch = server.batch(2);
    server.loseInsertResponse = true;
    await batch.upload();
    expect(batch.savedCount, 0);
    expect(server.rows, hasLength(1));
    await batch.upload();
    expect(batch.savedCount, 2);
    expect(server.uploads, hasLength(2));
    expect(server.insertCalls, 2);
  });

  for (final denial in ['quota', 'permission']) {
    test(
      '$denial stops further uploads; retry reuses uploaded object',
      () async {
        final batch = server.batch(3);
        server.quota = denial == 'quota';
        server.deny = denial == 'permission';
        await batch.upload();
        expect(batch.savedCount, 0);
        expect(server.uploads, hasLength(1));
        server.quota = false;
        server.deny = false;
        await batch.upload();
        expect(batch.savedCount, 3);
        expect(server.uploads, hasLength(3));
      },
    );
  }

  test('signout during upload stops linking and remaining photos', () async {
    final batch = server.batch(3);
    server.wait = Completer<void>();
    final work = batch.upload();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await server.client.auth.signOut();
    server.wait!.complete();
    await work;
    expect(server.uploads, hasLength(1));
    expect(server.rows, isEmpty);
    expect(batch.sameAccount, isFalse);
    await batch.upload();
    expect(server.uploads, hasLength(1));
  });

  test('pause finishes current item; resume skips completed ones', () async {
    final batch = server.batch(3);
    server.wait = Completer<void>();
    final work = batch.upload();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    batch.pause();
    server.wait!.complete();
    await work;
    expect(batch.savedCount, 1);
    await batch.upload();
    expect(batch.savedCount, 3);
    expect(server.uploads, hasLength(3));
  });

  test('legacy uploads retain family/member scope', () async {
    final batch = server.batch(2, legacy: true);
    await batch.upload();
    expect(batch.complete, isTrue);
    expect(
      server.rows.values.every(
        (r) =>
            r['family_id'] == 'family' &&
            r['legacy_member_id'] == 'member' &&
            r['legacy_memory_id'] == 'memory',
      ),
      isTrue,
    );
    expect(
      server.uploads.every(
        (p) => p.startsWith('user-a/family/legacy/member/memories/memory/'),
      ),
      isTrue,
    );
  });

  for (final variant in [
    (name: 'phone', size: const Size(390, 844), scale: 1.0),
    (name: 'large-text', size: const Size(320, 844), scale: 1.6),
    (name: 'tablet', size: const Size(834, 1194), scale: 1.0),
  ]) {
    testWidgets('preview count, removal and stable grid: ${variant.name}', (
      tester,
    ) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final batch = server.batch(20);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(variant.scale)),
            child: child!,
          ),
          home: MemoryMediaUploadScreen(batch: batch),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(MemoryImage(photoBytes), width: 360),
          tester.element(find.byType(MemoryMediaUploadScreen)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('20 / 20 selected'), findsOneWidget);
      final before = tester.getSize(find.byType(GridView));
      await tester.tap(find.byTooltip('Remove media 1'));
      await tester.pumpAndSettle();
      expect(find.text('19 / 20 selected'), findsOneWidget);
      expect(tester.getSize(find.byType(GridView)), before);
      expect(server.uploads, isEmpty);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('PHOTO_VISUAL_QA')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/photo-32-qa/preview-${variant.name}.png'),
        );
      }
    });
  }

  testWidgets('retry UI keeps successes and hides media after signout', (
    tester,
  ) async {
    final batch = server.batch(3);
    server.failIndex = 1;
    await tester.pumpWidget(
      MaterialApp(home: MemoryMediaUploadScreen(batch: batch)),
    );
    await tester.tap(find.text('Add 3 items'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 saved'), findsOneWidget);
    expect(find.text('Retry remaining media'), findsOneWidget);
    expect(find.byTooltip('Remove media 1'), findsNothing);
    server.failIndex = null;
    await tester.tap(find.text('Retry remaining media'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 saved'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(server.insertCalls, 3);
    await server.client.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Account changed. Reopen this memory.'), findsOneWidget);
  });

  testWidgets('closing preview does not upload or alter the memory', (
    tester,
  ) async {
    final batch = server.batch(3);
    int? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showMemoryMediaUpload(context, batch: batch);
            },
            child: const Text('Open preview'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(saved, 0);
    expect(server.uploads, isEmpty);
    expect(server.rows, isEmpty);
  });
}
