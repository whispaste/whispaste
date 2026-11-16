import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_overlay/overlay_start_feedback.dart';

/// Briefing criterion 4: the start feedback equals the real microphone state.
/// The recording phase is entered before the microphone is open, so the
/// overlay must show the preparing state until capture actually runs.
void main() {
  group('showsStartingFeedback', () {
    test('recording phase before the first sample shows preparing', () {
      expect(
        showsStartingFeedback(
          phase: RecordingPhase.recording,
          firstSampleSeen: false,
        ),
        isTrue,
      );
    });

    test('recording phase after the first sample shows the live state', () {
      expect(
        showsStartingFeedback(
          phase: RecordingPhase.recording,
          firstSampleSeen: true,
        ),
        isFalse,
      );
    });

    test('other phases never show the preparing state', () {
      for (final phase in RecordingPhase.values) {
        if (phase == RecordingPhase.recording) continue;
        expect(
          showsStartingFeedback(phase: phase, firstSampleSeen: false),
          isFalse,
          reason: '$phase must not be affected by the microphone state',
        );
      }
    });
  });
}
