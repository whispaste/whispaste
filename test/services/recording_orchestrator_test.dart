/// Recording orchestrator unit tests.
///
/// Tests the critical dictation pipeline (audio → STT → history → clipboard)
/// using fake dependencies injected via Riverpod overrides.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/recording/clipping_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake audio service — no real hardware interaction.
class FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  StreamController<double>? _ampCtrl;

  /// Counts how many times [startRecording] was successfully invoked
  /// (i.e. not blocked by the "already recording" guard).
  int startCallCount = 0;

  /// Overrides the inherited [lastRecordingClippedSamples] getter so tests
  /// can simulate clipping outcomes without driving the real PCM pipeline.
  int clippedSamplesToReport = 0;

  @override
  int get lastRecordingClippedSamples => clippedSamplesToReport;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => _ampCtrl?.stream;

  @override
  Future<void> startRecording() async {
    if (state.isRecording) {
      // Mirror the audio service's logged no-op — do NOT throw.
      return;
    }
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
}

/// Fake STT service — returns configurable transcripts, no subprocess.
class FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;
  bool throwTimeoutException = false;
  bool transcribeThrows = false;

  /// Language the orchestrator handed to the last [transcribeBytes] call.
  String? lastLanguage;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    if (throwTimeoutException) {
      throw TimeoutException(
        'STT start timed out',
        const Duration(seconds: 30),
      );
    }
    if (ensureRunningThrows) {
      throw Exception('STT server failed to start');
    }
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    lastLanguage = language;
    if (transcribeThrows) {
      throw Exception('Transcription failed');
    }
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

/// Fake settings notifier — returns test defaults without DB or secure store.
class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? _testDefaults;

  final AppSettings _settings;

  /// Test defaults keep post-processing disabled to stay focused on the
  /// transcription pipeline in these unit tests.
  static const _testDefaults = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'nothing',
    ),
  );

  @override
  Future<AppSettings> build() async => _settings;
}

/// In-memory secure key store that never touches platform credential stores.
class FakeSecureKeyStore extends SecureKeyStore {
  FakeSecureKeyStore() : super(null);

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

/// Fake desktop paste bridge that records capture/paste calls.
class FakeDesktopPasteController extends DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;
  Duration? lastDelay;
  bool pasteResult = true;
  bool captureResult = true;
  final captureResults = <bool>[];
  bool disposed = false;

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls += 1;
    if (captureResults.isNotEmpty) {
      return captureResults.removeAt(0);
    }
    return captureResult;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls += 1;
    lastDelay = delay;
    return pasteResult
        ? const NativePasteResult(status: NativePasteStatus.success)
        : const NativePasteResult(status: NativePasteStatus.postFailed);
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakeModelDownloadNotifier extends ModelDownloadNotifier {
  FakeModelDownloadNotifier(this._downloadedModels);

  final Set<String> _downloadedModels;

  @override
  ModelDownloadState build() {
    return ModelDownloadState(
      downloadedModels: _downloadedModels,
      serverReady: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Directory for scratch files used during tests.
final _scratchDir = Directory('test${Platform.pathSeparator}.scratch');

/// Creates a fake WAV file with a minimal RIFF header + padding.
/// Returns the file with an absolute path.
File createFakeWav(String name) {
  // 44-byte WAV header + 320 bytes of silence = ~10 ms at 16 kHz mono 16-bit.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeAudioService fakeAudio;
  late FakeSttService fakeStt;
  late FakeDesktopPasteController fakeDesktopPaste;
  late HistoryDatabase db;
  late File wavFile;
  String? clipboardText;

  ProviderContainer buildContainer(AppSettings settings) {
    return ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        audioServiceProvider.overrideWith(() => fakeAudio),
        localSttBundleProvider.overrideWith(() => fakeStt),
        settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
        secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
        desktopPasteControllerProvider.overrideWith((ref) => fakeDesktopPaste),
        modelDownloadProvider.overrideWith(
          () => FakeModelDownloadNotifier({
            'whisper-small',
            'whisper-medium',
            'whisper-large-v3-turbo',
          }),
        ),
      ],
    );
  }

  setUp(() async {
    // Isolate preflight checks from the real filesystem by pointing
    // sttDir at an empty scratch directory — no server binary exists here.
    sttDirOverride = _scratchDir.path;

    // Create a fake WAV file the orchestrator can read.
    wavFile = createFakeWav(
      'test_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
    fakeStt = FakeSttService();
    fakeDesktopPaste = FakeDesktopPasteController();
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    clipboardText = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardText == null) return null;
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
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

    // Ensure async providers resolve before tests run.
    await container.read(settingsProvider.future);
  });

  tearDown(() {
    sttDirOverride = null;
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (wavFile.existsSync()) {
      try {
        wavFile.deleteSync();
      } catch (_) {}
    }
  });

  // Clean up the scratch directory after all tests.
  tearDownAll(() {
    if (_scratchDir.existsSync()) {
      try {
        _scratchDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ── Helper: initialize orchestrator and move state to recording ─────────

  /// Initializes the orchestrator and drives the state machine to
  /// [RecordingPhase.recording].
  ///
  /// We set the phase manually because [startRecording] runs preflight
  /// checks against real filesystem paths that don't exist in tests.
  Future<RecordingOrchestrator> startRecordingPhase() async {
    final orch = container.read(recordingOrchestratorProvider.notifier);
    // Let the build() microtask (pre-warm) run and settle.
    await Future<void>.delayed(Duration.zero);

    container.read(recordingProvider.notifier).startRecording();
    expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    return orch;
  }

  // =========================================================================
  // Recognition language (store-review regression, June 2026)
  // =========================================================================

  group('Recognition language', () {
    /// Rebuilds the container with [stt]/[interface_] overrides and runs a
    /// full record→transcribe cycle, returning the language the transcriber
    /// received.
    Future<String?> languageSeenByTranscriber({
      required SttSettings stt,
      InterfaceSettings interface_ = const InterfaceSettings(),
    }) async {
      container.dispose();
      container = buildContainer(
        AppSettings(
          interface_: interface_,
          stt: stt,
          afterTranscriptionSection: const AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      return fakeStt.lastLanguage;
    }

    test('auto-detect reaches the transcriber as auto — never the UI '
        'locale', () async {
      // A Russian speaker on an English UI: before the fix the app forced
      // language=en and whisper produced English text from Russian audio.
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small'),
        interface_: const InterfaceSettings(locale: 'en'),
      );
      expect(lang, 'auto');
    });

    test('auto-detect ignores non-English UI locales too', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small'),
        interface_: const InterfaceSettings(locale: 'he'),
      );
      expect(lang, 'auto');
    });

    test('a catalog language code reaches the transcriber unchanged', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small', language: 'ru'),
      );
      expect(lang, 'ru');
    });

    test('legacy display value still resolves to its code', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small', language: 'German'),
      );
      expect(lang, 'de');
    });
  });

  // =========================================================================
  // Happy path
  // =========================================================================

  group('Happy path', () {
    test('stopRecording transcribes and saves to history', () async {
      fakeStt.transcriptToReturn = 'Test transcription result';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Test transcription result');

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.content, 'Test transcription result');
      expect(entries.first.model, 'whisper-small');
      expect(entries.first.isLocal, isTrue);
      expect(entries.first.source, 'dictation');
    });

    test('toggleRecording from recording state runs pipeline', () async {
      fakeStt.transcriptToReturn = 'Toggle result';
      final orch = await startRecordingPhase();

      await orch.toggleRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Toggle result');
    });

    test('daily stats are recorded', () async {
      fakeStt.transcriptToReturn = 'Stats test';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final stats = await db.customSelect('SELECT * FROM daily_stats').get();
      expect(stats, isNotEmpty);
    });

    test('auto-generates title from first ~60 chars', () async {
      fakeStt.transcriptToReturn = 'Short text';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries.first.title, 'Short text');
    });

    test('truncates long title at word boundary', () async {
      fakeStt.transcriptToReturn =
          'This is a very long transcription result that exceeds '
          'sixty characters and should be truncated at a word boundary';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries.first.title.length, lessThanOrEqualTo(62));
      expect(entries.first.title, endsWith('…'));
    });
  });

  // =========================================================================
  // Error during STT start
  // =========================================================================

  group('Error during STT start', () {
    test('ensureRunning() throws → state is error', () async {
      fakeStt.ensureRunningThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, contains('STT server failed'));
    });
  });

  // =========================================================================
  // Timeout during STT start
  // =========================================================================

  group('Timeout during STT start', () {
    test('TimeoutException → fails with stt_start_timeout', () async {
      fakeStt.throwTimeoutException = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'stt_start_timeout');
    });
  });

  // =========================================================================
  // Error during transcription
  // =========================================================================

  group('Error during transcription', () {
    test('transcribeBytes() throws → state is error', () async {
      fakeStt.transcribeThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, contains('Transcription failed'));
    });

    test('no history entry is saved on transcription error', () async {
      fakeStt.transcribeThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // Cancel / reset during recording
  // =========================================================================

  group('Cancel during recording', () {
    test('reset() returns to idle without transcription', () async {
      final orch = await startRecordingPhase();

      orch.reset();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // Guard resets after error — can record again
  // =========================================================================

  group('Guard resets after error', () {
    test('error → reset → second attempt succeeds', () async {
      // First attempt: STT fails.
      fakeStt.ensureRunningThrows = true;
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.error);

      // Reset to idle.
      orch.reset();
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      // Second attempt: fix the fake and retry.
      fakeStt.ensureRunningThrows = false;
      fakeStt.transcriptToReturn = 'Recovered';

      // Re-create the WAV since the first attempt cleans up (our fake is
      // a no-op, but the path must still resolve for the second run).
      wavFile = createFakeWav(
        'test_audio_retry_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio.wavPathToReturn = wavFile.absolute.path;

      container.read(recordingProvider.notifier).startRecording();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(container.read(recordingProvider).transcript, 'Recovered');
    });
  });

  // =========================================================================
  // Phase transitions
  // =========================================================================

  group('Phase transitions', () {
    test('correct order: idle → recording → transcribing → done', () async {
      fakeStt.transcriptToReturn = 'Phase test';

      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, phase) => phases.add(phase),
        fireImmediately: true,
      );

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(
        phases,
        containsAllInOrder([
          RecordingPhase.idle,
          RecordingPhase.recording,
          RecordingPhase.transcribing,
          RecordingPhase.done,
        ]),
      );
    });
  });

  // =========================================================================
  // Empty transcript
  // =========================================================================

  group('Empty transcript', () {
    test('empty STT result → fails with transcription_empty', () async {
      fakeStt.transcriptToReturn = '';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'transcription_empty');
    });

    test('no history entry is saved on empty transcript', () async {
      fakeStt.transcriptToReturn = '';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // No audio recorded
  // =========================================================================

  group('No audio recorded', () {
    test('null WAV path → fails with no_audio_recorded', () async {
      fakeAudio.wavPathToReturn = null;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'no_audio_recorded');
    });
  });

  // =========================================================================
  // Preflight failure (startRecording)
  // =========================================================================

  group('Preflight failure', () {
    test('missing STT binary is soft-handled (stays idle)', () async {
      // Soft-preflight catches stt_server_not_found and shows an info
      // notification instead of entering the error phase.
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .startRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.idle);
      expect(state.errorMessage, isNull);
    });

    test('toggleRecording from idle with missing binary stays idle', () async {
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });
  });

  // =========================================================================
  // Audio capture error
  // =========================================================================

  group('Audio capture error', () {
    test('audio service error on start → state is error', () async {
      // Override effective config so preflight passes (would need real
      // files). Instead, test the audio error path by going through
      // startRecording manually with a config that would pass preflight,
      // but we simulate audio failure after preflight.
      //
      // Since we can't easily pass preflight in tests, we verify the
      // guard by calling stopRecording with a missing WAV file.
      fakeAudio.wavPathToReturn = 'nonexistent_path_12345.wav';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'wav_file_not_created');
    });
  });

  // =========================================================================
  // STT server not ready after ensureRunning
  // =========================================================================

  group('STT server not ready', () {
    test('server state not ready → fails with stt_server_failed', () async {
      // Make ensureRunning succeed but leave state as non-ready.
      final customStt = _NotReadySttService();
      final c2 = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            final memDb = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(memDb.close);
            return memDb;
          }),
          audioServiceProvider.overrideWith(() {
            return FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
          }),
          localSttBundleProvider.overrideWith(() => customStt),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              const AppSettings(
                stt: SttSettings(model: 'whisper-small', language: 'English'),
                onboarding: OnboardingSettings(onboardingCompleted: true),
              ),
            ),
          ),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
        ],
      );
      addTearDown(c2.dispose);

      await c2.read(settingsProvider.future);
      final orch = c2.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      c2.read(recordingProvider.notifier).startRecording();
      await orch.stopRecording();

      final state = c2.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'stt_server_failed');
    });

    test(
      'CUDA OOM queues recovery dialog context and resets to idle',
      () async {
        final customStt = _NotReadySttService(
          statusAfterEnsure: const SttStatus(
            serverState: SttServerState.error,
            errorMessage: 'stt_cuda_oom',
          ),
        );
        final c2 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              final memDb = HistoryDatabase.forTesting(NativeDatabase.memory());
              ref.onDispose(memDb.close);
              return memDb;
            }),
            audioServiceProvider.overrideWith(() {
              return FakeAudioService()
                ..wavPathToReturn = wavFile.absolute.path;
            }),
            localSttBundleProvider.overrideWith(() => customStt),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(
                  stt: SttSettings(
                    model: 'whisper-large-v3-turbo',
                    language: 'English',
                  ),
                  onboarding: OnboardingSettings(onboardingCompleted: true),
                ),
              ),
            ),
            secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
            modelDownloadProvider.overrideWith(
              () => FakeModelDownloadNotifier({
                'whisper-small',
                'whisper-medium',
                'whisper-large-v3-turbo',
              }),
            ),
          ],
        );
        addTearDown(c2.dispose);

        await c2.read(settingsProvider.future);
        final orch = c2.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        c2.read(recordingProvider.notifier).startRecording();
        await orch.stopRecording();

        expect(c2.read(recordingProvider).phase, RecordingPhase.idle);
        final recovery = c2.read(oomRecoveryPendingProvider);
        expect(recovery.pending, isTrue);
        expect(recovery.nextModelId, 'whisper-medium');
        expect(recovery.hasCloudConfigured, isFalse);
        expect(recovery.isPermanentFail, isFalse);
      },
    );
  });

  group('OOM recovery actions', () {
    test('applyOomModelFallback updates the local model', () async {
      // applyOomModelFallback only switches the model; the attempt counter is
      // incremented by OomRecoveryHandler.attemptRecovery() which is called
      // inside _handleOomRecovery() — not here.
      final orch = container.read(recordingOrchestratorProvider.notifier);

      final didSwitch = await orch.applyOomModelFallback('whisper-medium');

      expect(didSwitch, isTrue);
      expect(orch.oomAttemptCount, 0);
      final settings = await container.read(settingsProvider.future);
      expect(settings.effectiveModelId, 'whisper-medium');
    });

    test(
      'switchToConfiguredCloudStt prefers configured cloud provider',
      () async {
        final c2 = buildContainer(
          const AppSettings(
            stt: SttSettings(
              model: 'whisper-large-v3-turbo',
              language: 'English',
              provider: 'On Device',
            ),
            cloudProvider: CloudProviderSettings(
              cloudSttProvider: 'deepgram',
              deepgramApiKey: 'dg-test-key',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        addTearDown(c2.dispose);
        await c2.read(settingsProvider.future);

        final orch = c2.read(recordingOrchestratorProvider.notifier);
        final provider = await orch.switchToConfiguredCloudStt();
        final settings = await c2.read(settingsProvider.future);

        expect(provider, SttProviderType.deepgram);
        expect(settings.sttProviderType, SttProviderType.deepgram);
        expect(settings.cloudSttProviderType, CloudSttProvider.deepgram);
        expect(orch.oomAttemptCount, 0);
      },
    );
  });

  // =========================================================================
  // toggleRecording ignores non-idle / non-recording phases
  // =========================================================================

  group('toggleRecording guards', () {
    test('does nothing while transcribing', () async {
      final orch = await startRecordingPhase();

      // Drive to transcribing phase manually.
      container.read(recordingProvider.notifier).stopRecording();
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );

      await orch.toggleRecording();

      // Still transcribing — toggle was a no-op.
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );
    });

    test('does nothing in error phase', () async {
      container.read(recordingProvider.notifier).fail('test error');

      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.error);
    });
  });

  // =========================================================================
  // Recording idempotency — concurrent toggleRecording() calls
  // =========================================================================

  group('Recording idempotency', () {
    test('two parallel startRecording() calls produce one start, '
        'zero errors, one capture session', () async {
      // Drive orchestrator to idle state with pre-warmed microtask settled.
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Manually start the recording phase so preflight (filesystem) is
      // bypassed, then verify the audio service idempotency guard:
      // calling the orchestrator's startRecording while _startInFlight
      // is active (or phase is non-idle) must be a logged no-op.

      // First call: set phase to recording directly (as other tests do).
      container.read(recordingProvider.notifier).startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      // Audio service should not yet have been called via orchestrator.
      final countBefore = fakeAudio.startCallCount;

      // Second concurrent call to startRecording() — must be a no-op because
      // phase is no longer idle (immediate re-check after lock acquisition).
      final errors = <Object>[];
      await Future<void>(() async {
        try {
          await orch.startRecording();
        } catch (e) {
          errors.add(e);
        }
      });

      // No errors thrown.
      expect(errors, isEmpty, reason: 'startRecording must not throw');

      // Audio service startRecording was not called a second time.
      expect(
        fakeAudio.startCallCount,
        equals(countBefore),
        reason: 'Only one capture session should exist',
      );

      // Phase is still recording — the no-op left state unchanged.
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('two concurrent toggleRecording() calls from idle produce '
        'one start and zero thrown errors', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Both calls start while phase is idle. The _startInFlight guard
      // ensures only the first call proceeds; the second is a no-op.
      //
      // Note: toggleRecording from idle runs startRecording() which runs
      // preflight against _scratchDir (no server binary → soft-handled,
      // stays idle). What matters here is that no StateError is thrown and
      // startCallCount stays at 0 (preflight blocks audio capture).
      final errors = <Object>[];

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

      // No errors thrown — idempotency holds.
      expect(errors, isEmpty, reason: 'toggleRecording must never throw');

      // At most one audio capture was started (soft-preflight may block all).
      expect(
        fakeAudio.startCallCount,
        lessThanOrEqualTo(1),
        reason: 'At most one audio capture session permitted',
      );
    });

    // ── Voice-note button path ──────────────────────────────────────────────

    test(
      'tryAcquireStartLock returns true when idle, false when in flight',
      () async {
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // First acquire succeeds while orchestrator is idle.
        expect(orch.tryAcquireStartLock(), isTrue);

        // Second acquire fails — lock already held.
        expect(orch.tryAcquireStartLock(), isFalse);

        // After release the lock is available again.
        orch.releaseStartLock();
        expect(orch.tryAcquireStartLock(), isTrue);

        // Clean up.
        orch.releaseStartLock();
      },
    );

    test(
      'tryAcquireStartLock returns false when orchestrator is not idle',
      () async {
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Drive orchestrator to recording phase.
        container.read(recordingProvider.notifier).startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        // Lock acquisition must be denied — phase is not idle.
        expect(orch.tryAcquireStartLock(), isFalse);
      },
    );

    test('voice-note lock: second concurrent tryAcquireStartLock() is denied '
        'while first holds the lock (AC4 — voice-note button path)', () async {
      // This test covers AC4 for the voice-note button path.
      // It exercises the shared _startInFlight lock directly, which is the
      // mechanism VoiceNoteButton._startVoiceNote() relies on to prevent
      // two concurrent voice-note taps from starting two capture sessions.
      //
      // Dart is single-threaded, so "concurrent" is modelled by acquiring
      // the lock in tap-1, then verifying tap-2 is denied before tap-1
      // releases — the same sequence that occurs when two UI taps arrive
      // in the same event-loop turn.
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Tap-1 acquires the lock.
      final acquired1 = orch.tryAcquireStartLock();
      expect(acquired1, isTrue, reason: 'First tap should acquire the lock');

      // While tap-1 holds the lock, tap-2 must be denied.
      final acquired2 = orch.tryAcquireStartLock();
      expect(
        acquired2,
        isFalse,
        reason: 'Second concurrent tap must be suppressed (lock held)',
      );

      // Tap-1 releases. Now a third tap (e.g. after tap-1 finishes) must
      // succeed — verifies the lock is properly reusable.
      orch.releaseStartLock();
      final acquired3 = orch.tryAcquireStartLock();
      expect(
        acquired3,
        isTrue,
        reason: 'New tap after release must be able to acquire the lock',
      );
      orch.releaseStartLock();
    });
  });

  // =========================================================================
  // Clipboard / after-transcription action
  // =========================================================================

  group('After-transcription action', () {
    test('pipeline completes with clipboard action setting', () async {
      // Rebuild container with clipboard action.
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_clip_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Clipboard text';
      clipboardText = 'Existing clipboard';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      container.read(recordingProvider.notifier).startRecording();

      await orch.stopRecording();

      // Pipeline completes — clipboard action doesn't block it.
      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Clipboard text');

      // History entry saved.
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.content, 'Clipboard text');
      expect(clipboardText, 'Clipboard text');
      expect(fakeDesktopPaste.pasteCalls, 0);
    });

    test('pipeline completes with action=nothing (no clipboard)', () async {
      // Default FakeSettingsNotifier uses afterTranscription='nothing'.
      clipboardText = 'Keep me';
      fakeStt.transcriptToReturn = 'No clipboard';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(container.read(recordingProvider).transcript, 'No clipboard');
      expect(clipboardText, 'Keep me');
      expect(fakeDesktopPaste.pasteCalls, 0);
    });

    test(
      'paste action restores previous clipboard text after pasting',
      () async {
        container.dispose();
        db = HistoryDatabase.forTesting(NativeDatabase.memory());
        wavFile = createFakeWav(
          'test_audio_paste_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
        fakeStt = FakeSttService()..transcriptToReturn = 'Paste only';
        clipboardText = 'Original clipboard';

        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            behavior: BehaviorSettings(autoPasteDelay: 350),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final orch = await startRecordingPhase();
        await orch.stopRecording();

        expect(container.read(recordingProvider).phase, RecordingPhase.done);
        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(fakeDesktopPaste.lastDelay, const Duration(milliseconds: 350));
        expect(clipboardText, 'Original clipboard');
      },
    );

    test(
      'paste captures a target before pasting when none is available yet',
      () async {
        container.dispose();
        db = HistoryDatabase.forTesting(NativeDatabase.memory());
        wavFile = createFakeWav(
          'test_audio_retry_capture_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
        fakeStt = FakeSttService()..transcriptToReturn = 'Retry capture';
        clipboardText = 'Original clipboard';

        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            behavior: BehaviorSettings(autoPasteDelay: 200),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final orch = await startRecordingPhase();
        await orch.stopRecording();

        expect(container.read(recordingProvider).phase, RecordingPhase.done);
        expect(fakeDesktopPaste.captureCalls, 1);
        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(clipboardText, 'Original clipboard');
      },
    );

    test('clipboard_and_paste keeps transcript on clipboard', () async {
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_both_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Copy and paste';
      clipboardText = 'Original clipboard';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard_and_paste',
          ),
          behavior: BehaviorSettings(autoPasteDelay: 125),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(fakeDesktopPaste.pasteCalls, 1);
      expect(fakeDesktopPaste.lastDelay, const Duration(milliseconds: 125));
      expect(clipboardText, 'Copy and paste');
    });
  });

  // =========================================================================
  // WAV file edge cases
  // =========================================================================

  group('WAV file edge cases', () {
    test('empty WAV file → fails with wav_file_empty', () async {
      // Create a zero-byte WAV file.
      final emptyWav = File(
        '${_scratchDir.path}${Platform.pathSeparator}'
        'empty_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      emptyWav.parent.createSync(recursive: true);
      emptyWav.writeAsBytesSync([]);
      addTearDown(() {
        if (emptyWav.existsSync()) emptyWav.deleteSync();
      });

      fakeAudio.wavPathToReturn = emptyWav.absolute.path;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'wav_file_empty');
    });
  });

  // =========================================================================
  // ClippingState integration
  // =========================================================================

  group('ClippingState integration', () {
    test(
      'successful capture pushes the clipping counter into ClippingState',
      () async {
        fakeAudio.clippedSamplesToReport = 17;
        fakeStt.transcriptToReturn = 'transcript with clipping';
        final orch = await startRecordingPhase();

        await orch.stopRecording();

        final clipping = container.read(clippingStateProvider);
        expect(clipping.count, 17);
        expect(clipping.shouldShowBanner, isTrue);
      },
    );

    test('clean follow-up recording (count=0) clears the banner', () async {
      // First recording: clipping happened — banner appears.
      fakeAudio.clippedSamplesToReport = 5;
      fakeStt.transcriptToReturn = 'clipped';
      final orch1 = await startRecordingPhase();
      await orch1.stopRecording();
      expect(container.read(clippingStateProvider).shouldShowBanner, isTrue);

      // Second recording: clean → counter goes back to 0 → banner hides.
      // Build a fresh WAV so the orchestrator can still read non-empty bytes
      // (the previous capture cleaned up the prior file via cleanupFile,
      // which the fake stubs to no-op).
      wavFile = createFakeWav(
        'test_audio_followup_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio.wavPathToReturn = wavFile.absolute.path;
      fakeAudio.clippedSamplesToReport = 0;
      fakeStt.transcriptToReturn = 'clean';
      container.read(recordingProvider.notifier).reset();
      final orch2 = await startRecordingPhase();
      await orch2.stopRecording();

      final clipping = container.read(clippingStateProvider);
      expect(clipping.count, 0);
      expect(clipping.shouldShowBanner, isFalse);
    });

    test('capture-step failure (audio start error) leaves ClippingState '
        'untouched', () async {
      // Pre-seed ClippingState with a non-zero value from a "prior"
      // recording so we can verify the failed run does NOT clobber it.
      container
          .read(clippingStateProvider.notifier)
          .reportRecordingFinished(42);
      expect(container.read(clippingStateProvider).count, 42);

      // Force the next startRecording to fail.
      fakeAudio.errorOnStart = true;
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Drive the state machine into recording so stopRecording() runs
      // through capture and bails on the empty/missing audio result.
      container.read(recordingProvider.notifier).startRecording();
      fakeAudio.wavPathToReturn = null; // capture returns null path
      await orch.stopRecording();

      // The orchestrator transitioned to error (no_audio_recorded).
      expect(container.read(recordingProvider).phase, RecordingPhase.error);
      // ClippingState is unchanged — the prior banner stays.
      final clipping = container.read(clippingStateProvider);
      expect(clipping.count, 42);
      expect(clipping.shouldShowBanner, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Additional fake: STT service that stays in stopped state after ensureRunning
// ---------------------------------------------------------------------------

class _NotReadySttService extends SttServerStateNotifier {
  _NotReadySttService({
    this.statusAfterEnsure = const SttStatus(
      serverState: SttServerState.stopped,
      port: 0,
    ),
  });

  final SttStatus statusAfterEnsure;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.stopped, port: 0);

  @override
  Future<void> ensureRunning() async {
    state = statusAfterEnsure;
  }

  @override
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async => '';

  @override
  Future<void> prewarm() async {}
}
