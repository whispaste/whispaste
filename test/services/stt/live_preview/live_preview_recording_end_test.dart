/// Regression test (N2, P1): the during-recording live preview must stop as
/// soon as the recording leaves the recording phase, whatever ends it.
///
/// Before the fix, only `notifyRecordingStopped` (cancel and error paths) tore
/// the previewer down. A successful dictation, an empty transcript, the Smart
/// Mode fallback and a capture abort never reached it, so the trigger timer kept
/// re-decoding the frozen trailing window every couple of seconds after the
/// text had already been delivered.
///
/// The phase is driven through the real [RecordingNotifier] (no phase override),
/// so the same transitions the orchestrator performs reach the notifier.
///
/// The preview's trigger timer runs on simulated time (fakeAsync), so proving
/// that it no longer ticks takes no real waiting.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

typedef _Harness = ({
  ProviderContainer container,
  _CountingLivePreviewEngine engine,
  FakeAsync time,
});

class _CountingLivePreviewEngine implements WhisperEngine, LivePreviewEngine {
  bool _loaded = false;

  int decodeLivePreviewCalls = 0;
  int stopLivePreviewCalls = 0;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async => 'fake transcript';

  @override
  Future<void> unload() async {
    _loaded = false;
  }

  @override
  Future<void> startLivePreview() async {}

  @override
  Future<String> decodeLivePreview(
    Float32List samples, {
    String? language,
    String? prompt,
  }) async {
    decodeLivePreviewCalls++;
    return 'preview text';
  }

  @override
  Future<void> stopLivePreview() async {
    stopLivePreviewCalls++;
  }
}

class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _settings;
  _FakeSettingsNotifier(this._settings);

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

ProviderContainer _makeContainer(WhisperEngine engine) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            overlayShowLiveTranscript: true,
          ),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('live_preview_end_test_');
  final modelFilename =
      findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  paths.sttDirOverride = dir.path;
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await _createFakeSttDir();
  });

  tearDown(() async {
    paths.sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  /// Starts a real recording with the preview running and some audio buffered,
  /// so a trigger tick has something to decode.
  /// The preview starts on [time], so its trigger timer is simulated.
  Future<_Harness> startRecordingWithPreview() async {
    final engine = _CountingLivePreviewEngine();
    final container = _makeContainer(engine);
    await container.read(settingsProvider.future);

    final notifier = container.read(localSttBundleProvider.notifier);
    await notifier.ensureRunning();

    container.read(recordingProvider.notifier).startRecording();
    final time = FakeAsync();
    time.run((_) => notifier.notifyRecordingStarted());
    time.elapse(Duration.zero);
    expect(notifier.livePreviewStream, isNotNull, reason: 'preview must run');

    // One second of 16-bit mono silence at 16 kHz.
    time.run((_) => notifier.feedLivePreviewPcm(Uint8List(32000)));
    return (container: container, engine: engine, time: time);
  }

  /// Once the recording has left the recording phase, the preview must be torn
  /// down: no stream left, the native state freed exactly once, and no further
  /// decodes while the app is no longer dictating.
  void expectPreviewStoppedAfter(
    _Harness h,
    void Function(RecordingNotifier recording) transition,
  ) {
    final (:container, :engine, :time) = h;
    final notifier = container.read(localSttBundleProvider.notifier);
    time.run((_) => transition(container.read(recordingProvider.notifier)));
    time.elapse(Duration.zero);

    expect(
      notifier.livePreviewStream,
      isNull,
      reason: 'preview must be torn down when the recording ends',
    );
    expect(engine.stopLivePreviewCalls, 1);

    final decodesAtEnd = engine.decodeLivePreviewCalls;
    // Longer than the 2 s trigger interval: a live timer would tick here.
    time.elapse(const Duration(milliseconds: 2500));
    expect(
      engine.decodeLivePreviewCalls,
      decodesAtEnd,
      reason: 'no preview decodes may run after the recording has ended',
    );

    // A later notifyRecordingStopped() must not free the native state again.
    time.run((_) => notifier.notifyRecordingStopped());
    time.elapse(Duration.zero);
    expect(engine.stopLivePreviewCalls, 1, reason: 'teardown is idempotent');
  }

  group('live preview ends when the recording leaves the recording phase', () {
    test('successful dictation (recording -> transcribing -> done)', () async {
      final h = await startRecordingWithPreview();
      addTearDown(h.container.dispose);

      expectPreviewStoppedAfter(h, (recording) {
        recording.stopRecording();
        recording.completeTranscription('hello world');
      });
    });

    test(
      'empty transcript or error (recording -> transcribing -> error)',
      () async {
        final h = await startRecordingWithPreview();
        addTearDown(h.container.dispose);

        expectPreviewStoppedAfter(h, (recording) {
          recording.stopRecording();
          recording.fail('transcription_empty');
        });
      },
    );

    test(
      'Smart Mode fallback (recording -> transcribing -> refining)',
      () async {
        final h = await startRecordingWithPreview();
        addTearDown(h.container.dispose);

        expectPreviewStoppedAfter(h, (recording) {
          recording.stopRecording();
          recording.startRefining('hello world');
        });
      },
    );

    test('cancel (recording -> idle)', () async {
      final h = await startRecordingWithPreview();
      addTearDown(h.container.dispose);

      expectPreviewStoppedAfter(h, (recording) {
        recording.reset();
      });
    });
  });
}
