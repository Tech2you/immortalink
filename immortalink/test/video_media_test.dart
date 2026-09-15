import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/utils/media_upload_policy.dart';
import 'package:immortalink/utils/vault_media_upload.dart';
import 'package:immortalink/utils/video_preview_source.dart';
import 'package:immortalink/widgets/vault_media.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlatform extends VideoPlayerPlatform {
  int creates = 0;
  int plays = 0;
  int pauses = 0;
  int disposals = 0;
  double volume = 1;
  Duration position = Duration.zero;
  bool fail = false;
  final sources = <DataSource>[];
  final events = <StreamController<VideoEvent>>[];
  Future<void> close() async {
    for (final stream in events) { await stream.close(); }
  }
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    creates++;
    sources.add(options.dataSource);
    if (fail) throw StateError('unavailable');
    return creates;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final stream = StreamController<VideoEvent>.broadcast();
    events.add(stream);
    scheduleMicrotask(
      () => stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 12),
          size: const Size(1920, 1080),
        ),
      ),
    );
    return stream.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposals++;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauses++;
  }

  @override
  Future<void> setVolume(int playerId, double value) async {
    volume = value;
  }

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.green);
}

void main() {
  testWidgets('selected video can play before upload', (tester) async {
    final platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(platform.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 150, height: 150,
      child: PendingVideoPreview(bytes: Uint8List.fromList([1, 2, 3]), name: 'clip.mp4'),
    ))));
    // Temporary-file preparation uses real filesystem I/O.
    for (var i = 0; i < 20 && platform.creates == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(platform.sources.single.sourceType, DataSourceType.file);
    expect(platform.plays, 0);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(find.byType(VaultVideoScreen), findsOneWidget);
    expect(platform.sources.last.sourceType, DataSourceType.file);
    expect(platform.plays, greaterThan(0));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(tester.takeException(), null);
  });
  test('draft video uses a temporary local file and removes it afterward', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final source = await prepareVideoPreview(bytes, 'mp4');
    final file = File.fromUri(Uri.parse(source.url));
    expect(await file.readAsBytes(), bytes);
    await source.release();
    expect(await file.exists(), false);
  });
  test('oversized picker files are rejected before reading bytes', () async {
    var read = false;
    final stream = Stream<List<int>>.multi((sink) {
      read = true;
      sink.close();
    });
    await expectLater(
      readVaultMediaFiles([
        PlatformFile(
          name: 'large.mp4',
          size: MediaUploadPolicy.videoMaxBytes + 1,
          readStream: stream,
        ),
      ]),
      throwsA(isA<MediaUploadException>()),
    );
    expect(read, false);
  });
  test(
    'stream bytes cannot bypass draft limits using an incorrect declared size',
    () async {
      await expectLater(
        readVaultMediaFiles([
          PlatformFile(
            name: 'clip.mp4',
            size: 1,
            readStream: Stream.value(List.filled(20, 0)),
          ),
        ], remainingBytes: 10),
        throwsA(isA<MediaUploadException>()),
      );
    },
  );
  testWidgets(
    'media chooser explicitly offers photos and videos and can be cancelled',
    (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  cancelled = await pickVaultMedia(context) == null;
                },
                child: const Text('Add media'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add media'));
      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(cancelled, true);
    },
  );
  test(
    'video types and signed URLs are recognized without treating audio as video',
    () {
      expect(
        MediaUploadPolicy.isVideo('https://example.test/a.MOV?token=secret'),
        true,
      );
      expect(MediaUploadPolicy.isVideo('clip.mp4'), true);
      expect(MediaUploadPolicy.isVideo('clip.m4v'), true);
      expect(MediaUploadPolicy.isVideo('voice.m4a'), false);
      expect(MediaUploadPolicy.isVideo('photo.jpg?token=.mp4'), false);
      expect(
        MediaUploadPolicy.contentTypeForExtension('mov'),
        'video/quicktime',
      );
    },
  );
  test('50 MB video cap and image-only avatars remain enforced', () {
    expect(
      MediaUploadPolicy.validateBytes(
        MediaUploadKind.video,
        MediaUploadPolicy.videoMaxBytes,
        fileName: 'clip.mp4',
      ),
      null,
    );
    expect(
      MediaUploadPolicy.validateBytes(
        MediaUploadKind.video,
        MediaUploadPolicy.videoMaxBytes + 1,
        fileName: 'clip.mp4',
      ),
      contains('50 MB'),
    );
    expect(
      MediaUploadPolicy.validateBytes(
        MediaUploadKind.avatarPhoto,
        100,
        fileName: 'clip.mp4',
      ),
      isNotNull,
    );
    expect(
      MediaUploadPolicy.validateBytes(
        MediaUploadKind.photo,
        MediaUploadPolicy.photoMaxBytes + 1,
        fileName: 'photo.jpg',
      ),
      isNotNull,
    );
    expect(
      MediaUploadPolicy.validateBytes(
        MediaUploadKind.video,
        100,
        fileName: 'clip.avi',
      ),
      isNotNull,
    );
  });
  test(
    'videos keep their bytes and format instead of passing through image compression',
    () async {
      final bytes = Uint8List.fromList([
        0,
        0,
        0,
        20,
        102,
        116,
        121,
        112,
        105,
        115,
        111,
        109,
        0,
        0,
        0,
        0,
        105,
        115,
        111,
        109,
      ]);
      final result = await VaultMediaUpload.prepare(
        bytes,
        fileName: 'clip.mp4',
      );
      expect(result.bytes, same(bytes));
      expect(result.contentType, 'video/mp4');
      expect(result.extension, 'mp4');
      expect(result.optimized, false);
      await expectLater(
        VaultMediaUpload.prepare(Uint8List(20), fileName: 'fake.mp4'),
        throwsA(isA<MediaUploadException>()),
      );
    },
  );
  testWidgets(
    'video shows a paused frame and supports play, mute, background pause and disposal',
    (tester) async {
      final platform = FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(platform.close);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VaultMedia.network('https://example.test/clip.mp4'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(platform.creates, 1);
      expect(platform.plays, 0);
      expect(find.byType(FittedBox), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pumpAndSettle();
      expect(platform.creates, 2);
      expect(platform.plays, greaterThan(0));
      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(platform.volume, 0);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
      final paused = platform.pauses;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(platform.pauses, greaterThan(paused));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(VaultVideoScreen), findsNothing);
      expect(find.byType(VaultVideoScreen, skipOffstage: false), findsNothing);
      // The platform stream's cancellation completes outside the fake clock.
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      expect(platform.disposals, 1);
      expect(tester.takeException(), null);
    },
  );
}
