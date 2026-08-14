// Regression test for the start/stop race that let a push-to-talk release
// silently no-op while `AudioServiceNotifier.startRecording()` was still in
// its async setup window (mic permission, input-routing override, HAL
// settle wait). The orphaned start would finish unsupervised and keep
// recording until some later, unrelated hotkey cycle happened to absorb it
// — producing multi-minute WAV files from a few-second press and, over many
// occurrences, unreleased capture resources across a long-running session.
//
// This test exercises the pure arbitration logic in isolation (no Flutter,
// no platform channels) so it stays fast and deterministic.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recording_start_stop_arbiter.dart';

void main() {
  group('RecordingStartStopArbiter', () {
    test('a start with no concurrent stop completes normally', () {
      final arbiter = RecordingStartStopArbiter();
      arbiter.beginStart();
      expect(arbiter.endStart(), isFalse);
    });

    test('a stop with no start in progress is a genuine no-op', () {
      final arbiter = RecordingStartStopArbiter();
      expect(arbiter.requestStopWhileNotRecording(), isFalse);
    });

    test('a stop that arrives while starting flags the start for abort', () {
      final arbiter = RecordingStartStopArbiter();
      arbiter.beginStart();

      // Simulates the hotkey release racing the still-pending async setup
      // (permission check / routing override / HAL settle wait): at this
      // point `state.isRecording` is still false, so the caller sees the
      // same "nothing to stop" no-op it always has — but the arbiter now
      // remembers to abort once setup finishes.
      expect(arbiter.requestStopWhileNotRecording(), isTrue);

      // The pending start must self-abort instead of reporting the
      // capture as active — this is what closes the leak: no orphaned
      // recording is left running for the caller to forget about.
      expect(arbiter.endStart(), isTrue);
    });

    test('the abort signal is consumed exactly once', () {
      final arbiter = RecordingStartStopArbiter();
      arbiter.beginStart();
      arbiter.requestStopWhileNotRecording();
      expect(arbiter.endStart(), isTrue);

      // A later, unrelated stop-while-idle must not still read as
      // "abort pending" — the flag must not leak across cycles.
      expect(arbiter.requestStopWhileNotRecording(), isFalse);
    });

    test('flags do not leak into the next start/stop cycle', () {
      final arbiter = RecordingStartStopArbiter();

      // First cycle: clean start, no race.
      arbiter.beginStart();
      expect(arbiter.endStart(), isFalse);

      // Second cycle: a genuine race — must be detected independently of
      // the first, unrelated cycle.
      arbiter.beginStart();
      expect(arbiter.requestStopWhileNotRecording(), isTrue);
      expect(arbiter.endStart(), isTrue);
    });

    test('a stop arriving after the start already finished is not queued', () {
      final arbiter = RecordingStartStopArbiter();
      arbiter.beginStart();
      expect(arbiter.endStart(), isFalse);

      // Once a start has finished, `state.isRecording` is true and the
      // real `stopRecording()` takes the normal (non-arbiter) path — the
      // arbiter must report nothing in flight for a caller that still
      // asks.
      expect(arbiter.requestStopWhileNotRecording(), isFalse);
    });
  });
}
