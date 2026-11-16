/// Countdown to the automatic duration-limit stop (overlay decision 3).
///
/// Pure logic. The limit itself is enforced by [SafetyGuard]
/// (`DurationLimitReached`); this only decides when the overlay shows the
/// remaining time.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a recording runs on past the limit while the notice card can
/// still extend it (#858). Equal to `SafetyGuard.limitGraceSeconds`.
const int durationLimitGraceSeconds = 3;

/// The countdown appears this long before the limit.
const Duration durationCountdownWindow = Duration(seconds: 30);

/// Remaining time until the limit when the countdown is due, else `null`.
///
/// `maxDurationSeconds` follows the stored setting: `0` means no limit, which
/// never shows a countdown. Once the limit is reached the stop takes over, so
/// no countdown is returned for zero or negative remainders, except for the
/// [graceSeconds] after the limit, where it reads zero.
Duration? remainingUntilDurationLimit({
  required Duration elapsed,
  required int maxDurationSeconds,
  Duration window = durationCountdownWindow,
  int graceSeconds = 0,
}) {
  if (maxDurationSeconds <= 0) return null;
  final remaining = Duration(seconds: maxDurationSeconds) - elapsed;
  if (remaining > window) return null;
  if (remaining <= Duration.zero) {
    // Inside the grace the card still stands, at zero, so the click that
    // arrives at the limit has a target; after it the stop has taken over.
    return -remaining < Duration(seconds: graceSeconds) ? Duration.zero : null;
  }
  return remaining;
}

/// Seconds the running recording's duration limit was extended by (the
/// notice card's "Record {n} more min", overlay F2); 0 when not extended. At most one
/// extension per recording. Written by the orchestrator, read by the overlay.
class DurationLimitExtensionController extends Notifier<int> {
  @override
  int build() => 0;

  void set(int seconds) {
    state = seconds;
  }
}

final durationLimitExtensionProvider =
    NotifierProvider<DurationLimitExtensionController, int>(
      DurationLimitExtensionController.new,
    );
