/// Non-terminal no-signal hint of [SafetyGuard] (ticket, matrix 9.3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

Future<List<SafetyEvent>> _collect(
  SafetyGuardConfig config,
  List<double> amplitudes,
) async {
  final events = <SafetyEvent>[];
  await Stream.fromIterable(
    amplitudes,
  ).transform(SafetyGuard(config: config)).forEach(events.add);
  return events;
}

void main() {
  // 25 samples per second, the production rate.
  const sps = 25;

  test(
    'emits NoSignalWarning once after 1 s of silence, before dead-mic',
    () async {
      const config = SafetyGuardConfig(
        samplesPerSecond: sps,
        deadMicTimeout: 3.0,
        maxDurationSeconds: 0,
      );
      // 3 s of silence: hint at 1 s, dead-mic at 3 s.
      final events = await _collect(config, List.filled(3 * sps, 0.0));

      expect(events, hasLength(2));
      expect(events[0], isA<NoSignalWarning>());
      expect(events[1], isA<DeadMicTimeoutReached>());
    },
  );

  test(
    'hint is not repeated and the stream stays open until dead-mic',
    () async {
      const config = SafetyGuardConfig(
        samplesPerSecond: sps,
        deadMicTimeout: 3.0,
        maxDurationSeconds: 0,
      );
      final events = await _collect(config, List.filled(2 * sps, 0.0));

      // Only the hint: the recording is not stopped before the dead-mic timeout.
      expect(events, hasLength(1));
      expect(events.single, isA<NoSignalWarning>());
    },
  );

  test('no hint when a signal arrives within the first second', () async {
    const config = SafetyGuardConfig(
      samplesPerSecond: sps,
      deadMicTimeout: 3.0,
      maxDurationSeconds: 0,
    );
    // 300 ms of level is speech (SafetyGuard.speechMinDuration).
    final amplitudes = [
      ...List.filled(10, 0.0),
      ...List.filled(8, 0.3),
      ...List.filled(40, 0.0),
    ];
    final events = await _collect(config, amplitudes);

    expect(events.whereType<NoSignalWarning>(), isEmpty);
  });

  test('no hint when dead-mic detection is disabled', () async {
    const config = SafetyGuardConfig(
      samplesPerSecond: sps,
      deadMicTimeout: 0,
      maxDurationSeconds: 0,
    );
    final events = await _collect(config, List.filled(3 * sps, 0.0));

    expect(events, isEmpty);
  });

  test('no hint when dead-mic would fire at the same moment', () async {
    const config = SafetyGuardConfig(
      samplesPerSecond: sps,
      deadMicTimeout: 1.0,
      maxDurationSeconds: 0,
    );
    final events = await _collect(config, List.filled(sps, 0.0));

    expect(events, hasLength(1));
    expect(events.single, isA<DeadMicTimeoutReached>());
  });

  test('no hint once speech was detected, even after a long pause', () async {
    const config = SafetyGuardConfig(
      samplesPerSecond: sps,
      deadMicTimeout: 3.0,
      autoStopSilence: 0,
      maxDurationSeconds: 0,
    );
    final amplitudes = [...List.filled(8, 0.4), ...List.filled(2 * sps, 0.0)];
    final events = await _collect(config, amplitudes);

    expect(events.whereType<NoSignalWarning>(), isEmpty);
  });
}
