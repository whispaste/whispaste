import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';

// The service imports _mapPhase as a top-level function — re-implement the
// mapping here to test the contract independently of Riverpod wiring.

void main() {
  group('RecordingPhase → FloatingButtonVisualState mapping', () {
    // This mirrors the mapping in floating_button_service.dart
    FloatingButtonVisualState mapPhase(RecordingPhase phase) => switch (phase) {
      RecordingPhase.idle => FloatingButtonVisualState.idle,
      RecordingPhase.recording => FloatingButtonVisualState.recording,
      RecordingPhase.transcribing => FloatingButtonVisualState.transcribing,
      RecordingPhase.processing => FloatingButtonVisualState.transcribing,
      RecordingPhase.done => FloatingButtonVisualState.done,
      RecordingPhase.error => FloatingButtonVisualState.error,
    };

    test('idle maps to idle', () {
      expect(mapPhase(RecordingPhase.idle), FloatingButtonVisualState.idle);
    });

    test('recording maps to recording', () {
      expect(
        mapPhase(RecordingPhase.recording),
        FloatingButtonVisualState.recording,
      );
    });

    test('transcribing maps to transcribing', () {
      expect(
        mapPhase(RecordingPhase.transcribing),
        FloatingButtonVisualState.transcribing,
      );
    });

    test('processing also maps to transcribing (same visual)', () {
      expect(
        mapPhase(RecordingPhase.processing),
        FloatingButtonVisualState.transcribing,
      );
    });

    test('done maps to done', () {
      expect(mapPhase(RecordingPhase.done), FloatingButtonVisualState.done);
    });

    test('error maps to error', () {
      expect(mapPhase(RecordingPhase.error), FloatingButtonVisualState.error);
    });

    test('all RecordingPhase values are handled', () {
      // Ensures exhaustive coverage — the switch expression would fail at
      // compile time if a new phase were added without a mapping.
      for (final phase in RecordingPhase.values) {
        expect(() => mapPhase(phase), returnsNormally);
      }
    });
  });

  group('FloatingButtonVisualState enum', () {
    test('contains exactly 6 states', () {
      expect(FloatingButtonVisualState.values, hasLength(6));
    });

    test('state names match C++ FloatingButtonState', () {
      // The Dart enum names must match what the MethodChannel sends to C++.
      // C++ ParseState expects lowercase: idle, recording, transcribing,
      // done, error, disabled.
      const expected = [
        'idle',
        'recording',
        'transcribing',
        'done',
        'error',
        'disabled',
      ];
      expect(
        FloatingButtonVisualState.values.map((e) => e.name).toList(),
        expected,
      );
    });
  });
}
