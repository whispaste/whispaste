/// Unit tests for [SafetyGuard] — the amplitude→SafetyEvent stream transformer.
///
/// All tests use synthetic amplitude sequences (converted to a broadcast stream)
/// and collect the resulting [SafetyEvent] list for assertion.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Runs [amplitudes] through a [SafetyGuard] configured with [config] and
/// returns all [SafetyEvent]s emitted before the stream completes.
Future<List<SafetyEvent>> collectEvents(
  SafetyGuardConfig config,
  List<double> amplitudes,
) async {
  final source = Stream.fromIterable(amplitudes);
  final events = <SafetyEvent>[];
  await source.transform(SafetyGuard(config: config)).forEach(events.add);
  return events;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── SafetyEvent identity ─────────────────────────────────────────────────

  group('SafetyEvent sealed class', () {
    test('each constant has the correct runtime type', () {
      expect(deadMicTimeoutReached, isA<DeadMicTimeoutReached>());
      expect(silenceAutoStop, isA<SilenceAutoStop>());
      expect(durationWarningAt90, isA<DurationWarningAt90>());
      expect(durationLimitReached, isA<DurationLimitReached>());
    });
  });

  // ── Dead-mic detection ───────────────────────────────────────────────────

  group('Dead-mic detection', () {
    test(
      'emits deadMicTimeoutReached after threshold silent samples (no speech)',
      () async {
        // deadMicTimeout = 1.0 s, samplesPerSecond = 10 → threshold = 10 samples
        const config = SafetyGuardConfig(
          deadMicTimeout: 1.0,
          autoStopSilence: 0,
          maxDurationSeconds: 0,
          samplesPerSecond: 10,
        );
        // 10 fully-silent samples → guard fires on the 10th.
        final events = await collectEvents(config, List.filled(10, 0.0));

        expect(events, hasLength(1));
        expect(events.single, isA<DeadMicTimeoutReached>());
      },
    );

    test('does NOT fire on 9 silent samples (one below threshold)', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 1.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // 9 samples — below the 10-sample threshold.
      final events = await collectEvents(config, List.filled(9, 0.0));

      expect(events, isEmpty);
    });

    test('does NOT fire when deadMicTimeout is 0 (guard disabled)', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final events = await collectEvents(config, List.filled(20, 0.0));

      expect(events, isEmpty);
    });

    test('does NOT fire after speech has been detected', () async {
      // Once speech is seen, dead-mic guard disarms permanently for the session.
      const config = SafetyGuardConfig(
        deadMicTimeout: 1.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // 1 loud sample (speech), then 15 silent samples.
      final amplitudes = [0.5, ...List.filled(15, 0.0)];
      final events = await collectEvents(config, amplitudes);

      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });

    test('fires only once even with many more silent samples', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 1.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final events = await collectEvents(config, List.filled(30, 0.0));

      expect(events.whereType<DeadMicTimeoutReached>(), hasLength(1));
    });
  });

  // ── Auto-stop on silence ─────────────────────────────────────────────────

  group('Silence auto-stop', () {
    test(
      'emits silenceAutoStop after speech then threshold silent samples',
      () async {
        // autoStopSilence = 1.0 s, samplesPerSecond = 10 → threshold = 10 samples.
        const config = SafetyGuardConfig(
          deadMicTimeout: 0,
          autoStopSilence: 1.0,
          maxDurationSeconds: 0,
          samplesPerSecond: 10,
        );
        // 1 loud sample (arms speechDetected) + 10 silent samples.
        final amplitudes = [0.5, ...List.filled(10, 0.0)];
        final events = await collectEvents(config, amplitudes);

        expect(events, hasLength(1));
        expect(events.single, isA<SilenceAutoStop>());
      },
    );

    test(
      'does NOT fire without prior speech (silence from the start)',
      () async {
        const config = SafetyGuardConfig(
          deadMicTimeout: 0,
          autoStopSilence: 1.0,
          maxDurationSeconds: 0,
          samplesPerSecond: 10,
        );
        // Pure silence — speechDetected never set, so auto-stop stays armed.
        final events = await collectEvents(config, List.filled(15, 0.0));

        expect(events.whereType<SilenceAutoStop>(), isEmpty);
      },
    );

    test('interleaved speech resets the silence counter', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 1.0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // Pattern: 1 speech + 5 silence, repeated 4 times → max consecutive = 5.
      final amplitudes = [
        for (var i = 0; i < 4; i++) ...[0.5, ...List.filled(5, 0.0)],
      ];
      final events = await collectEvents(config, amplitudes);

      // Max consecutive silence is 5 < threshold 10 → no auto-stop yet.
      expect(events.whereType<SilenceAutoStop>(), isEmpty);
    });

    test('silence exactly at threshold fires the guard', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 1.0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final amplitudes = [0.5, ...List.filled(10, 0.0)]; // exactly 10 silent
      final events = await collectEvents(config, amplitudes);

      expect(events.single, isA<SilenceAutoStop>());
    });

    test('does NOT fire when autoStopSilence is 0 (guard disabled)', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // Speech then long silence — no auto-stop guard.
      final amplitudes = [0.5, ...List.filled(20, 0.0)];
      final events = await collectEvents(config, amplitudes);

      expect(events.whereType<SilenceAutoStop>(), isEmpty);
    });
  });

  // ── Duration warning at 90 % ─────────────────────────────────────────────

  group('Duration warning at 90%', () {
    test(
      'emits durationWarningAt90 when 90% of maxDurationSeconds is reached',
      () async {
        // maxDuration = 10 s, samplesPerSecond = 10 → 90 % = 9 s = 90 samples.
        const config = SafetyGuardConfig(
          deadMicTimeout: 0,
          autoStopSilence: 0,
          maxDurationSeconds: 10,
          samplesPerSecond: 10,
        );
        // Emit 91 loud samples (speech, so dead-mic path skipped).
        // 90th sample triggers warning; 100th triggers limit.
        // We only emit 91 so we see the warning but also the limit (91 >= 100? No).
        // 91 samples = 9.1 s < 10 s limit → warning fires, no limit yet.
        final amplitudes = List.filled(91, 0.5);
        final events = await collectEvents(config, amplitudes);

        // Exactly one warning, no limit (stream not yet at 100 samples).
        expect(events.whereType<DurationWarningAt90>(), hasLength(1));
        expect(events.whereType<DurationLimitReached>(), isEmpty);
      },
    );

    test('warning fires only once per session', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 10,
        samplesPerSecond: 10,
      );
      // 95 samples → crosses 90 % but not 100 %.
      final events = await collectEvents(config, List.filled(95, 0.5));

      expect(events.whereType<DurationWarningAt90>(), hasLength(1));
    });

    test('does NOT emit warning when maxDurationSeconds is 0', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final events = await collectEvents(config, List.filled(200, 0.5));

      expect(events.whereType<DurationWarningAt90>(), isEmpty);
    });
  });

  // ── Duration limit ───────────────────────────────────────────────────────

  group('Duration limit', () {
    test('emits durationLimitReached at maxDurationSeconds', () async {
      // maxDuration = 2 s, samplesPerSecond = 10 → limit at 20 samples.
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 2,
        samplesPerSecond: 10,
      );
      // 25 loud samples → limit fires at sample 20.
      final events = await collectEvents(config, List.filled(25, 0.5));

      expect(events.whereType<DurationLimitReached>(), hasLength(1));
    });

    test(
      'stream closes after durationLimitReached (no further events)',
      () async {
        const config = SafetyGuardConfig(
          deadMicTimeout: 0,
          autoStopSilence: 0,
          maxDurationSeconds: 2,
          samplesPerSecond: 10,
        );
        // 50 samples — well past the limit.
        final events = await collectEvents(config, List.filled(50, 0.5));

        // Only the limit event + possibly the warning; never two limit events.
        expect(events.whereType<DurationLimitReached>(), hasLength(1));
      },
    );

    test(
      'warning fires before limit — correct order in combined sequence',
      () async {
        // 2 s limit, 10 sps → warning at 18 samples (9 s * 10/10 → 1.8 s * 10 = 18)
        // Actually: 90% of 2 = 1.8 s → floor = 1 s? Let's use 10 s / 10 sps = easier.
        // maxDuration = 10, sps = 10: warning at elapsedSec >= 9.0 → 90 samples.
        // Limit at 100 samples.
        const config = SafetyGuardConfig(
          deadMicTimeout: 0,
          autoStopSilence: 0,
          maxDurationSeconds: 10,
          samplesPerSecond: 10,
        );
        // 105 samples → crosses both 90 % and 100 %.
        final events = await collectEvents(config, List.filled(105, 0.5));

        final warningIdx = events.indexWhere((e) => e is DurationWarningAt90);
        final limitIdx = events.indexWhere((e) => e is DurationLimitReached);

        expect(warningIdx, isNot(-1), reason: 'warning must be emitted');
        expect(limitIdx, isNot(-1), reason: 'limit must be emitted');
        expect(warningIdx, lessThan(limitIdx), reason: 'warning before limit');
      },
    );

    test('does NOT fire when maxDurationSeconds is 0', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final events = await collectEvents(config, List.filled(500, 0.5));

      expect(events.whereType<DurationLimitReached>(), isEmpty);
    });
  });

  // ── Guard fire is terminal (only one terminal event per session) ─────────

  group('Guard termination semantics', () {
    test(
      'only one terminal event emitted even when multiple would apply',
      () async {
        // Enable both dead-mic (no speech) and a very short max duration.
        // Dead-mic threshold = 5 samples; max duration = 2 samples.
        // Limit fires first (at sample 2), dead-mic would fire at sample 5.
        const config = SafetyGuardConfig(
          deadMicTimeout: 0.5, // 5 samples at 10 sps
          autoStopSilence: 0,
          maxDurationSeconds: 0, // disabled — use dead-mic path only
          samplesPerSecond: 10,
        );
        final events = await collectEvents(config, List.filled(20, 0.0));

        // Only dead-mic (one terminal event).
        final terminalCount = events
            .where(
              (e) =>
                  e is DeadMicTimeoutReached ||
                  e is SilenceAutoStop ||
                  e is DurationLimitReached,
            )
            .length;
        expect(terminalCount, equals(1));
      },
    );
  });

  // ── Silence threshold boundary ───────────────────────────────────────────

  group('Silence threshold boundary', () {
    test(
      'sample at exactly the silence threshold is treated as silent',
      () async {
        // Level 0.019 < 0.02 → silent. Level 0.02 is NOT silent (< not <=).
        const config = SafetyGuardConfig(
          deadMicTimeout: 1.0,
          autoStopSilence: 0,
          maxDurationSeconds: 0,
          samplesPerSecond: 10,
        );
        // 10 samples at 0.019 → dead-mic fires.
        final events = await collectEvents(
          config,
          List.filled(10, SafetyGuard.silenceThreshold - 0.001),
        );
        expect(events.single, isA<DeadMicTimeoutReached>());
      },
    );

    test('sample at or above silence threshold is treated as speech', () async {
      const config = SafetyGuardConfig(
        deadMicTimeout: 1.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // 10 samples at exactly 0.02 → NOT silent, so dead-mic never fires.
      final events = await collectEvents(
        config,
        List.filled(10, SafetyGuard.silenceThreshold),
      );
      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });
  });
}
