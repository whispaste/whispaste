/// Growth review GR-007 (decision 8b): the end of a dictation counts as user
/// activity for the nudge gate. A nudge must not open right after a paste,
/// even when the user dictated into another application and never touched
/// the WhisPaste window.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/nudge_gate.dart';

/// Recording notifier whose phase a test can drive. The derived phase provider
/// and the gate read it exactly as in the app.
final class _FakeRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void setPhase(RecordingPhase phase) => state = state.copyWith(phase: phase);
}

void main() {
  final start = DateTime(2026, 10, 19, 12);

  late DateTime now;
  late ProviderContainer container;
  late _FakeRecording recording;

  setUp(() {
    now = start;
    container = ProviderContainer(
      overrides: [
        nudgeClockProvider.overrideWithValue(() => now),
        recordingProvider.overrideWith(_FakeRecording.new),
      ],
    );
    addTearDown(container.dispose);
    recording = container.read(recordingProvider.notifier) as _FakeRecording;
  });

  group('nudgeGateProvider and the end of a dictation', () {
    test('a finished dictation restarts the idle window', () {
      final gate = container.read(nudgeGateProvider);

      // The app itself has been idle for a long time before the dictation.
      now = start.add(const Duration(minutes: 1));
      recording
        ..setPhase(RecordingPhase.recording)
        ..setPhase(RecordingPhase.transcribing)
        ..setPhase(RecordingPhase.done);

      // Without the fix the gate would allow a nudge right here (idle 60 s).
      final decision = gate.decide();
      expect(decision, isA<NudgeWait>());
      expect((decision as NudgeWait).after, kNudgeIdleThreshold);
    });

    test('a nudge opens 30 s after the dictation ended, not earlier', () {
      final gate = container.read(nudgeGateProvider);

      now = start.add(const Duration(minutes: 1));
      recording
        ..setPhase(RecordingPhase.recording)
        ..setPhase(RecordingPhase.done);

      now = start.add(const Duration(minutes: 1, seconds: 29));
      expect(gate.decide(), isA<NudgeWait>());

      now = start.add(const Duration(minutes: 1, seconds: 30));
      expect(gate.decide(), isA<NudgeAllow>());
    });

    test('a running dictation blocks nudges, busy steps are not an end', () {
      final gate = container.read(nudgeGateProvider);

      now = start.add(const Duration(minutes: 1));
      recording
        ..setPhase(RecordingPhase.recording)
        ..setPhase(RecordingPhase.transcribing)
        ..setPhase(RecordingPhase.refining);

      final decision = gate.decide();
      expect(decision, isA<NudgeWait>());
      expect((decision as NudgeWait).after, kNudgeBusyRecheck);
    });
  });
}
