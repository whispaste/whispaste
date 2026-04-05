import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/recording/recording_state.dart';

// ---------------------------------------------------------------------------
// Helper: create a ProviderContainer for pure-logic tests (no widget needed).
// ---------------------------------------------------------------------------
ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
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
      const a = RecordingState(
        phase: RecordingPhase.done,
        transcript: 'hello',
      );
      const b = RecordingState(
        phase: RecordingPhase.done,
        transcript: 'hello',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains key fields', () {
      const s = RecordingState(phase: RecordingPhase.error, errorMessage: 'oh no');
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

      expect(c.read(recordingElapsedProvider).inSeconds, greaterThanOrEqualTo(1));
    });

    test('recordingPhaseProvider reflects phase', () {
      final c = makeContainer();
      expect(c.read(recordingPhaseProvider), RecordingPhase.idle);

      c.read(recordingProvider.notifier).startRecording();
      expect(c.read(recordingPhaseProvider), RecordingPhase.recording);
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
}
