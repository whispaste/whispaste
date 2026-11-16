/// Non-terminal no-signal hint of [SafetyGuard] (ticket, matrix 9.3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

/// The guard input for a test level: `0.0` stands for a tick without any
/// signal (digital zero or no data, `-inf` dBFS), every other level for a
/// live microphone (#984: only a real loss of signal counts as dead).
GuardSample _sampleFor(double level) => level == 0.0
    ? const GuardSample(dbFs: double.negativeInfinity, level: 0)
    : GuardSample(dbFs: -40, level: level);

Future<List<SafetyEvent>> _collect(
  SafetyGuardConfig config,
  List<double> amplitudes,
) async {
  final events = <SafetyEvent>[];
  await Stream.fromIterable(
    amplitudes.map(_sampleFor),
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

  group('only a real loss of signal counts (#984)', () {
    const config = SafetyGuardConfig(
      samplesPerSecond: sps,
      deadMicTimeout: 3.0,
      autoStopSilence: 2.0,
      maxDurationSeconds: 0,
    );

    Future<List<(int, SafetyEvent)>> indexed(List<GuardSample> samples) async {
      var i = -1;
      final events = <(int, SafetyEvent)>[];
      await Stream.fromIterable(samples)
          .map((s) {
            i++;
            return s;
          })
          .transform(SafetyGuard(config: config))
          .forEach((e) => events.add((i, e)));
      return events;
    }

    test('a steady -70 dBFS microphone triggers nothing', () async {
      // Below the level floor (the bar shows nothing), but a live input.
      final events = await indexed(
        List.filled(10 * sps, GuardSample.fromDbFs(-70)),
      );
      expect(events, isEmpty);
    });

    for (final (name, dbFs) in [
      ('NaN', double.nan),
      ('digital zero (-inf)', double.negativeInfinity),
    ]) {
      test('$name gives the hint at 1 s and dead-mic at 3 s', () async {
        final events = await indexed(
          List.filled(4 * sps, GuardSample.fromDbFs(dbFs)),
        );
        expect(events.map((e) => e.$2).toList(), [
          isA<NoSignalWarning>(),
          isA<DeadMicTimeoutReached>(),
        ]);
        expect(events[0].$1, sps - 1);
        expect(events[1].$1, 3 * sps - 1);
      });
    }

    test('the first signal after the hint is reported once', () async {
      final events = await indexed([
        ...List.filled(sps, GuardSample.fromDbFs(double.negativeInfinity)),
        ...List.filled(5, GuardSample.fromDbFs(-70)),
        ...List.filled(sps, GuardSample.fromDbFs(double.negativeInfinity)),
        ...List.filled(5, GuardSample.fromDbFs(-70)),
      ]);
      expect(events.map((e) => e.$2).toList(), [
        isA<NoSignalWarning>(),
        isA<SignalArrived>(),
      ]);
      expect(events[1].$1, sps);
    });

    test('a quiet live tick resets the dead count', () async {
      final events = await indexed([
        for (var i = 0; i < 6 * sps; i++)
          GuardSample.fromDbFs(
            i % (2 * sps) == 0 ? -75 : double.negativeInfinity,
          ),
      ]);
      expect(events.where((e) => e.$2 is DeadMicTimeoutReached), isEmpty);
    });
  });
}
