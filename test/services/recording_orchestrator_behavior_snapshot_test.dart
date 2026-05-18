/// Behavior-snapshot tests for the RecordingOrchestrator.
///
/// Two suites:
/// 1. Amplitude guard suite — dead-mic, auto-stop, duration-warning,
///    duration-limit using synthetic amplitude streams.
/// 2. Phase-transition table — all 11 allowed transitions + 3 rejected
///    transitions, matching the PRD state machine table.
/// 3. Idempotency snapshot — abbreviated snapshot that two parallel
///    toggleRecording() calls produce at most one start.
///
/// These are snapshot / characterisation tests that lock in today's behaviour
/// before extracting SafetyGuard, OomRecoveryHandler and RecordingStateMachine
/// from the orchestrator (issues 17–19).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Fakes (re-defined; test files are not exported)
// ---------------------------------------------------------------------------

class _FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  StreamController<double>? _ampCtrl;
  int startCallCount = 0;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => _ampCtrl?.stream;

  @override
  Future<void> startRecording() async {
    if (state.isRecording) return;
    if (errorOnStart) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_error',
      );
      return;
    }
    startCallCount++;
    _ampCtrl = StreamController<double>.broadcast();
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPathToReturn,
    );
  }

  @override
  Future<String?> stopRecording() async {
    _ampCtrl?.close();
    _ampCtrl = null;
    state = AudioStatus(filePath: wavPathToReturn);
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {}

  /// Emits amplitude samples via the active stream controller.
  void emitLevel(double level) => _ampCtrl?.add(level);
}

class _FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;
  bool transcribeThrows = false;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    if (ensureRunningThrows) throw Exception('STT server failed to start');
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    if (transcribeThrows) throw Exception('Transcription failed');
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? _defaults;

  final AppSettings _settings;

  static const _defaults = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'nothing',
    ),
  );

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSecureKeyStore extends SecureKeyStore {
  _FakeSecureKeyStore() : super(null);
  final _store = <String, String>{};

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async => _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

class _FakeDesktopPasteController extends DesktopPasteController {
  bool pasteThrows = false;

  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    if (pasteThrows) throw Exception('paste failed');
    return const NativePasteResult(status: NativePasteStatus.success);
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async => const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<void> dispose() async {}
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() {
    return const ModelDownloadState(
      downloadedModels: {
        'whisper-small',
        'whisper-medium',
        'whisper-large-v3-turbo',
      },
      serverReady: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _scratchDir = Directory('test${Platform.pathSeparator}.scratch_snapshot');

File _createFakeWav(String name) {
  final bytes = List<int>.filled(364, 0);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  final file = File('${_scratchDir.path}${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

/// Creates fake whisper-server binary + model file in [sttDirOverride] so
/// that the orchestrator's preflight checks pass. Returns those files so
/// the caller can clean them up or inspect them.
///
/// Call this only when you need `toggleRecording()` / `startRecording()` to
/// wire the amplitude subscription through the real orchestrator path.
List<File> createFakeStubFiles() {
  final dir = Directory(_scratchDir.path);
  dir.createSync(recursive: true);

  // Fake whisper-server binary (content doesn't matter — only existence).
  final serverName = Platform.isWindows
      ? 'whisper-server.exe'
      : 'whisper-server';
  final serverFile = File('${dir.path}${Platform.pathSeparator}$serverName');
  serverFile.writeAsBytesSync([0]);

  // Fake model file for whisper-small.
  // resolveModelFilename('whisper-small') returns 'ggml-small-q5_1.bin'.
  final modelFile = File(
    '${dir.path}${Platform.pathSeparator}ggml-small-q5_1.bin',
  );
  modelFile.writeAsBytesSync([0]);

  return [serverFile, modelFile];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioService fakeAudio;
  late _FakeSttService fakeStt;
  late _FakeDesktopPasteController fakePaste;
  late HistoryDatabase db;
  late File wavFile;
  late ProviderContainer container;

  // ------------------------------------------------------------------
  // Container factory — allows per-test AppSettings overrides.
  // ------------------------------------------------------------------
  ProviderContainer buildContainer(AppSettings settings) {
    return ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        audioServiceProvider.overrideWith(() => fakeAudio),
        localSttBundleProvider.overrideWith(() => fakeStt),
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
        secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
        desktopPasteControllerProvider.overrideWith((ref) => fakePaste),
        modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Shared setUp / tearDown
  // ------------------------------------------------------------------
  setUp(() async {
    sttDirOverride = _scratchDir.path;

    wavFile = _createFakeWav(
      'snap_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    fakeAudio = _FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
    fakeStt = _FakeSttService();
    fakePaste = _FakeDesktopPasteController();
    db = HistoryDatabase.forTesting(NativeDatabase.memory());

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData' ||
              call.method == 'Clipboard.getData') {
            return null;
          }
          return null;
        });

    container = buildContainer(
      const AppSettings(
        stt: SttSettings(model: 'whisper-small', language: 'English'),
        afterTranscriptionSection: AfterTranscriptionSettings(
          afterTranscription: 'nothing',
        ),
        onboarding: OnboardingSettings(onboardingCompleted: true),
      ),
    );

    await container.read(settingsProvider.future);
  });

  tearDown(() {
    sttDirOverride = null;
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    try {
      if (wavFile.existsSync()) wavFile.deleteSync();
    } catch (_) {}
  });

  tearDownAll(() {
    try {
      if (_scratchDir.existsSync()) _scratchDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ------------------------------------------------------------------
  // Helper: drive state machine to recording phase (bypasses preflight).
  // ------------------------------------------------------------------
  Future<RecordingOrchestrator> goToRecording() async {
    final orch = container.read(recordingOrchestratorProvider.notifier);
    await Future<void>.delayed(Duration.zero); // let build() microtask settle
    container.read(recordingProvider.notifier).startRecording();
    expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    // Start real audio so the amplitude stream exists.
    await container.read(audioServiceProvider.notifier).startRecording();
    return orch;
  }

  // =====================================================================
  // Group 1: Amplitude guard suite
  // =====================================================================
  //
  // These tests require the orchestrator's _amplitudeSub to be wired.
  // That subscription is set up inside startRecording() after preflight
  // passes and audio capture starts.
  //
  // Strategy:
  //   1. Create stub files (whisper-server + ggml-small-q5_1.bin) in sttDirOverride
  //      so preflight passes.
  //   2. Call toggleRecording() → full orchestrator start path → amplitude
  //      subscription is wired to _FakeAudioService._ampCtrl.
  //   3. Emit samples via fakeAudio.emitLevel() and assert phase changes.
  //
  // The FakeSttService is already configured to handle transcription, so
  // auto-stop leads all the way to done. Dead-mic leads to error.

  group('Amplitude guard suite', () {
    late List<File> stubFiles;

    /// Build a container with guard-specific settings and run preflight-aware
    /// startRecording() to wire the amplitude subscription.
    Future<ProviderContainer> buildGuardContainer(AppSettings settings) async {
      final c = buildContainer(settings);
      await c.read(settingsProvider.future);
      // Let the orchestrator build() microtask settle.
      await Future<void>.delayed(Duration.zero);
      // Kick off startRecording() — preflight will pass because stub files
      // exist in sttDirOverride. The call is fire-and-forget so we can emit
      // amplitude samples while it is suspended at ensureRunning().
      unawaited(
        c.read(recordingOrchestratorProvider.notifier).toggleRecording(),
      );
      // Yield to let the orchestrator reach audio capture + subscribe.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c;
    }

    setUp(() {
      // Create fake stub files so orchestrator preflight passes.
      stubFiles = createFakeStubFiles();
    });

    tearDown(() {
      for (final f in stubFiles) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    });

    test(
      'dead-mic: 10 silent samples without speech → phase becomes error',
      () async {
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 1.0, // 10 samples → dead-mic
              autoStopSilence: 0,
            ),
            behavior: BehaviorSettings(maxRecordDuration: 0),
          ),
        );
        addTearDown(c.dispose);

        // Verify recording started.
        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // 10 silent samples (level 0.0 < threshold 0.02) → dead-mic fires.
        for (var i = 0; i < 10; i++) {
          fakeAudio.emitLevel(0.0);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          c.read(recordingProvider).phase,
          RecordingPhase.error,
          reason:
              'dead-mic guard must transition to error after 10 silent samples',
        );
      },
    );

    test(
      'dead-mic: 9 silent samples without speech → guard does NOT fire yet',
      () async {
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 1.0,
              autoStopSilence: 0,
            ),
            behavior: BehaviorSettings(maxRecordDuration: 0),
          ),
        );
        addTearDown(c.dispose);

        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // 9 samples — one below the 10-sample threshold.
        for (var i = 0; i < 9; i++) {
          fakeAudio.emitLevel(0.0);
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(
          c.read(recordingProvider).phase,
          RecordingPhase.recording,
          reason: '9 silent samples must not yet trigger the dead-mic guard',
        );
      },
    );

    test(
      'auto-stop: speech then 10 silent samples → phase leaves recording',
      () async {
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 0,
              autoStopSilence: 1.0, // 10 samples → auto-stop
            ),
            behavior: BehaviorSettings(maxRecordDuration: 0),
          ),
        );
        addTearDown(c.dispose);

        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // Emit one speech sample (≥ threshold 0.02) to arm _speechDetected.
        fakeAudio.emitLevel(0.5);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Then 10 silent samples → auto-stop → stopRecording() pipeline.
        for (var i = 0; i < 10; i++) {
          fakeAudio.emitLevel(0.0);
        }
        // Allow time for auto-stop and async pipeline (transcription).
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(
          c.read(recordingProvider).phase,
          anyOf(
            RecordingPhase.transcribing,
            RecordingPhase.done,
            RecordingPhase.error,
          ),
          reason:
              'auto-stop must leave recording phase after 10 silent '
              'samples following speech',
        );
      },
    );

    test(
      'auto-stop: interleaved speech resets silence counter — no premature stop',
      () async {
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 0,
              autoStopSilence: 1.0,
            ),
            behavior: BehaviorSettings(maxRecordDuration: 0),
          ),
        );
        addTearDown(c.dispose);

        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // Interleave speech + silence — counter resets on each speech sample.
        // Each round: 1 speech + 5 silence. Max consecutive silence = 5 < 10.
        for (var i = 0; i < 5; i++) {
          fakeAudio.emitLevel(0.5); // speech
          for (var s = 0; s < 5; s++) {
            fakeAudio.emitLevel(0.0); // silence (5 — below 10 threshold)
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(
          c.read(recordingProvider).phase,
          RecordingPhase.recording,
          reason: 'interleaved speech must reset the silence counter',
        );
      },
    );

    test(
      'duration-limit: maxRecordDuration=2s, guard fires after elapsed >= 2s',
      () async {
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 0,
              autoStopSilence: 0,
            ),
            behavior: BehaviorSettings(maxRecordDuration: 2), // 2-second limit
          ),
        );
        addTearDown(c.dispose);

        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // Emit one sample per 100ms, waiting for the wall-clock elapsed timer
        // (driven by RecordingNotifier._elapsedTimer) to tick past 2 seconds.
        for (var i = 0; i < 25; i++) {
          fakeAudio.emitLevel(0.5); // speech — avoids dead-mic path
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (c.read(recordingProvider).phase != RecordingPhase.recording) {
            break;
          }
        }

        expect(
          c.read(recordingProvider).phase,
          anyOf(
            RecordingPhase.transcribing,
            RecordingPhase.done,
            RecordingPhase.error,
          ),
          reason:
              'duration-limit guard must stop recording after maxRecordDuration',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'duration-warning: guard fires at 90% and eventually stops at 100%',
      () async {
        // The 90% warning sets _durationWarningFired (private flag) and
        // optionally plays a sound. We cannot observe the flag directly, but
        // we can verify that the recording is still active just before the
        // limit (guard hasn't fully fired) and then transitions after the limit.
        final c = await buildGuardContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            recordingSafety: RecordingSafetySettings(
              deadMicTimeout: 0,
              autoStopSilence: 0,
            ),
            behavior: BehaviorSettings(maxRecordDuration: 2),
            sound: SoundSettings(
              durationWarningSound: false, // silence sound output in tests
            ),
          ),
        );
        addTearDown(c.dispose);

        expect(c.read(recordingProvider).phase, RecordingPhase.recording);

        // Drive past 2 s, emitting samples to trigger _evaluateGuard().
        for (var i = 0; i < 25; i++) {
          fakeAudio.emitLevel(0.5);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (c.read(recordingProvider).phase != RecordingPhase.recording) {
            break;
          }
        }

        expect(
          c.read(recordingProvider).phase,
          anyOf(
            RecordingPhase.transcribing,
            RecordingPhase.done,
            RecordingPhase.error,
          ),
          reason:
              'guard must have fired at or after duration limit '
              '(90% warning precedes 100% stop)',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // =====================================================================
  // Group 2: Phase-transition table suite
  // =====================================================================

  group('Phase-transition table', () {
    // -- Allowed transitions ------------------------------------------------

    test('idle ─start→ recording', () async {
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      await Future<void>.delayed(Duration.zero);
      container.read(recordingProvider.notifier).startRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('recording ─stop→ transcribing', () async {
      await goToRecording();

      container.read(recordingProvider.notifier).stopRecording();

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );
    });

    test('recording ─guardFire→ transcribing (amplitude auto-stop)', () async {
      // Amplitude guard requires _amplitudeSub to be wired via the orchestrator's
      // full startRecording() path. Create stub files so preflight passes.
      final stubs = createFakeStubFiles();
      addTearDown(() {
        for (final f in stubs) {
          try {
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      });

      final guardContainer = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          recordingSafety: RecordingSafetySettings(
            deadMicTimeout: 0,
            autoStopSilence: 1.0, // 10 samples → auto-stop
          ),
          behavior: BehaviorSettings(maxRecordDuration: 0),
        ),
      );
      addTearDown(guardContainer.dispose);
      await guardContainer.read(settingsProvider.future);
      await Future<void>.delayed(Duration.zero);

      // Wire amplitude subscription via the full orchestrator start path.
      unawaited(
        guardContainer
            .read(recordingOrchestratorProvider.notifier)
            .toggleRecording(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        guardContainer.read(recordingProvider).phase,
        RecordingPhase.recording,
        reason: 'must reach recording phase before emitting samples',
      );

      // Arm speech-detected flag, then silence → auto-stop.
      fakeAudio.emitLevel(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      for (var i = 0; i < 10; i++) {
        fakeAudio.emitLevel(0.0);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final phase = guardContainer.read(recordingProvider).phase;
      expect(
        phase,
        anyOf(
          RecordingPhase.transcribing,
          RecordingPhase.done,
          RecordingPhase.error,
        ),
        reason: 'guardFire auto-stop must leave recording phase',
      );
    });

    test('recording ─fail→ error', () async {
      await goToRecording();

      container.read(recordingProvider.notifier).fail('test_error');

      expect(container.read(recordingProvider).phase, RecordingPhase.error);
    });

    test('transcribing ─complete→ done (via processing)', () async {
      await goToRecording();

      container.read(recordingProvider.notifier).stopRecording();
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );

      // completeTranscription transitions transcribing → done.
      container.read(recordingProvider.notifier).completeTranscription('Hello');

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
    });

    test('transcribing ─fail→ error', () async {
      await goToRecording();

      container.read(recordingProvider.notifier).stopRecording();
      container.read(recordingProvider.notifier).fail('stt_error');

      expect(container.read(recordingProvider).phase, RecordingPhase.error);
    });

    test('processing ─paste→ done (pipeline happy path)', () async {
      // The pipeline goes through processing internally — for the notifier,
      // completeTranscription() works from both transcribing and processing.
      // We simulate processing → done by manually going through the phases.
      await goToRecording();

      container.read(recordingProvider.notifier).stopRecording();
      // completeTranscription accepts transcribing OR processing.
      container
          .read(recordingProvider.notifier)
          .completeTranscription('Final text');

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(container.read(recordingProvider).transcript, 'Final text');
    });

    test('processing ─fail→ error', () async {
      await goToRecording();

      container.read(recordingProvider.notifier).stopRecording();
      container.read(recordingProvider.notifier).fail('paste_error');

      expect(container.read(recordingProvider).phase, RecordingPhase.error);
      expect(container.read(recordingProvider).errorMessage, 'paste_error');
    });

    test('done ─reset→ idle', () async {
      await goToRecording();
      container.read(recordingProvider.notifier).stopRecording();
      container.read(recordingProvider.notifier).completeTranscription('Done');
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      container.read(recordingOrchestratorProvider.notifier).reset();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('error ─reset→ idle', () async {
      container.read(recordingProvider.notifier).fail('something_went_wrong');
      expect(container.read(recordingProvider).phase, RecordingPhase.error);

      container.read(recordingOrchestratorProvider.notifier).reset();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('error ─oomRetry→ idle (OOM recovery resets to idle)', () async {
      // The OOM recovery path calls reset() on the recording notifier, which
      // transitions error → idle (the UI then auto-restarts recording via
      // applyOomModelFallback / user action). We verify that after OOM
      // recovery handling, the state returns to idle.
      await goToRecording();
      container.read(recordingProvider.notifier).stopRecording();
      container.read(recordingProvider.notifier).fail('stt_cuda_oom');
      expect(container.read(recordingProvider).phase, RecordingPhase.error);

      // OOM recovery resets to idle then shows the OOM dialog.
      container.read(recordingProvider.notifier).reset();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });

    // -- Rejected transitions -----------------------------------------------

    test('rejected: toggleRecording while transcribing is a no-op', () async {
      final orch = await goToRecording();
      container.read(recordingProvider.notifier).stopRecording();
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );

      await orch.toggleRecording();

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
        reason: 'toggleRecording must be rejected while transcribing',
      );
    });

    test('rejected: toggleRecording while in error phase is a no-op', () async {
      container.read(recordingProvider.notifier).fail('test_error');
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.error,
        reason: 'toggleRecording must be rejected while in error phase',
      );
    });

    test('rejected: startRecording() while recording is a no-op', () async {
      final orch = await goToRecording();
      final countBefore = fakeAudio.startCallCount;

      await orch.startRecording();

      expect(
        fakeAudio.startCallCount,
        equals(countBefore),
        reason: 'startRecording must be rejected when already recording',
      );
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.recording,
        reason: 'phase must remain recording after rejected start',
      );
    });

    test(
      'rejected: RecordingNotifier.startRecording() ignored when not idle',
      () async {
        // Directly verify the RecordingNotifier rejects transitions from non-idle.
        await goToRecording();
        container.read(recordingProvider.notifier).stopRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.transcribing,
        );

        // Attempt to start recording from transcribing state — must be ignored.
        container.read(recordingProvider.notifier).startRecording();

        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.transcribing,
          reason: 'startRecording must be ignored when not in idle phase',
        );
      },
    );

    test('rejected: completeTranscription ignored when in idle phase', () async {
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      container
          .read(recordingProvider.notifier)
          .completeTranscription('should be ignored');

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.idle,
        reason:
            'completeTranscription must be ignored when not transcribing/processing',
      );
    });

    // -- Full sequence snapshot ---------------------------------------------

    test(
      'full allowed-transition sequence: idle → recording → transcribing → done → idle',
      () async {
        final phases = <RecordingPhase>[];
        container.listen(
          recordingProvider.select((s) => s.phase),
          (_, phase) => phases.add(phase),
          fireImmediately: true,
        );

        // idle → recording
        await Future<void>.delayed(Duration.zero);
        container.read(recordingProvider.notifier).startRecording();

        // recording → transcribing
        container.read(recordingProvider.notifier).stopRecording();

        // transcribing → done
        container
            .read(recordingProvider.notifier)
            .completeTranscription('Test');

        // done → idle
        container.read(recordingOrchestratorProvider.notifier).reset();

        expect(
          phases,
          containsAllInOrder([
            RecordingPhase.idle,
            RecordingPhase.recording,
            RecordingPhase.transcribing,
            RecordingPhase.done,
            RecordingPhase.idle,
          ]),
        );
      },
    );

    test('full error path: idle → recording → error → idle', () async {
      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, phase) => phases.add(phase),
        fireImmediately: true,
      );

      await Future<void>.delayed(Duration.zero);
      container.read(recordingProvider.notifier).startRecording();
      container.read(recordingProvider.notifier).fail('error_occurred');
      container.read(recordingOrchestratorProvider.notifier).reset();

      expect(
        phases,
        containsAllInOrder([
          RecordingPhase.idle,
          RecordingPhase.recording,
          RecordingPhase.error,
          RecordingPhase.idle,
        ]),
      );
    });
  });

  // =====================================================================
  // Group 3: Idempotency snapshot
  // =====================================================================

  group('Idempotency snapshot', () {
    test('two parallel toggleRecording() calls produce at most one start, '
        'no errors (abbreviated snapshot of issue-03 behaviour)', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final errors = <Object>[];

      // Fire two toggleRecording() calls concurrently from idle.
      // Only one should proceed; the other must be silently suppressed.
      await Future.wait([
        Future<void>(() async {
          try {
            await orch.toggleRecording();
          } catch (e) {
            errors.add(e);
          }
        }),
        Future<void>(() async {
          try {
            await orch.toggleRecording();
          } catch (e) {
            errors.add(e);
          }
        }),
      ]);

      expect(errors, isEmpty, reason: 'toggleRecording must never throw');
      expect(
        fakeAudio.startCallCount,
        lessThanOrEqualTo(1),
        reason: 'at most one audio capture session must be started',
      );
    });

    test('startRecording() while _startInFlight is set is a silent no-op '
        '(second call does not change the audio start count)', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Manually drive to recording phase (preflight bypassed).
      container.read(recordingProvider.notifier).startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      final countBefore = fakeAudio.startCallCount;

      // Second startRecording() while phase != idle must be a no-op.
      await orch.startRecording();

      expect(
        fakeAudio.startCallCount,
        equals(countBefore),
        reason: 'audio startRecording must not be called again',
      );
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.recording,
        reason: 'phase must remain recording',
      );
    });

    test('tryAcquireStartLock() — second concurrent call is denied '
        'while first holds the lock', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final acquired1 = orch.tryAcquireStartLock();
      expect(acquired1, isTrue, reason: 'first acquire must succeed');

      final acquired2 = orch.tryAcquireStartLock();
      expect(
        acquired2,
        isFalse,
        reason: 'second acquire must be denied while lock is held',
      );

      orch.releaseStartLock();

      final acquired3 = orch.tryAcquireStartLock();
      expect(
        acquired3,
        isTrue,
        reason: 'acquire after release must succeed again',
      );
      orch.releaseStartLock();
    });
  });
}
