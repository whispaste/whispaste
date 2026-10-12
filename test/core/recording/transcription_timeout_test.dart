import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart'
    show transcriptionStuckBudget;

void main() {
  const floor = Duration(minutes: 5);

  group('transcriptionStuckBudget', () {
    test('short recordings keep the floor unchanged', () {
      expect(
        transcriptionStuckBudget(const Duration(seconds: 10), floor: floor),
        floor,
      );
      expect(
        transcriptionStuckBudget(const Duration(minutes: 1), floor: floor),
        floor,
      );
    });

    test('scales with the audio length above the floor', () {
      // 3 × 10 min = 30 min, well above the 5 min floor.
      expect(
        transcriptionStuckBudget(const Duration(minutes: 10), floor: floor),
        const Duration(minutes: 30),
      );
    });

    test('a 60-minute recording gets three hours', () {
      expect(
        transcriptionStuckBudget(const Duration(minutes: 60), floor: floor),
        const Duration(hours: 3),
      );
    });

    test('the floor wins exactly at the crossover point', () {
      // 3 × 100 s = 300 s = 5 min: both branches agree.
      expect(
        transcriptionStuckBudget(const Duration(seconds: 100), floor: floor),
        floor,
      );
      expect(
        transcriptionStuckBudget(const Duration(seconds: 101), floor: floor),
        const Duration(seconds: 303),
      );
    });

    test('zero or negative audio returns the floor', () {
      expect(transcriptionStuckBudget(Duration.zero, floor: floor), floor);
      expect(
        transcriptionStuckBudget(const Duration(seconds: -4), floor: floor),
        floor,
      );
    });

    test('the floor is a parameter, so tests can shrink it', () {
      expect(
        transcriptionStuckBudget(
          Duration.zero,
          floor: const Duration(milliseconds: 50),
        ),
        const Duration(milliseconds: 50),
      );
    });
  });
}
