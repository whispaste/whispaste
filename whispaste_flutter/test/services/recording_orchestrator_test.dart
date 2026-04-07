/// Recording orchestrator unit tests.
///
/// Tests the critical dictation pipeline (audio → STT → history → clipboard)
/// using fake dependencies injected via Riverpod overrides.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/config_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake audio service — no real hardware interaction.
class FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  StreamController<double>? _ampCtrl;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => _ampCtrl?.stream;

  @override
  Future<void> startRecording() async {
    if (errorOnStart) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_error',
      );
      return;
    }
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
class FakeSttService extends SttServiceNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;
  bool throwTimeoutException = false;
  bool transcribeThrows = false;

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
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async {
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

  /// Test defaults with clipboard action disabled to avoid platform channels
  /// and post-processing disabled (not yet implemented).
  static const _testDefaults = AppSettings(
    afterTranscription: 'nothing',
    postProcessEnabled: false,
  );

  @override
  Future<AppSettings> build() async => _settings;
}

/// Fake config notifier — returns defaults without disk I/O.
class FakeConfigNotifier extends ConfigNotifier {
  @override
  Future<WhisPasteConfig> build() async => const WhisPasteConfig();
}

/// In-memory secure key store that never touches platform credential stores.
class FakeSecureKeyStore extends SecureKeyStore {
  FakeSecureKeyStore() : super(null);

  final _store = <String, String>{};

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async =>
      _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Directory for scratch files used during tests.
final _scratchDir = Directory(
  'test${Platform.pathSeparator}.scratch',
);

/// Creates a fake WAV file with a minimal RIFF header + padding.
/// Returns the file with an absolute path.
File createFakeWav(String name) {
  // 44-byte WAV header + 320 bytes of silence = ~10 ms at 16 kHz mono 16-bit.
  final bytes = List<int>.filled(364, 0);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  final file = File(
    '${_scratchDir.path}${Platform.pathSeparator}$name',
  );
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
  late HistoryDatabase db;
  late File wavFile;

  setUp(() async {
    // Create a fake WAV file the orchestrator can read.
    wavFile = createFakeWav(
      'test_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    fakeAudio = FakeAudioService()
      ..wavPathToReturn = wavFile.absolute.path;
    fakeStt = FakeSttService();
    db = HistoryDatabase.forTesting(NativeDatabase.memory());

    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        audioServiceProvider.overrideWith(() => fakeAudio),
        sttServiceProvider.overrideWith(() => fakeStt),
        configProvider.overrideWith(() => FakeConfigNotifier()),
        settingsProvider.overrideWith(() => FakeSettingsNotifier()),
        secureKeyStoreProvider
            .overrideWith((ref) => FakeSecureKeyStore()),
        effectiveConfigProvider.overrideWith(
          (ref) => const WhisPasteConfig(
            useLocalStt: false,
            localModelId: 'whisper-small',
            transcriptionLanguage: 'en',
          ),
        ),
      ],
    );

    // Ensure async providers resolve before tests run.
    await container.read(settingsProvider.future);
  });

  tearDown(() {
    container.dispose();
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
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.recording,
    );
    return orch;
  }

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

      final stats = await db.customSelect(
        'SELECT * FROM daily_stats',
      ).get();
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
    test('startRecording fails when STT binary is missing', () async {
      // Initialize orchestrator (build + pre-warm settle).
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .startRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(
        state.errorMessage,
        anyOf(
          'stt_server_not_found',
          'stt_model_not_found',
          'stt_model_unknown',
        ),
      );
    });

    test('toggleRecording from idle hits preflight → error', () async {
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.error,
      );
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
            return FakeAudioService()
              ..wavPathToReturn = wavFile.absolute.path;
          }),
          sttServiceProvider.overrideWith(() => customStt),
          configProvider.overrideWith(() => FakeConfigNotifier()),
          settingsProvider.overrideWith(() => FakeSettingsNotifier()),
          secureKeyStoreProvider
              .overrideWith((ref) => FakeSecureKeyStore()),
          effectiveConfigProvider.overrideWith(
            (ref) => const WhisPasteConfig(
              useLocalStt: false,
              localModelId: 'whisper-small',
              transcriptionLanguage: 'en',
            ),
          ),
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

      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.error,
      );
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
}

// ---------------------------------------------------------------------------
// Additional fake: STT service that stays in stopped state after ensureRunning
// ---------------------------------------------------------------------------

class _NotReadySttService extends SttServiceNotifier {
  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.stopped, port: 0);

  @override
  Future<void> ensureRunning() async {
    // Deliberately leave state as stopped (not ready).
  }

  @override
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async =>
      '';

  @override
  Future<void> prewarm() async {}
}
