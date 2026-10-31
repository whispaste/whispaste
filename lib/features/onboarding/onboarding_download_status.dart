/// The speech-model download as the onboarding shows it: one status for the
/// footer on every page, the practice gate and the remaining time.
///
/// Pure logic on purpose. The downloader states are mapped here, and the time
/// estimate comes only from measured throughput, so it can be tested without a
/// clock or a network.
library;

import '../../services/model_download_service.dart' show DownloadPhase;
import '../../services/stt_parakeet/parakeet_download_service.dart'
    show ParakeetDownloadPhase;

/// What the footer shows, independent of the engine.
enum OnboardingDownloadPhase { idle, running, verifying, ready, failed }

/// The download status of the first-run setup.
class OnboardingDownloadStatus {
  const OnboardingDownloadStatus({
    required this.phase,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.remaining,
  });

  final OnboardingDownloadPhase phase;
  final int bytesDone;
  final int bytesTotal;

  /// Estimated time left. Null until the measured throughput is stable, never
  /// an invented number.
  final Duration? remaining;

  /// Progress from 0 to 1, or 0 while the total is unknown.
  double get fraction =>
      bytesTotal > 0 ? (bytesDone / bytesTotal).clamp(0.0, 1.0) : 0;

  /// "Ausprobieren" is open only once the model is ready to use.
  bool get practiceUnlocked => phase == OnboardingDownloadPhase.ready;
}

/// Whether onboarding's first-dictation page is open for a try, and why not.
///
/// The page is locked while a local speech model is not ready: the user sees
/// why and what happens next before the first press, and a press records
/// nothing. A cloud provider needs no local model, so it is never locked here
/// (a cloud provider without a key fails at the press, as it does everywhere).
enum PracticeGate {
  /// Trying works: the model is ready, or no local model is needed.
  open,

  /// The model is downloading or being verified; unlocks by itself.
  loading,

  /// The download failed; the page offers a retry.
  failed,

  /// No model on disk and no download running; the page offers the load.
  missing,
}

/// The try-out lock rule as a pure function of the engine and the download.
PracticeGate practiceGateFor({
  required bool localEngine,
  required OnboardingDownloadStatus status,
}) {
  if (!localEngine) return PracticeGate.open;
  return switch (status.phase) {
    OnboardingDownloadPhase.ready => PracticeGate.open,
    OnboardingDownloadPhase.running ||
    OnboardingDownloadPhase.verifying => PracticeGate.loading,
    OnboardingDownloadPhase.failed => PracticeGate.failed,
    OnboardingDownloadPhase.idle => PracticeGate.missing,
  };
}

/// Maps the Whisper downloader's phase. An idle downloader with an installed
/// model counts as ready, so an already set-up install never waits.
OnboardingDownloadStatus onboardingStatusFromWhisper({
  required DownloadPhase phase,
  required int bytesDone,
  required int bytesTotal,
  required bool installed,
  Duration? remaining,
}) => _map(
  phase: switch (phase) {
    DownloadPhase.idle =>
      installed ? OnboardingDownloadPhase.ready : OnboardingDownloadPhase.idle,
    DownloadPhase.downloading ||
    DownloadPhase.extracting => OnboardingDownloadPhase.running,
    DownloadPhase.verifying => OnboardingDownloadPhase.verifying,
    DownloadPhase.done => OnboardingDownloadPhase.ready,
    DownloadPhase.error => OnboardingDownloadPhase.failed,
  },
  bytesDone: bytesDone,
  bytesTotal: bytesTotal,
  remaining: remaining,
);

/// Maps the Parakeet downloader's phase, see [onboardingStatusFromWhisper].
OnboardingDownloadStatus onboardingStatusFromParakeet({
  required ParakeetDownloadPhase phase,
  required int bytesDone,
  required int bytesTotal,
  required bool installed,
  Duration? remaining,
}) => _map(
  phase: switch (phase) {
    ParakeetDownloadPhase.idle =>
      installed ? OnboardingDownloadPhase.ready : OnboardingDownloadPhase.idle,
    ParakeetDownloadPhase.downloading => OnboardingDownloadPhase.running,
    ParakeetDownloadPhase.verifying => OnboardingDownloadPhase.verifying,
    ParakeetDownloadPhase.done => OnboardingDownloadPhase.ready,
    ParakeetDownloadPhase.error => OnboardingDownloadPhase.failed,
  },
  bytesDone: bytesDone,
  bytesTotal: bytesTotal,
  remaining: remaining,
);

OnboardingDownloadStatus _map({
  required OnboardingDownloadPhase phase,
  required int bytesDone,
  required int bytesTotal,
  required Duration? remaining,
}) => OnboardingDownloadStatus(
  phase: phase,
  bytesDone: bytesDone,
  bytesTotal: bytesTotal,
  // A remaining time is shown only while a transfer runs.
  remaining: phase == OnboardingDownloadPhase.running ? remaining : null,
);

/// Measures the download speed from byte samples and estimates the time left.
///
/// The rate is the moving average over [window] of the samples. An estimate is
/// given only when the samples span at least [minSpan] and the rate is stable:
/// the rate of the first half of the window and of the second half must agree
/// within a factor of [stableRatio]. Before that there is no estimate at all,
/// so the footer shows only percent and megabytes.
class DownloadThroughput {
  DownloadThroughput({
    this.window = const Duration(seconds: 10),
    this.minSpan = const Duration(seconds: 3),
    this.stableRatio = 1.6,
  });

  final Duration window;
  final Duration minSpan;
  final double stableRatio;

  final List<(Duration at, int bytes)> _samples = [];

  /// Records the bytes received so far at [at] on the caller's clock.
  void record(Duration at, int bytes) {
    if (_samples.isNotEmpty && at < _samples.last.$1) return;
    if (_samples.isNotEmpty && bytes < _samples.last.$2) return;
    _samples.add((at, bytes));
    final cutoff = at - window;
    // Keep one sample at or before the cutoff as the window's start point.
    while (_samples.length > 2 && _samples[1].$1 <= cutoff) {
      _samples.removeAt(0);
    }
  }

  /// Bytes per second over the window, or null without a stable measurement.
  double? get bytesPerSecond {
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;
    final span = last.$1 - first.$1;
    if (span < minSpan) return null;
    final rate = (last.$2 - first.$2) / span.inMicroseconds * 1e6;
    if (rate <= 0 || !_isStable()) return null;
    return rate;
  }

  /// Time left for [bytesLeft] at the measured rate, or null.
  Duration? remainingFor(int bytesLeft) {
    final rate = bytesPerSecond;
    if (rate == null || bytesLeft <= 0) return null;
    return Duration(microseconds: (bytesLeft / rate * 1e6).round());
  }

  bool _isStable() {
    final first = _samples.first;
    final last = _samples.last;
    final mid = _samples[_samples.length ~/ 2];
    final firstSpan = (mid.$1 - first.$1).inMicroseconds;
    final secondSpan = (last.$1 - mid.$1).inMicroseconds;
    if (firstSpan <= 0 || secondSpan <= 0) return false;
    final firstRate = (mid.$2 - first.$2) / firstSpan;
    final secondRate = (last.$2 - mid.$2) / secondSpan;
    if (firstRate <= 0 || secondRate <= 0) return false;
    final ratio = firstRate > secondRate
        ? firstRate / secondRate
        : secondRate / firstRate;
    return ratio <= stableRatio;
  }
}
