import 'dart:async';
import 'dart:io';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/screens/record_memory_screen.dart';
import 'package:immortalink/utils/web_audio_recorder.dart';

class FakeMemoryRecorder implements WebAudioRecorder {
  bool recording = false;
  bool paused = false;
  bool denyStart = false;
  bool failStop = false;
  Completer<void>? startGate;
  int starts = 0;
  int cancels = 0;
  @override
  bool get isSupported => true;
  @override
  bool get isRecording => recording;
  @override
  Future<void> start() async {
    starts++;
    if (startGate != null) await startGate!.future;
    if (denyStart) throw StateError('Microphone permission was not granted.');
    recording = true;
    paused = false;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<RecordedAudio> stop() async {
    if (failStop) throw StateError('Could not stop recording.');
    recording = false;
    return const RecordedAudio(
      bytes: [1, 2, 3, 4],
      mimeType: 'audio/mp4',
      extension: 'm4a',
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    recording = false;
  }

  @override
  void dispose() {
    recording = false;
  }
}

class _FakeGlobalAudio extends GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

void mockPreviewAudio() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  GlobalAudioplayersPlatformInterface.instance = _FakeGlobalAudio();
  for (final channel in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers.global/events',
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
}

void main() {
  setUp(mockPreviewAudio);
  setUpAll(() async {
    const fontPath = String.fromEnvironment('LOADING_QA_FONT');
    if (fontPath.isNotEmpty) {
      final data = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(data))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  Future<void> open(
    WidgetTester tester,
    FakeMemoryRecorder recorder,
    void Function(RecordedMemoryVoice?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Start'),
              onPressed: () async => onResult(
                await Navigator.push<RecordedMemoryVoice>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordMemoryScreen(
                      recorder: recorder,
                      defaultTitle: 'Voice note 1',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('pause, resume, review and name a local take at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (size.width == 320) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final recorder = FakeMemoryRecorder();
      RecordedMemoryVoice? result;
      await open(tester, recorder, (value) => result = value);
      expect(recorder.recording, isTrue);
      await tester.scrollUntilVisible(
        find.text('Pause recording'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause recording'));
      await tester.pumpAndSettle();
      expect(recorder.paused, isTrue);
      await tester.tap(find.text('Resume recording'));
      await tester.pumpAndSettle();
      expect(recorder.paused, isFalse);
      await tester.scrollUntilVisible(
        find.text('Stop and review'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and review'));
      await tester.pumpAndSettle();
      expect(recorder.recording, isFalse);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mum\'s Sunday story');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('UI_PREVIEW_QA')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../build/ui-preview-33-qa/record-review-${size.width.toInt()}.png',
          ),
        );
      }
      expect(result, isNull);
      await tester.scrollUntilVisible(
        find.text('Use recording'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use recording'));
      await tester.pumpAndSettle();
      expect(result?.title, 'Mum\'s Sunday story');
      expect(result?.audio.bytes, [1, 2, 3, 4]);
      expect(result?.seconds, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel and system back discard recording without a result', (
    tester,
  ) async {
    final recorder = FakeMemoryRecorder();
    RecordedMemoryVoice? result;
    await open(tester, recorder, (value) => result = value);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(recorder.recording, isFalse);
    expect(recorder.cancels, 1);
    expect(result, isNull);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('permission failure can be dismissed, stop failure can retry', (
    tester,
  ) async {
    final recorder = FakeMemoryRecorder()..denyStart = true;
    await open(tester, recorder, (_) {});
    expect(find.text('Try again'), findsOneWidget);
    recorder.denyStart = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    recorder.failStop = true;
    await tester.tap(find.text('Stop and review'));
    await tester.pumpAndSettle();
    expect(find.text('Use recording'), findsNothing);
    recorder.failStop = false;
    await tester.tap(find.text('Stop and review'));
    await tester.pumpAndSettle();
    expect(find.text('Use recording'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel recording'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets(
    'late microphone permission cannot leave recording after disposal',
    (tester) async {
      final recorder = FakeMemoryRecorder()..startGate = Completer<void>();
      await open(tester, recorder, (_) {});
      await tester.pumpWidget(const SizedBox());
      recorder.startGate!.complete();
      await tester.pumpAndSettle();
      expect(recorder.recording, isFalse);
      expect(recorder.cancels, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
