/// Too-quiet hint for a running recording (overlay, Maintainer decision 4).
///
/// Pure logic: the caller supplies the RMS level and the time, so the rule is
/// testable with an injected clock. Digital silence (`-inf`) is not counted
/// here; the signal-loss path ([SignalLossDetector]) owns that case.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RMS level below which the microphone counts as too quiet.
///
/// Starting value, not a measured one. It is to be calibrated by a
/// measurement series: quiet rooms, built-in and external microphones, normal
/// and soft speech, each on Windows, Linux and macOS. Until then a value well
/// below normal speech and above room tone is the intent.
const double quietMicRmsThresholdDbFs = -55.0;

/// How long the level has to stay below [quietMicRmsThresholdDbFs] before the
/// hint appears. Short enough to help, long enough that a pause between
/// sentences does not trigger it.
const Duration quietMicHoldDuration = Duration(seconds: 5);

/// Decides when the "microphone very quiet" hint is shown during a recording.
///
/// Feed every RMS reading with its time to [observe]. The hint turns on after
/// [hold] of continuous quiet and off as soon as the level comes back above
/// the threshold or goes to digital silence.
class QuietMicrophoneWatch {
  QuietMicrophoneWatch({
    this.threshold = quietMicRmsThresholdDbFs,
    this.hold = quietMicHoldDuration,
  });

  /// Level below which a reading counts as quiet, in dBFS.
  final double threshold;

  /// Continuous quiet needed before the hint shows.
  final Duration hold;

  DateTime? _quietSince;
  bool _hinting = false;

  /// Whether the hint is currently due.
  bool get hinting => _hinting;

  /// Feeds one RMS reading in dBFS taken at [now]. Returns `true` when the
  /// hint state changed, so the caller only rebuilds on a real change.
  bool observe(double rmsDbFs, DateTime now) {
    final before = _hinting;
    if (!rmsDbFs.isFinite || rmsDbFs >= threshold) {
      _quietSince = null;
      _hinting = false;
    } else {
      final since = _quietSince ??= now;
      if (now.difference(since) >= hold) _hinting = true;
    }
    return _hinting != before;
  }

  /// Clears the state for the next recording.
  void reset() {
    _quietSince = null;
    _hinting = false;
  }
}

/// Whether the current recording's microphone is too quiet. Written by the
/// audio service, read by the overlay.
class MicQuietController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool quiet) {
    state = quiet;
  }
}

final micQuietProvider = NotifierProvider<MicQuietController, bool>(
  MicQuietController.new,
);
