import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';

// ---------------------------------------------------------------------------
// Helper: create a ProviderContainer for pure-logic tests (no widget needed).
// ---------------------------------------------------------------------------
ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Fakes for missingSelectedSpeechModelProvider tests — settings + model-download
// state without touching disk or the real notifiers' side effects.
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  _FakeModelDownloadNotifier(
    this._downloadedModels, {
    this.scanned = true,
    this.downloadingModelId,
  });

  final Set<String> _downloadedModels;
  final bool scanned;
  final String? downloadingModelId;

  @override
  ModelDownloadState build() => ModelDownloadState(
    downloadedModels: _downloadedModels,
    scanned: scanned,
    activeModelId: downloadingModelId,
    phase: downloadingModelId != null
        ? DownloadPhase.downloading
        : DownloadPhase.idle,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // RecordingState unit tests
  // -------------------------------------------------------------------------
  group('RecordingState', () {
    test('default state is idle with zeroed fields', () {
      const s = RecordingState();
      expect(s.phase, RecordingPhase.idle);
      expect(s.elapsed, Duration.zero);
      expect(s.audioLevel, 0.0);
      expect(s.transcript, isNull);
      expect(s.errorMessage, isNull);
    });

    test('convenience getters reflect phase', () {
      const idle = RecordingState();
      expect(idle.isIdle, isTrue);
      expect(idle.isRecording, isFalse);

      const rec = RecordingState(phase: RecordingPhase.recording);
      expect(rec.isRecording, isTrue);
      expect(rec.isIdle, isFalse);

      const trans = RecordingState(phase: RecordingPhase.transcribing);
      expect(trans.isTranscribing, isTrue);

      const done = RecordingState(phase: RecordingPhase.done);
      expect(done.isDone, isTrue);

      const err = RecordingState(phase: RecordingPhase.error);
      expect(err.isError, isTrue);
    });

    test('copyWith produces correct copy', () {
      const original = RecordingState();
      final copy = original.copyWith(
        phase: RecordingPhase.recording,
        elapsed: const Duration(seconds: 5),
        audioLevel: 0.7,
      );
      expect(copy.phase, RecordingPhase.recording);
      expect(copy.elapsed, const Duration(seconds: 5));
      expect(copy.audioLevel, 0.7);
      expect(copy.transcript, isNull);
    });

    test('equality and hashCode', () {
      const a = RecordingState(phase: RecordingPhase.done, transcript: 'hello');
      const b = RecordingState(phase: RecordingPhase.done, transcript: 'hello');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains key fields', () {
      const s = RecordingState(
        phase: RecordingPhase.error,
        errorMessage: 'oh no',
      );
      expect(s.toString(), contains('error'));
      expect(s.toString(), contains('oh no'));
    });
  });

  // -------------------------------------------------------------------------
  // RecordingNotifier — state transitions
  // -------------------------------------------------------------------------
  group('RecordingNotifier transitions', () {
    test('initial state is idle', () {
      final c = makeContainer();
      expect(c.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('startRecording transitions idle → recording', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).startRecording();
      expect(c.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('stopRecording transitions recording → transcribing', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).startRecording();
      c.read(recordingProvider.notifier).stopRecording();
      expect(c.read(recordingProvider).phase, RecordingPhase.transcribing);
    });

    test('completeTranscription transitions transcribing → done', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.completeTranscription('Hello world');

      final s = c.read(recordingProvider);
      expect(s.phase, RecordingPhase.done);
      expect(s.transcript, 'Hello world');
    });

    test('fail transitions any phase → error', () {
      for (final startPhase in RecordingPhase.values) {
        final c = ProviderContainer();

        try {
          final n = c.read(recordingProvider.notifier);

          // Drive to the desired starting phase.
          switch (startPhase) {
            case RecordingPhase.idle:
              break;
            case RecordingPhase.recording:
              n.startRecording();
            case RecordingPhase.transcribing:
              n.startRecording();
              n.stopRecording();
            case RecordingPhase.refining:
              n.startRecording();
              n.stopRecording();
              n.startRefining('raw text');
            case RecordingPhase.done:
              n.startRecording();
              n.stopRecording();
              n.completeTranscription('text');
            case RecordingPhase.error:
              n.fail('prior error');
          }
          expect(c.read(recordingProvider).phase, startPhase);

          n.fail('boom');
          final s = c.read(recordingProvider);
          expect(s.phase, RecordingPhase.error);
          expect(s.errorMessage, 'boom');
        } finally {
          c.dispose();
        }
      }
    });

    test('reset returns to idle from any phase', () {
      for (final startPhase in RecordingPhase.values) {
        final c = ProviderContainer();

        try {
          final n = c.read(recordingProvider.notifier);

          switch (startPhase) {
            case RecordingPhase.idle:
              break;
            case RecordingPhase.recording:
              n.startRecording();
            case RecordingPhase.transcribing:
              n.startRecording();
              n.stopRecording();
            case RecordingPhase.refining:
              n.startRecording();
              n.stopRecording();
              n.startRefining('raw text');
            case RecordingPhase.done:
              n.startRecording();
              n.stopRecording();
              n.completeTranscription('text');
            case RecordingPhase.error:
              n.fail('err');
          }
          expect(c.read(recordingProvider).phase, startPhase);

          n.reset();
          expect(c.read(recordingProvider).phase, RecordingPhase.idle);
        } finally {
          c.dispose();
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // Guards — invalid transitions are no-ops
  // -------------------------------------------------------------------------
  group('RecordingNotifier guards', () {
    test('startRecording is no-op when already recording', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.startRecording(); // should be ignored
      expect(c.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('startRecording is no-op when transcribing', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.startRecording(); // should be ignored
      expect(c.read(recordingProvider).phase, RecordingPhase.transcribing);
    });

    test('stopRecording is no-op when idle', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).stopRecording();
      expect(c.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('stopRecording is no-op when transcribing', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.stopRecording(); // should be ignored
      expect(c.read(recordingProvider).phase, RecordingPhase.transcribing);
    });

    test('completeTranscription is no-op when not transcribing', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).completeTranscription('hi');
      expect(c.read(recordingProvider).phase, RecordingPhase.idle);
      expect(c.read(recordingProvider).transcript, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Audio level
  // -------------------------------------------------------------------------
  group('RecordingNotifier audioLevel', () {
    test('updateAudioLevel works during recording', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.updateAudioLevel(0.75);
      expect(c.read(recordingProvider).audioLevel, 0.75);
    });

    test('updateAudioLevel is no-op when idle', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).updateAudioLevel(0.5);
      expect(c.read(recordingProvider).audioLevel, 0.0);
    });

    test('audioLevel is clamped to 0.0–1.0', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();

      n.updateAudioLevel(1.5);
      expect(c.read(recordingProvider).audioLevel, 1.0);

      n.updateAudioLevel(-0.3);
      expect(c.read(recordingProvider).audioLevel, 0.0);
    });

    test('audioLevel resets to 0 on stopRecording', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.updateAudioLevel(0.8);
      n.stopRecording();
      expect(c.read(recordingProvider).audioLevel, 0.0);
    });
  });

  // -------------------------------------------------------------------------
  // Elapsed timer
  // -------------------------------------------------------------------------
  group('RecordingNotifier elapsed timer', () {
    test('elapsed increments while recording', () async {
      final c = makeContainer();
      c.read(recordingProvider.notifier).startRecording();

      // Let the 1-second periodic timer fire twice.
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      final elapsed = c.read(recordingProvider).elapsed;
      expect(elapsed.inSeconds, greaterThanOrEqualTo(2));
    });

    test('elapsed stops on stopRecording', () async {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      n.stopRecording();

      final afterStop = c.read(recordingProvider).elapsed;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final later = c.read(recordingProvider).elapsed;

      expect(later, equals(afterStop));
    });

    test('elapsed resets on reset()', () async {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      n.reset();

      expect(c.read(recordingProvider).elapsed, Duration.zero);
    });
  });

  // -------------------------------------------------------------------------
  // Derived / convenience providers
  // -------------------------------------------------------------------------
  group('Derived providers', () {
    test('isRecordingProvider reflects recording phase', () {
      final c = makeContainer();
      expect(c.read(isRecordingProvider), isFalse);

      c.read(recordingProvider.notifier).startRecording();
      expect(c.read(isRecordingProvider), isTrue);

      c.read(recordingProvider.notifier).stopRecording();
      expect(c.read(isRecordingProvider), isFalse);
    });

    test('audioLevelProvider reflects audioLevel', () {
      final c = makeContainer();
      expect(c.read(audioLevelProvider), 0.0);

      c.read(recordingProvider.notifier).startRecording();
      c.read(recordingProvider.notifier).updateAudioLevel(0.42);
      expect(c.read(audioLevelProvider), 0.42);
    });

    test('recordingElapsedProvider reflects elapsed', () async {
      final c = makeContainer();
      expect(c.read(recordingElapsedProvider), Duration.zero);

      c.read(recordingProvider.notifier).startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(
        c.read(recordingElapsedProvider).inSeconds,
        greaterThanOrEqualTo(1),
      );
    });

    test('recordingPhaseProvider reflects phase', () {
      final c = makeContainer();
      expect(c.read(recordingPhaseProvider), RecordingPhase.idle);

      c.read(recordingProvider.notifier).startRecording();
      expect(c.read(recordingPhaseProvider), RecordingPhase.recording);
    });
  });

  group('missingSelectedSpeechModelProvider', () {
    Future<SelectableSpeechModel?> read({
      SttSettings stt = const SttSettings(model: 'whisper-large-v3-turbo'),
      Set<String> downloaded = const {},
      bool scanned = true,
      String? downloadingModelId,
      bool parakeetInstalled = true,
    }) async {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings(
                onboarding: const OnboardingSettings(onboardingCompleted: true),
                stt: stt,
              ),
            ),
          ),
          modelDownloadProvider.overrideWith(
            () => _FakeModelDownloadNotifier(
              downloaded,
              scanned: scanned,
              downloadingModelId: downloadingModelId,
            ),
          ),
          parakeetDownloadProvider.overrideWith(
            () => _FakeParakeetDownloadNotifier(installed: parakeetInstalled),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);
      return c.read(missingSelectedSpeechModelProvider);
    }

    test('names the selected Whisper model when its file is missing', () async {
      final missing = await read();
      expect(missing?.modelId, 'whisper-large-v3-turbo');
    });

    test('nothing is missing before the initial disk scan has landed — the '
        'empty pre-scan set must not read as "missing"', () async {
      expect(await read(scanned: false), isNull);
    });

    test('nothing is missing once the model is on disk', () async {
      expect(await read(downloaded: {'whisper-large-v3-turbo'}), isNull);
    });

    test('nothing is missing while that model is downloading', () async {
      expect(await read(downloadingModelId: 'whisper-large-v3-turbo'), isNull);
    });

    test('cloud providers need no local model', () async {
      expect(
        await read(
          stt: const SttSettings(
            provider: 'OpenAI',
            model: 'whisper-large-v3-turbo',
          ),
        ),
        isNull,
      );
    });

    // UIA-MDL-GATE b: Parakeet is judged by its bundle, like Whisper by its
    // file, so the dock and the hotkey say so for it too.
    test('Parakeet without its bundle is missing', () async {
      final missing = await read(
        stt: const SttSettings(
          engine: 'parakeet',
          model: 'whisper-large-v3-turbo',
        ),
        downloaded: {'whisper-large-v3-turbo'},
        parakeetInstalled: false,
      );
      expect(missing?.engine, SpeechModelEngine.parakeet);
    });

    test('Parakeet with its bundle is not missing, whatever Whisper file '
        'is absent', () async {
      expect(
        await read(
          stt: const SttSettings(
            engine: 'parakeet',
            model: 'whisper-large-v3-turbo',
          ),
        ),
        isNull,
      );
    });
  });

  group('OomRecoveryNotifier', () {
    test('starts without a pending recovery', () {
      final c = makeContainer();
      final state = c.read(oomRecoveryPendingProvider);

      expect(state.pending, isFalse);
      expect(state.nextModelId, isNull);
      expect(state.hasCloudConfigured, isFalse);
      expect(state.isPermanentFail, isFalse);
    });

    test('showPending stores recovery context and clear resets it', () {
      final c = makeContainer();
      final notifier = c.read(oomRecoveryPendingProvider.notifier);

      notifier.showPending(
        nextModelId: 'whisper-small',
        hasCloudConfigured: true,
        isPermanentFail: false,
      );

      final pending = c.read(oomRecoveryPendingProvider);
      expect(pending.pending, isTrue);
      expect(pending.nextModelId, 'whisper-small');
      expect(pending.hasCloudConfigured, isTrue);
      expect(pending.isPermanentFail, isFalse);

      notifier.clear();
      final cleared = c.read(oomRecoveryPendingProvider);
      expect(cleared.pending, isFalse);
      expect(cleared.nextModelId, isNull);
      expect(cleared.hasCloudConfigured, isFalse);
      expect(cleared.isPermanentFail, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Session correlation ID
  // -------------------------------------------------------------------------
  group('Session correlation ID', () {
    test('sessionId is null when idle', () {
      final c = makeContainer();
      expect(c.read(recordingProvider).sessionId, isNull);
    });

    test('sessionId is generated on startRecording', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).startRecording();
      final sid = c.read(recordingProvider).sessionId;
      expect(sid, isNotNull);
      expect(sid, isNotEmpty);
    });

    test('sessionId format is base36-hex', () {
      final c = makeContainer();
      c.read(recordingProvider.notifier).startRecording();
      final sid = c.read(recordingProvider).sessionId!;
      // Format: <base36-timestamp>-<8-hex-random>
      expect(sid, contains('-'));
      final parts = sid.split('-');
      expect(parts.length, 2);
      // Second part is 8 hex characters.
      expect(parts[1].length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(parts[1]), isTrue);
    });

    test('sessionId persists through transcribing and done', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      final sid = c.read(recordingProvider).sessionId;
      n.stopRecording();
      expect(c.read(recordingProvider).sessionId, sid);
      n.completeTranscription('text');
      expect(c.read(recordingProvider).sessionId, sid);
    });

    test('sessionId is cleared on reset', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      expect(c.read(recordingProvider).sessionId, isNotNull);
      n.reset();
      expect(c.read(recordingProvider).sessionId, isNull);
    });

    test('sessionId is unique across sessions', () {
      final ids = <String>{};
      for (var i = 0; i < 20; i++) {
        final c = ProviderContainer();
        try {
          final n = c.read(recordingProvider.notifier);
          n.startRecording();
          final sid = c.read(recordingProvider).sessionId!;
          expect(
            ids.add(sid),
            isTrue,
            reason: 'Session ID $sid was not unique on iteration $i',
          );
        } finally {
          c.dispose();
        }
      }
    });

    test('recordingSessionIdProvider reflects sessionId', () {
      final c = makeContainer();
      expect(c.read(recordingSessionIdProvider), isNull);
      c.read(recordingProvider.notifier).startRecording();
      expect(c.read(recordingSessionIdProvider), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // Full lifecycle
  // -------------------------------------------------------------------------
  group('Full lifecycle', () {
    test('idle → recording → transcribing → done → reset → idle', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);

      expect(c.read(recordingProvider).phase, RecordingPhase.idle);

      n.startRecording();
      expect(c.read(recordingProvider).phase, RecordingPhase.recording);

      n.stopRecording();
      expect(c.read(recordingProvider).phase, RecordingPhase.transcribing);

      n.completeTranscription('result');
      expect(c.read(recordingProvider).phase, RecordingPhase.done);
      expect(c.read(recordingProvider).transcript, 'result');

      n.reset();
      expect(c.read(recordingProvider).phase, RecordingPhase.idle);
      expect(c.read(recordingProvider).transcript, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // pasteFailed — the flag `_handleDoneState` reads to skip the success
  // chime when the after-transcription paste attempt already played the
  // failure chime (see RecordingOrchestrator._reportPasteFailure).
  // -------------------------------------------------------------------------
  group('pasteFailed', () {
    test('defaults to false on a normal completion', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.completeTranscription('result');
      expect(c.read(recordingProvider).pasteFailed, isFalse);
    });

    test('is set when completeTranscription reports a paste failure', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.completeTranscription('result', pasteFailed: true);
      expect(c.read(recordingProvider).pasteFailed, isTrue);
      expect(c.read(recordingProvider).transcript, 'result');
    });

    test('resets to false on the next recording after a failed one', () {
      final c = makeContainer();
      final n = c.read(recordingProvider.notifier);
      n.startRecording();
      n.stopRecording();
      n.completeTranscription('first', pasteFailed: true);
      expect(c.read(recordingProvider).pasteFailed, isTrue);

      n.reset();
      n.startRecording();
      n.stopRecording();
      n.completeTranscription('second');
      expect(c.read(recordingProvider).pasteFailed, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // RecordingTargetNotifier
  // -------------------------------------------------------------------------
  group('recordingTargetProvider', () {
    test('defaults to clipboard', () {
      final c = makeContainer();
      expect(c.read(recordingTargetProvider), RecordingTarget.clipboard);
    });

    test('set() updates the readable state', () {
      final c = makeContainer();
      final n = c.read(recordingTargetProvider.notifier);

      n.set(RecordingTarget.quickNote);
      expect(c.read(recordingTargetProvider), RecordingTarget.quickNote);

      n.set(RecordingTarget.clipboard);
      expect(c.read(recordingTargetProvider), RecordingTarget.clipboard);
    });
  });
}

class _FakeParakeetDownloadNotifier extends ParakeetDownloadNotifier {
  _FakeParakeetDownloadNotifier({required this.installed});

  final bool installed;

  @override
  ParakeetDownloadState build() => ParakeetDownloadState(installed: installed);
}
