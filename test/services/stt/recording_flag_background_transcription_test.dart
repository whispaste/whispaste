/// A background transcription (automation API, file import) reports completion
/// through [SttServerStateNotifier.notifyTranscriptionCompleted]. While a
/// dictation is still busy, that must not clear the recording flag: the engine
/// call keeps its reduced-thread setting for the live recording (ticket).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

import '../../test_helpers/wav_bytes.dart';

/// Records the reduced-thread flag each engine call receives.
class _RecordingEngine implements WhisperEngine, LivePreviewEngine {
  bool _loaded = false;
  bool? lastReducedThreads;

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
  }) async {
    lastReducedThreads = reducedThreads;
    return 'fake transcript';
  }

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
  }) async => 'preview text';

  @override
  Future<void> stopLivePreview() async {}
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
  required RecordingPhase phase,
}) {
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
      recordingPhaseProvider.overrideWithValue(phase),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

Future<Directory> _createFakeSttDir() async {
  final dir = await Directory.systemTemp.createTemp('recording_flag_test_');
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

  group('capture end before the final decode', () {
    test('stopping the recording stops the live preview and the final decode '
        'gets full threads', () async {
      final engine = _RecordingEngine();
      final container = _makeContainer(
        engine: engine,
        phase: RecordingPhase.recording,
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();
      notifier.notifyRecordingStarted();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.livePreviewStream, isNotNull);

      notifier.notifyRecordingStopped();
      expect(notifier.livePreviewStream, isNull);

      await notifier.transcribeBytes(buildWavBytes());
      expect(engine.lastReducedThreads, isFalse);
    });
  });

  group('background completion during a live dictation', () {
    test('keeps the recording flag: the live preview stays and the engine '
        'still gets reduced threads', () async {
      final engine = _RecordingEngine();
      final container = _makeContainer(
        engine: engine,
        phase: RecordingPhase.recording,
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();
      notifier.notifyRecordingStarted();
      await Future<void>.delayed(Duration.zero);

      // The API or file import finishes its own transcription and releases.
      notifier.notifyTranscriptionCompleted();
      await notifier.transcribeBytes(buildWavBytes());

      expect(notifier.livePreviewStream, isNotNull);
      expect(engine.lastReducedThreads, isTrue);

      notifier.notifyRecordingStopped();
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'without a dictation the completion clears the flag as before',
      () async {
        final engine = _RecordingEngine();
        final container = _makeContainer(
          engine: engine,
          phase: RecordingPhase.idle,
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        final notifier = container.read(localSttBundleProvider.notifier);
        await notifier.ensureRunning();
        notifier.notifyRecordingStarted();
        await Future<void>.delayed(Duration.zero);

        notifier.notifyTranscriptionCompleted();
        await notifier.transcribeBytes(buildWavBytes());

        expect(engine.lastReducedThreads, isFalse);

        notifier.notifyRecordingStopped();
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('an end state (done) is not busy, so the flag is cleared', () async {
      final engine = _RecordingEngine();
      final container = _makeContainer(
        engine: engine,
        phase: RecordingPhase.done,
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();
      notifier.notifyRecordingStarted();
      await Future<void>.delayed(Duration.zero);

      notifier.notifyTranscriptionCompleted();
      await notifier.transcribeBytes(buildWavBytes());

      expect(engine.lastReducedThreads, isFalse);

      notifier.notifyRecordingStopped();
      await Future<void>.delayed(Duration.zero);
    });
  });
}
