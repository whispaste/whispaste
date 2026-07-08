/// Unit tests for SttServerStateNotifier (new modular notifier).
///
/// Uses [whisperEngineProvider] as the DI seam — the notifier drives the
/// in-process [WhisperEngine] instead of a `whisper-server` subprocess +
/// HTTP transport (Issue 03 cutover). Provider imports come from
/// [stt_bundle.dart].
///
/// Scope note (Issue 03, Nachtrag 2): the pre-cutover version of this file
/// also covered GPU-DLL-gate/`ServerBinaryRecovery`/heartbeat-stall/exit-code
/// fallback behavior driven by subprocess-spawn/crash mechanics that have no
/// equivalent against an in-process engine. Those tests were retired here
/// (not adapted) — see this issue's Evidence block `remaining_risks` for the
/// consolidated coverage-gap note, closed by Issue 04 (backend selection) and
/// Issue 05 (resilience).
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

// ---------------------------------------------------------------------------
// Fake helpers (self-contained; do not import from other test files)
// ---------------------------------------------------------------------------

class _FakeWhisperEngine implements WhisperEngine {
  bool _loaded = false;
  String? lastModelPath;
  int loadCallCount = 0;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath}) async {
    loadCallCount++;
    lastModelPath = modelPath;
    _loaded = true;
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    return 'fake transcript';
  }

  @override
  Future<void> unload() async {
    _loaded = false;
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
  int downloadModelCalls = 0;
  String? lastDownloadedModelId;

  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});

  @override
  Future<void> downloadModel(String modelId) async {
    downloadModelCalls += 1;
    lastDownloadedModelId = modelId;
    state = ModelDownloadState(downloadedModels: {modelId});
  }
}

ProviderContainer _makeContainer({
  required WhisperEngine engine,
  AppSettings? settings,
}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          settings ?? AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
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

/// Creates a temporary directory with a fake GGML model file large enough to
/// pass the minimum-size guard (>10 MB). Returns the temp dir; caller is
/// responsible for cleanup. No whisper-server binary is written — the engine
/// seam has no subprocess to spawn.
Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('stt_notifier_test_');

  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));

  paths.sttDirOverride = dir.path;
  return dir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SttServerStateNotifier — basic lifecycle', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('initial state is stopped', () {
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.stopped);
    });

    test('ensureRunning() transitions to ready on healthy engine', () async {
      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      final status = container.read(localSttBundleProvider);
      expect(status.serverState, SttServerState.ready);
      expect(engine.loadCallCount, 1);
      expect(engine.lastModelPath, isNotNull);
    });

    test('stop() transitions to stopped', () async {
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      final notifier = container.read(localSttBundleProvider.notifier);
      await notifier.ensureRunning();
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.ready,
      );

      notifier.stop();
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
      );
    });
  });

  group('SttServerStateNotifier — notify methods', () {
    test(
      'notifyRecordingStarted/Stopped do not throw when server is stopped',
      () {
        final container = _makeContainer(engine: _FakeWhisperEngine());
        addTearDown(container.dispose);

        final notifier = container.read(localSttBundleProvider.notifier);
        notifier.notifyRecordingStarted();
        notifier.notifyRecordingStopped();
        notifier.notifyTranscriptionCompleted();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Pure decision function — isSttModelFileTooSmall (AC3)
  // ---------------------------------------------------------------------------

  group('isSttModelFileTooSmall — pure decision function', () {
    // Table-driven: each entry is (fileSizeBytes, expected)
    const cases = <(int, bool)>[
      (0, true), // empty file
      (1024, true), // 1 KB — clearly truncated
      (9 * 1024 * 1024, true), // 9 MiB — just below threshold
      (10 * 1024 * 1024 - 1, true), // one byte below threshold
      (10 * 1024 * 1024, false), // exactly at threshold — not corrupt
      (11 * 1024 * 1024, false), // 11 MiB — healthy model
      (200 * 1024 * 1024, false), // 200 MiB — large model, healthy
    ];

    for (final (size, expected) in cases) {
      test('${size ~/ 1024} KB → isTooSmall=$expected', () {
        expect(isSttModelFileTooSmall(size), equals(expected));
      });
    }

    test('custom minModelBytes threshold is respected', () {
      // 5 MiB min — a 6 MiB file should pass.
      expect(
        isSttModelFileTooSmall(6 * 1024 * 1024, minModelBytes: 5 * 1024 * 1024),
        isFalse,
      );
      // Same 6 MiB file fails against the default 10 MiB threshold.
      expect(isSttModelFileTooSmall(6 * 1024 * 1024), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Corrupt/too-small model → silent re-download (AC1, AC2)
  // ---------------------------------------------------------------------------

  group('SttServerStateNotifier — corrupt model auto-reload', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createFakeSttDir();
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('too-small model file triggers silent re-download via '
        'modelDownloadProvider (AC1, AC2)', () async {
      // Overwrite the 11 MiB model that _createFakeSttDir wrote with a
      // truncated 1 KiB stub — simulating an interrupted download.
      final modelFilename =
          findSttModel('whisper-small')?.filename ?? 'ggml-small-q5_1.bin';
      final modelFile = File('${tempDir.path}/$modelFilename');
      await modelFile.writeAsBytes(Uint8List(1024)); // 1 KB — below 10 MiB

      final engine = _FakeWhisperEngine();
      final container = _makeContainer(engine: engine);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);
      await container.read(localSttBundleProvider.notifier).ensureRunning();

      // The notifier must park in `stopped` (mirroring the SHA-mismatch
      // self-heal path) and hand off to modelDownloadProvider.downloadModel.
      final status = container.read(localSttBundleProvider);
      expect(
        status.serverState,
        SttServerState.stopped,
        reason:
            'corrupt model path must park in stopped, not error '
            '(consistent with SHA-mismatch self-heal — AC2)',
      );

      final download =
          container.read(modelDownloadProvider.notifier)
              as _FakeModelDownloadNotifier;
      expect(
        download.downloadModelCalls,
        1,
        reason: 'silent re-download must be triggered exactly once (AC1)',
      );
      expect(
        download.lastDownloadedModelId,
        'whisper-small',
        reason: 're-download must request the active model id',
      );
      // The engine must NOT have been loaded for a corrupt model.
      expect(
        engine.loadCallCount,
        0,
        reason: 'no engine load must be attempted for a corrupt model file',
      );
    });

    test(
      'healthy 11 MiB model file does NOT trigger re-download (regression guard)',
      () async {
        // _createFakeSttDir already writes an 11 MiB file — no override needed.
        final container = _makeContainer(engine: _FakeWhisperEngine());
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        final download =
            container.read(modelDownloadProvider.notifier)
                as _FakeModelDownloadNotifier;
        expect(
          download.downloadModelCalls,
          0,
          reason: 'a healthy model must never trigger a silent re-download',
        );
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.ready,
        );
      },
    );
  });
}
