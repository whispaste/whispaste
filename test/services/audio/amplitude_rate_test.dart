/// Regression test for the amplitude-stream rate constants in
/// `audio_service.dart`.
///
/// The amplitude stream's poll interval and the integer "samples per second"
/// used by `SafetyGuard` must stay in sync — when they drift apart, all
/// SafetyGuard timers (max-duration, dead-mic, silence-auto-stop) feed off
/// the wrong rate and fire 2.5× too early. See the orchestrator's
/// `SafetyGuardConfig(samplesPerSecond: amplitudeSamplesPerSecond)` call.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

void main() {
  test('amplitudeSamplesPerSecond matches amplitudePollInterval', () {
    final derivedHz = 1000 / amplitudePollInterval.inMilliseconds;
    expect(
      amplitudeSamplesPerSecond,
      closeTo(derivedHz, 0.5),
      reason:
          'amplitudeSamplesPerSecond ($amplitudeSamplesPerSecond Hz) is out of '
          'sync with amplitudePollInterval '
          '(${amplitudePollInterval.inMilliseconds} ms ≈ $derivedHz Hz). '
          'Update both together.',
    );
  });

  test('SafetyGuard at amplitudeSamplesPerSecond fires duration limit at the '
      'configured second — not 2.5× too early', () async {
    const maxDur = 2;
    const config = SafetyGuardConfig(
      deadMicTimeout: 0,
      autoStopSilence: 0,
      maxDurationSeconds: maxDur,
      samplesPerSecond: amplitudeSamplesPerSecond,
    );

    // Feed enough non-silent samples to cross the limit by exactly one
    // sample. With a correctly-tuned rate, the limit hits at
    // `maxDur * amplitudeSamplesPerSecond` samples.
    const limitSamples = maxDur * amplitudeSamplesPerSecond;
    final amplitudes = List.filled(limitSamples + 5, 0.5);

    final events = <SafetyEvent>[];
    await Stream.fromIterable(
      amplitudes,
    ).transform(SafetyGuard(config: config)).forEach(events.add);

    // We expect exactly: 1 warning at 90 % + 1 terminal limit event.
    expect(
      events.whereType<DurationLimitReached>(),
      hasLength(1),
      reason:
          'Expected the duration-limit guard to fire once after '
          '$limitSamples samples (= $maxDur s at '
          '$amplitudeSamplesPerSecond Hz).',
    );
  });
}
