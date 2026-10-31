/// Tests for the live-transcript-DURING-recording preview lifecycle wired
/// into [SttServerStateNotifier] (live-transcript-streaming ticket):
///
/// - Performance guarantee: with `overlayShowLiveTranscript == false`, the
///   notifier never touches [LivePreviewEngine] at all (no state init, no
///   decode timer).
/// - Cleanup guarantee: whichever recording-ending path fires
///   (`notifyRecordingStopped`, `stop()`, provider disposal), the engine's
///   `stopLivePreview()` (which frees the native `whisper_state`) is called
///   reliably — no leaks.
///
/// Uses a self-contained fake [WhisperEngine] that also implements
/// [LivePreviewEngine], mirroring `stt_server_state_notifier_test.dart`'s
/// `_FakeWhisperEngine` (kept separate per that file's
/// self-contained-fakes convention).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

class _FakeLivePreviewEngine implements WhisperEngine, LivePreviewEngine {
  bool _loaded = false;

  int startLivePreviewCalls = 0;
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
  Future<void> startLivePreview() async {
    startLivePreviewCalls++;
  }

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

ProviderContainer _makeContainer({
  required WhisperEngine engine,
  required AppSettings settings,
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

/// Creates a temporary directory with a fake GGML model file large enough to
/// pass the minimum-size guard (>10 MB), mirroring
/// `stt_server_state_notifier_test.dart`'s identical helper (kept duplicated
/// per that file's self-contained-fakes convention) — needed by tests that
/// call `ensureRunning()`/`_start()`, which stats a real model file on disk.
Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('live_preview_test_');

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
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

  group('Live-preview performance guarantee (overlayShowLiveTranscript off)', () {
    test(
      'notifyRecordingStarted() never touches LivePreviewEngine when the setting is off',
      () async {
        final engine = _FakeLivePreviewEngine();
        final container = _makeContainer(
          engine: engine,
          settings: AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            overlayShowLiveTranscript: false,
          ),
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final notifier = container.read(localSttBundleProvider.notifier);
        notifier.notifyRecordingStarted();
        // Give any accidental async start a chance to run before asserting.
        await Future<void>.delayed(Duration.zero);

        expect(engine.startLivePreviewCalls, 0);
        expect(notifier.livePreviewStream, isNull);

        notifier.notifyRecordingStopped();
        await Future<void>.delayed(Duration.zero);
        expect(engine.stopLivePreviewCalls, 0);
      },
    );

    test(
      'notifyRecordingStarted() starts the preview when the setting is on and the engine is ready',
      () async {
        final engine = _FakeLivePreviewEngine();
        final container = _makeContainer(
          engine: engine,
          settings: AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            overlayShowLiveTranscript: true,
          ),
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();

        notifier.notifyRecordingStarted();
        await Future<void>.delayed(Duration.zero);

        expect(engine.startLivePreviewCalls, 1);
        expect(notifier.livePreviewStream, isNotNull);

        notifier.notifyRecordingStopped();
        await Future<void>.delayed(Duration.zero);
        expect(engine.stopLivePreviewCalls, 1);
      },
    );
  });

  group(
    'Live-preview cleanup guarantee (whisper_free_state via stopLivePreview)',
    () {
      test(
        'notifyRecordingStopped() calls stopLivePreview exactly once',
        () async {
          final engine = _FakeLivePreviewEngine();
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              overlayShowLiveTranscript: true,
            ),
          );
          addTearDown(container.dispose);
          await container.read(settingsProvider.future);

          final notifier = container.read(localSttBundleProvider.notifier);
          await notifier.ensureRunning();
          notifier.notifyRecordingStarted();
          await Future<void>.delayed(Duration.zero);

          notifier.notifyRecordingStopped();
          await Future<void>.delayed(Duration.zero);

          expect(engine.stopLivePreviewCalls, 1);
        },
      );

      test(
        'stop() (abort/model-switch path) also calls stopLivePreview',
        () async {
          final engine = _FakeLivePreviewEngine();
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              overlayShowLiveTranscript: true,
            ),
          );
          addTearDown(container.dispose);
          await container.read(settingsProvider.future);

          final notifier = container.read(localSttBundleProvider.notifier);
          await notifier.ensureRunning();
          notifier.notifyRecordingStarted();
          await Future<void>.delayed(Duration.zero);

          await notifier.stop();

          expect(engine.stopLivePreviewCalls, 1);
        },
      );

      test(
        'provider disposal calls stopLivePreview even without an explicit stop()',
        () async {
          final engine = _FakeLivePreviewEngine();
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              overlayShowLiveTranscript: true,
            ),
          );
          await container.read(settingsProvider.future);

          final notifier = container.read(localSttBundleProvider.notifier);
          await notifier.ensureRunning();
          notifier.notifyRecordingStarted();
          await Future<void>.delayed(Duration.zero);

          container.dispose();

          expect(engine.stopLivePreviewCalls, 1);
        },
      );

      test(
        'stopLivePreview is a safe no-op call count of zero when preview was never started',
        () async {
          final engine = _FakeLivePreviewEngine();
          final container = _makeContainer(
            engine: engine,
            settings: AppSettings.defaults.copyWith(
              sttModel: 'whisper-small',
              overlayShowLiveTranscript: false,
            ),
          );
          addTearDown(container.dispose);
          await container.read(settingsProvider.future);

          final notifier = container.read(localSttBundleProvider.notifier);
          notifier.notifyRecordingStopped();
          await Future<void>.delayed(Duration.zero);

          expect(engine.stopLivePreviewCalls, 0);
        },
      );
    },
  );
}
