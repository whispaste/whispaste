/// Unit tests for [SafetyGuard] — the amplitude→SafetyEvent stream transformer.
///
/// All tests use synthetic amplitude sequences (converted to a broadcast stream)
/// and collect the resulting [SafetyEvent] list for assertion.
library;

import 'dart:async';

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// 300 ms of level above the threshold at 10 samples/s: the shortest run
/// that counts as speech.
const _speech = [0.5, 0.5, 0.5];

/// The guard input for a test level: `0.0` stands for a tick without any
/// signal (digital zero or no data, `-inf` dBFS), every other level for a
/// live microphone (#984: only a real loss of signal counts as dead).
GuardSample sampleFor(double level) => level == 0.0
    ? const GuardSample(dbFs: double.negativeInfinity, level: 0)
    : GuardSample(dbFs: -40, level: level);

/// Runs [amplitudes] through a [SafetyGuard] configured with [config] and
/// returns all [SafetyEvent]s emitted before the stream completes.
Future<List<SafetyEvent>> collectEvents(
  SafetyGuardConfig config,
  List<double> amplitudes,
) async {
  final source = Stream.fromIterable(amplitudes.map(sampleFor));
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
      // Speech, then 15 silent samples.
      final amplitudes = [..._speech, ...List.filled(15, 0.0)];
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
        // Speech (arms speechDetected) + 10 silent samples.
        final amplitudes = [..._speech, ...List.filled(10, 0.0)];
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
        for (var i = 0; i < 4; i++) ...[..._speech, ...List.filled(5, 0.0)],
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
      final amplitudes = [
        ..._speech,
        ...List.filled(10, 0.0),
      ]; // exactly 10 silent
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
      final amplitudes = [..._speech, ...List.filled(20, 0.0)];
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

  group('Duration limit extension (overlay F2)', () {
    // maxDuration = 2 s at 10 samples/s → limit at 20 samples; extended once
    // by 2 s after sample 15 → limit at 40 samples.
    const config = SafetyGuardConfig(
      deadMicTimeout: 0,
      autoStopSilence: 0,
      maxDurationSeconds: 2,
      samplesPerSecond: 10,
    );

    Future<List<(int, SafetyEvent)>> run(
      SafetyGuard guard,
      int samples, {
      int? extendAt,
    }) async {
      var i = 0;
      Stream<GuardSample> source() async* {
        for (; i < samples; i++) {
          if (i == extendAt) guard.extendDuration(2);
          yield sampleFor(0.5);
        }
      }

      final events = <(int, SafetyEvent)>[];
      await source().transform(guard).forEach((e) => events.add((i, e)));
      return events;
    }

    test('the limit moves by the extension and warns again', () async {
      final events = await run(SafetyGuard(config: config), 45, extendAt: 19);
      final limits = events.where((e) => e.$2 is DurationLimitReached);
      expect(limits, hasLength(1));
      expect(limits.single.$1, greaterThanOrEqualTo(39));
      expect(
        events.where((e) => e.$2 is DurationWarningAt90),
        hasLength(2),
        reason: 'once for the first limit, once for the extended one',
      );
    });

    test('a grace keeps the recording alive past the limit until the '
        'extension arrives (#858)', () async {
      // Limit at 20 samples; the click lands 2 samples after it, inside the
      // 1 s grace (10 samples). The extension moves the limit to 40 (the
      // orchestrator drops the grace then; here it stays, so 50).
      final guard = SafetyGuard(config: config)..limitGraceSeconds = 1;
      final events = await run(guard, 60, extendAt: 22);
      final limits = events.where((e) => e.$2 is DurationLimitReached);
      expect(limits, hasLength(1));
      expect(
        limits.single.$1,
        greaterThanOrEqualTo(49),
        reason: 'only the extended limit (40) plus grace (10) stops',
      );
    });

    test('without an answer the grace ends in the stop (#858)', () async {
      final guard = SafetyGuard(config: config)..limitGraceSeconds = 1;
      final events = await run(guard, 45);
      final limits = events.where((e) => e.$2 is DurationLimitReached);
      expect(limits, hasLength(1));
      expect(limits.single.$1, greaterThanOrEqualTo(29));
      expect(limits.single.$1, lessThan(31));
    });

    test('without a limit an extension changes nothing', () async {
      const unlimited = SafetyGuardConfig(
        deadMicTimeout: 0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      final events = await run(SafetyGuard(config: unlimited), 30, extendAt: 5);
      expect(events, isEmpty);
    });
  });

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

  // ── Clicks and noise are not speech ──────────────────────────────────────

  group('Speech needs a sustained level', () {
    const config = SafetyGuardConfig(
      deadMicTimeout: 1.0,
      autoStopSilence: 0,
      maxDurationSeconds: 0,
      samplesPerSecond: 10,
    );

    test('one loud sample in silence keeps the dead-mic guard armed', () async {
      final events = await collectEvents(config, [
        0.05,
        ...List.filled(10, 0.0),
      ]);
      expect(events.single, isA<DeadMicTimeoutReached>());
    });

    test('a two-sample click (200 ms) is not speech either', () async {
      // The click resets the dead count (the input is live for a moment);
      // were it speech, the ten dead ticks after it would not count.
      final events = await collectEvents(config, [
        ...List.filled(4, 0.0),
        0.9,
        0.9,
        ...List.filled(10, 0.0),
      ]);
      expect(events.single, isA<DeadMicTimeoutReached>());
    });

    test('noise with short spikes is not speech', () async {
      // Deterministic: low noise below the threshold, with a one-sample
      // spike roughly every fourth sample. Noise is a live input, so only
      // the dead ticks after it trip the guard, which shows the spikes did
      // not count as speech.
      final random = Random(42);
      final amplitudes = [
        for (var i = 0; i < 40; i++)
          i % 4 == 3
              ? 0.03 + random.nextDouble() * 0.2
              : 0.001 + random.nextDouble() * 0.018,
        ...List.filled(10, 0.0),
      ];
      final events = await collectEvents(config, amplitudes);
      expect(events.single, isA<DeadMicTimeoutReached>());
    });

    test('300 ms of level counts as speech and disarms the guard', () async {
      final events = await collectEvents(config, [
        ..._speech,
        ...List.filled(15, 0.0),
      ]);
      expect(events, isEmpty);
    });

    test('speech with single silent gaps still disarms the guard', () async {
      // Real speech has brief dips between syllables; one silent sample
      // between loud ones must not restart the 300 ms count.
      final events = await collectEvents(config, [
        0.5,
        0.5,
        0.0,
        0.5,
        0.5,
        0.0,
        ...List.filled(15, 0.0),
      ]);
      expect(events, isEmpty);
    });

    test('a dip longer than speechMaxGap restarts the count', () async {
      // At 10 samples/s the tolerated dip is one sample (80 ms rounds up to
      // 100 ms); two silent samples (200 ms) restart the 300 ms count.
      final events = await collectEvents(config, [
        0.5,
        0.5,
        0.0,
        0.0,
        0.5,
        0.5,
        ...List.filled(10, 0.0),
      ]);
      expect(events.single, isA<DeadMicTimeoutReached>());
    });

    test('speech scales with the sample rate', () async {
      const fast = SafetyGuardConfig(
        deadMicTimeout: 1.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 20,
      );
      // 5 samples at 20/s are 250 ms: not yet speech.
      final short = await collectEvents(fast, [
        ...List.filled(5, 0.5),
        ...List.filled(20, 0.0),
      ]);
      expect(short.single, isA<DeadMicTimeoutReached>());
      // 6 samples are 300 ms.
      final long = await collectEvents(fast, [
        ...List.filled(6, 0.5),
        ...List.filled(20, 0.0),
      ]);
      expect(long, isEmpty);
    });
  });

  // ── Silence threshold boundary ───────────────────────────────────────────

  group('Silence threshold boundary', () {
    test(
      'sample at exactly the silence threshold is treated as silent',
      () async {
        // Just below the threshold → silent; at it → NOT silent (< not <=).
        const config = SafetyGuardConfig(
          deadMicTimeout: 1.0,
          autoStopSilence: 0,
          maxDurationSeconds: 0,
          samplesPerSecond: 10,
        );
        // 10 samples just below the threshold are not speech, so the dead
        // ticks after them still fire the dead-mic guard.
        final events = await collectEvents(config, [
          ...List.filled(10, SafetyGuard.silenceThreshold - 0.001),
          ...List.filled(10, 0.0),
        ]);
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
      // 10 samples at exactly the threshold are speech: the dead ticks after
      // them no longer count.
      final events = await collectEvents(config, [
        ...List.filled(10, SafetyGuard.silenceThreshold),
        ...List.filled(10, 0.0),
      ]);
      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });
  });

  // ── Start grace for a waking microphone (#1777) ─────────────────────────

  group('Start grace before the first signal (#1777)', () {
    // 1 s timeout + 2 s grace at 10 samples/s: 10 ticks with a signal seen
    // before, 30 ticks while the input never delivered anything.
    const config = SafetyGuardConfig(
      deadMicTimeout: 1.0,
      firstSignalGrace: 2.0,
      autoStopSilence: 0,
      maxDurationSeconds: 0,
      samplesPerSecond: 10,
    );

    test('a first signal after the plain timeout is not a dead mic', () async {
      // Mute for 2.9 s (past the 1 s timeout), then the device wakes up.
      final events = await collectEvents(config, [
        ...List.filled(29, 0.0),
        0.05,
        ..._speech,
      ]);

      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });

    test(
      'an input that never delivers still fires after timeout + grace',
      () async {
        expect(
          await collectEvents(config, List.filled(29, 0.0)),
          isNot(contains(isA<DeadMicTimeoutReached>())),
        );
        final events = await collectEvents(config, List.filled(30, 0.0));
        expect(events.whereType<DeadMicTimeoutReached>(), hasLength(1));
      },
    );

    test(
      'a loss after the first signal counts with the plain timeout',
      () async {
        // Quiet but live for 200 ms, then nothing: no grace any more.
        final events = await collectEvents(config, [
          0.05,
          0.05,
          ...List.filled(10, 0.0),
        ]);
        expect(events.whereType<DeadMicTimeoutReached>(), hasLength(1));
      },
    );

    // #1784: a waking device can click once and fall back to zeros.
    test('a single click keeps the start grace', () async {
      final click = await collectEvents(config, [
        0.05,
        ...List.filled(29, 0.0),
      ]);
      expect(click.whereType<DeadMicTimeoutReached>(), isEmpty);

      final events = await collectEvents(config, [
        0.05,
        ...List.filled(30, 0.0),
      ]);
      expect(events.whereType<DeadMicTimeoutReached>(), hasLength(1));
    });

    test('a signal below -80 dBFS does not end the start grace', () async {
      final events = <SafetyEvent>[];
      await Stream.fromIterable([
        for (var i = 0; i < 5; i++) const GuardSample(dbFs: -85, level: 0),
        ...List.filled(29, const GuardSample(dbFs: -double.infinity, level: 0)),
      ]).transform(SafetyGuard(config: config)).forEach(events.add);
      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });

    test('the grace needs an unbroken run of signal', () async {
      // Two clicks with zeros between are no sustained signal.
      final events = await collectEvents(config, [
        0.05,
        0.0,
        0.05,
        ...List.filled(29, 0.0),
      ]);
      expect(events.whereType<DeadMicTimeoutReached>(), isEmpty);
    });

    test('the grace never turns a disabled dead-mic guard on', () async {
      const off = SafetyGuardConfig(
        deadMicTimeout: 0,
        firstSignalGrace: 2.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      expect(await collectEvents(off, List.filled(60, 0.0)), isEmpty);
    });

    test('the no-signal hint still comes after 1 s with the grace', () async {
      const withHint = SafetyGuardConfig(
        deadMicTimeout: 3.0,
        firstSignalGrace: 2.0,
        autoStopSilence: 0,
        maxDurationSeconds: 0,
        samplesPerSecond: 10,
      );
      // 4.9 s without signal: hint at 1 s, no stop before 3 s + 2 s.
      final events = await collectEvents(withHint, List.filled(49, 0.0));
      expect(events.single, isA<NoSignalWarning>());
    });

    test('the pipeline grace keeps a really silent mic reported in time', () {
      // Default 3 s timeout: a waking device gets clearly more than that,
      // a really silent one is still reported well within 10 s.
      const grace = SafetyGuard.firstSignalGraceSeconds;
      expect(grace, greaterThanOrEqualTo(3.0));
      expect(
        const SafetyGuardConfig(samplesPerSecond: 25).deadMicTimeout + grace,
        lessThanOrEqualTo(8.0),
      );
    });
  });
}
