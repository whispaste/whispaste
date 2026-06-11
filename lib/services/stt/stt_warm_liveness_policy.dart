/// Bounded retry-with-grace policy for warm STT liveness checks.
///
/// When the STT server is already "warm" (state=ready, process alive) but a
/// single health-check twitches (returns false), this policy retries up to
/// [maxAttempts] times before declaring the server dead and requesting a
/// restart.  This avoids tearing down a healthy warm server on a transient
/// 500 ms hiccup at recording start.
///
/// Deliberately pure: no Riverpod dependency, no [http.Client] import.
/// The caller supplies an injectable [checkOnce] callback and an optional
/// [clock] factory so tests can run without real I/O or real time.
library;

import 'dart:async';

/// Result returned by [SttWarmLivenessPolicy.checkWithGrace].
enum WarmLivenessResult {
  /// Server responded healthy within the grace budget — no restart needed.
  healthy,

  /// Server did not respond healthy after exhausting all attempts — restart
  /// required.
  needsRestart,
}

/// Bounded retry policy for warm-path liveness checks.
///
/// Default parameters give a grace budget of ≈ 2 s:
///   - 3 attempts, each with a 500 ms HTTP timeout (inside [checkOnce])
///   - 300 ms back-off between attempts
///
/// On well-responding hardware the first attempt almost always succeeds,
/// so the common path adds zero latency versus the old one-shot check.
class SttWarmLivenessPolicy {
  /// Creates a policy with the given parameters.
  ///
  /// [clock] is optional and used only by tests that want to observe timing
  /// behaviour without real wall-clock progression.
  SttWarmLivenessPolicy({
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  }) : _clock = clock ?? _defaultClock;

  /// How many times to attempt [checkOnce] before giving up.
  final int maxAttempts;

  /// Pause between consecutive failed attempts.
  final Duration retryDelay;

  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now();

  /// Runs [checkOnce] up to [maxAttempts] times, pausing [retryDelay] between
  /// failures.
  ///
  /// Returns [WarmLivenessResult.healthy] as soon as one attempt succeeds.
  /// Returns [WarmLivenessResult.needsRestart] if every attempt fails.
  ///
  /// [checkOnce] must return `true` when the server is healthy and `false`
  /// on any error or non-200 response.  The caller is responsible for the
  /// HTTP timeout inside [checkOnce].
  Future<WarmLivenessResult> checkWithGrace(
    Future<bool> Function() checkOnce,
  ) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final _ = _clock(); // allow fake clock injection to be observable
      final ok = await checkOnce();
      if (ok) return WarmLivenessResult.healthy;
      if (attempt < maxAttempts) {
        await Future<void>.delayed(retryDelay);
      }
    }
    return WarmLivenessResult.needsRestart;
  }
}
