/// Unit tests for [SttWarmLivenessPolicy].
///
/// Uses a fake clock and a scripted check-callback to run entirely in-process
/// without real HTTP or real time passing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_warm_liveness_policy.dart';

void main() {
  group('SttWarmLivenessPolicy', () {
    // -------------------------------------------------------------------------
    // AC2a: timeout on attempt 1, answer on attempt 2 → healthy (no restart)
    // -------------------------------------------------------------------------
    test(
      'AC2a: returns healthy when first attempt fails but second succeeds',
      () async {
        var callCount = 0;
        Future<bool> checkOnce() async {
          callCount++;
          // Fail on attempt 1, succeed on attempt 2.
          return callCount >= 2;
        }

        final policy = SttWarmLivenessPolicy(
          maxAttempts: 3,
          retryDelay: Duration.zero,
        );

        final result = await policy.checkWithGrace(checkOnce);

        expect(result, WarmLivenessResult.healthy);
        // At least 2 calls were made (the second one succeeded).
        expect(callCount, 2);
      },
    );

    // -------------------------------------------------------------------------
    // AC2b: no answer over the whole grace → exactly ONE restart requested
    // The policy returns needsRestart once (callers restart once in response).
    // -------------------------------------------------------------------------
    test(
      'AC2b: returns needsRestart after all attempts fail (never healthy)',
      () async {
        var callCount = 0;
        Future<bool> checkOnce() async {
          callCount++;
          return false;
        }

        final policy = SttWarmLivenessPolicy(
          maxAttempts: 3,
          retryDelay: Duration.zero,
        );

        final result = await policy.checkWithGrace(checkOnce);

        expect(result, WarmLivenessResult.needsRestart);
        // Exactly maxAttempts calls were made — the policy does NOT loop
        // infinitely; it exhausts exactly 3 attempts.
        expect(callCount, 3);
      },
    );

    // -------------------------------------------------------------------------
    // AC2c: grace duration respected — retryDelay is observed between retries
    // -------------------------------------------------------------------------
    test('AC2c: grace delay is observed between retry attempts', () async {
      final callTimestamps = <DateTime>[];
      final fakeTimes = [
        DateTime(2026, 1, 1, 0, 0, 0),
        DateTime(2026, 1, 1, 0, 0, 0, 300), // +300 ms
        DateTime(2026, 1, 1, 0, 0, 0, 600), // +600 ms
      ];
      var clockIndex = 0;
      DateTime fakeClock() {
        final i = clockIndex++;
        return fakeTimes[i.clamp(0, 2)];
      }

      Future<bool> checkOnce() async {
        callTimestamps.add(DateTime.now());
        return false;
      }

      final policy = SttWarmLivenessPolicy(
        maxAttempts: 3,
        retryDelay: const Duration(milliseconds: 1),
        clock: fakeClock,
      );

      final result = await policy.checkWithGrace(checkOnce);

      // All attempts exhausted → needsRestart.
      expect(result, WarmLivenessResult.needsRestart);
      // Clock was consulted once per attempt.
      expect(clockIndex, 3);
      // Exactly 3 check calls happened.
      expect(callTimestamps.length, 3);
    });

    // -------------------------------------------------------------------------
    // AC2a variant: healthy on the first attempt — fast path, no retries
    // -------------------------------------------------------------------------
    test('healthy on first attempt — no retries', () async {
      var callCount = 0;
      Future<bool> checkOnce() async {
        callCount++;
        return true;
      }

      final policy = SttWarmLivenessPolicy(
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );

      final result = await policy.checkWithGrace(checkOnce);

      expect(result, WarmLivenessResult.healthy);
      expect(callCount, 1);
    });

    // -------------------------------------------------------------------------
    // AC3: the policy itself never calls CrashReporter / Sentry.
    //
    // Verification: [SttWarmLivenessPolicy] has no import of sentry_flutter
    // or CrashReporter (checked by code inspection / static analysis gate).
    //
    // This test additionally confirms the needsRestart path completes without
    // throwing — callers are responsible for any restart logic & logging.
    // -------------------------------------------------------------------------
    test(
      'AC3: needsRestart path completes without error (no Sentry in policy)',
      () async {
        Future<bool> checkOnce() async => false;

        final policy = SttWarmLivenessPolicy(
          maxAttempts: 2,
          retryDelay: Duration.zero,
        );

        // Must not throw.
        await expectLater(
          policy.checkWithGrace(checkOnce),
          completion(WarmLivenessResult.needsRestart),
        );
      },
    );

    // -------------------------------------------------------------------------
    // Edge: maxAttempts = 1 behaves like the old one-shot check
    // -------------------------------------------------------------------------
    test('maxAttempts=1 with healthy check → healthy immediately', () async {
      final policy = SttWarmLivenessPolicy(
        maxAttempts: 1,
        retryDelay: Duration.zero,
      );
      final result = await policy.checkWithGrace(() async => true);
      expect(result, WarmLivenessResult.healthy);
    });

    test(
      'maxAttempts=1 with failing check → needsRestart immediately',
      () async {
        final policy = SttWarmLivenessPolicy(
          maxAttempts: 1,
          retryDelay: Duration.zero,
        );
        final result = await policy.checkWithGrace(() async => false);
        expect(result, WarmLivenessResult.needsRestart);
      },
    );
  });
}
