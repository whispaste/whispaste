/// Countdown before the duration limit (overlay decision 3): when it is due,
/// and that the flag reaches the render side. Time is passed in, nothing waits.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/recording/duration_countdown.dart';

void main() {
  group('remainingUntilDurationLimit', () {
    test('the window is 30 seconds', () {
      expect(durationCountdownWindow, const Duration(seconds: 30));
    });

    test('no limit configured (0) never shows a countdown', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(hours: 1),
          maxDurationSeconds: 0,
        ),
        isNull,
      );
    });

    test('before the last 30 seconds there is no countdown', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(seconds: 89),
          maxDurationSeconds: 120,
        ),
        isNull,
      );
    });

    test('the countdown starts exactly 30 seconds before the limit', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(seconds: 90),
          maxDurationSeconds: 120,
        ),
        const Duration(seconds: 30),
      );
    });

    test('the remaining time counts down inside the window', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(seconds: 100),
          maxDurationSeconds: 120,
        ),
        const Duration(seconds: 20),
      );
    });

    test('at and after the limit the stop takes over, no countdown', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(seconds: 120),
          maxDurationSeconds: 120,
        ),
        isNull,
      );
      expect(
        remainingUntilDurationLimit(
          elapsed: const Duration(seconds: 125),
          maxDurationSeconds: 120,
        ),
        isNull,
      );
    });

    test('a short limit below the window counts down from its start', () {
      expect(
        remainingUntilDurationLimit(
          elapsed: Duration.zero,
          maxDurationSeconds: 30,
        ),
        const Duration(seconds: 30),
      );
    });
  });

  test('the countdown flag survives the snapshot map, for the render side', () {
    const snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      label: '',
      elapsed: '0:25',
      countdown: true,
    );
    final restored = FloatingOverlaySnapshot.fromMap(snapshot.toMap());
    expect(restored.countdown, isTrue);
    expect(
      FloatingOverlaySnapshot.fromMap(const <String, dynamic>{}).countdown,
      isFalse,
    );
  });
}
