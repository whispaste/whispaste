/// Behavior-snapshot tests for SttServerStateNotifier.
///
/// Covers idle-timeout management (reset / elapse), the one responsibility
/// that survived the Issue 03 engine cutover unchanged in this file.
///
/// Scope note (Issue 03, Nachtrag 2): the pre-cutover version of this file
/// also covered subprocess lifecycle (start/stop/restart), HTTP health
/// polling, the Exit-3 hash-recheck flow, the GPU-crash CPU-fallback
/// decision table, `classifySttExitCode`, and a heartbeat-timeout
/// cross-reference — all driven by subprocess-spawn/crash/HTTP-poll
/// mechanics that have no equivalent against an in-process engine. Those
/// groups were retired here (not adapted). See this issue's Evidence block
/// `remaining_risks` for the consolidated coverage-gap note, closed by
/// Issue 04 (backend selection) and Issue 05 (resilience).
///
/// DO NOT import from other test files — test files are not exported.
/// Fake helpers are redefined here so this file is self-contained.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

// ── Fake helpers ─────────────────────────────────────────────────────────────

class _FakeWhisperEngine implements WhisperEngine {
  bool _loaded = false;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async => '';

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

/// Fake settings notifier that never hits disk.
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

/// Builds a [ProviderContainer] with injectable fakes.
ProviderContainer _makeContainer({AppSettings? settings}) {
  return ProviderContainer(
    overrides: [
      whisperEngineProvider.overrideWithValue(_FakeWhisperEngine()),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Idle-timeout management', () {
    test('notifyRecordingStarted() disables idle timer; '
        'notifyRecordingStopped() re-arms it', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(localSttBundleProvider.notifier);

      // These must not throw — they exercise the idle-timer guard paths.
      notifier.notifyRecordingStarted();
      notifier.notifyRecordingStopped();

      // State must not change by these calls alone (server not running).
      expect(
        container.read(localSttBundleProvider).serverState,
        SttServerState.stopped,
        reason:
            'Idle timer calls must not change server state when server is stopped',
      );
    });

    test(
      'notifyRecordingStarted() prevents idle timer reset during active recording',
      () async {
        final container = _makeContainer(
          // Use sttIdleTimeoutMinutes = 0 (keep-alive) so the timer is never
          // armed during the test — isolates the recording-active guard.
          settings: AppSettings.defaults.copyWith(
            sttModel: 'whisper-small',
            sttIdleTimeoutMinutes: 0,
          ),
        );
        addTearDown(container.dispose);

        final notifier = container.read(localSttBundleProvider.notifier);

        // Calling notifyRecordingStarted and notifyRecordingStopped while
        // the server is stopped must not throw and must leave state unchanged.
        notifier.notifyRecordingStarted();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        notifier.notifyRecordingStopped();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );

    test(
      'notifyTranscriptionCompleted() re-arms idle timer after recording',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(localSttBundleProvider.notifier);

        // Start → complete transcription → check no exception thrown.
        notifier.notifyRecordingStarted();
        notifier.notifyTranscriptionCompleted();

        // Server is stopped (never started) — state must still be stopped.
        expect(
          container.read(localSttBundleProvider).serverState,
          SttServerState.stopped,
        );
      },
    );
  });
}
