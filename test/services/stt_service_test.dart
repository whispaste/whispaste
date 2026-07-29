/// Unit tests for SttServerStateNotifier basics.
///
/// Scope note (Issue 03, Nachtrag 2): the pre-cutover version of this file
/// also had a "Heartbeat-based startup timeout" group (4 tests) polling a
/// stderr/health-check startup sequence against a subprocess. That polling
/// model does not exist for [WhisperEngine.load] (throws-or-succeeds, no
/// poll loop) — the group was retired, not adapted. See this issue's
/// Evidence block `remaining_risks` for the consolidated coverage-gap note.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeWhisperEngine implements WhisperEngine {
  bool _loaded = false;
  int loadCallCount = 0;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loadCallCount++;
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
  }) async => 'fake transcript';

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
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
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
      modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
  );
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SttServerStateNotifier', () {
    test('stop() puts server into stopped state immediately', () {
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      final notifier = container.read(localSttBundleProvider.notifier);
      notifier.stop();

      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
      );
    });

    test('notifyRecordingStarted pauses idle timer', () {
      final container = _makeContainer(engine: _FakeWhisperEngine());
      addTearDown(container.dispose);

      // Should not throw
      container.read(localSttBundleProvider.notifier).notifyRecordingStarted();
      container.read(localSttBundleProvider.notifier).notifyRecordingStopped();
    });

    test(
      'whisperEngineProvider override is wired into SttServerStateNotifier',
      () async {
        // Verifies that the DI seam is correctly wired: the container reads
        // the overridden WhisperEngine, not the real WhisperFfiEngine, and
        // ensureRunning() actually calls into it.

        // Force sttModelPath()/the model file to not exist so the
        // model-presence check inside _start() reliably fails into the
        // `error` state without ever calling engine.load() — proving the
        // wiring is exercised without depending on a real model file.
        paths.sttDirOverride =
            '/nonexistent-stt-dir-${DateTime.now().microsecondsSinceEpoch}';
        addTearDown(() => paths.sttDirOverride = null);

        final engine = _FakeWhisperEngine();
        final container = _makeContainer(engine: engine);
        addTearDown(container.dispose);

        // The override must be the fake, not WhisperFfiEngine.
        expect(
          container.read(whisperEngineProvider),
          isA<_FakeWhisperEngine>(),
          reason: 'whisperEngineProvider override must be active',
        );

        await container.read(settingsProvider.future);
        await container.read(localSttBundleProvider.notifier).ensureRunning();

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.error,
          reason: 'missing model file must surface as error, not a crash',
        );
        expect(
          engine.loadCallCount,
          0,
          reason: 'engine.load() must not be reached without a model file',
        );
      },
    );
  });
}
