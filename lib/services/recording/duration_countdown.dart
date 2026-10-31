/// Countdown to the automatic duration-limit stop (overlay decision 3).
///
/// Pure logic. The limit itself is enforced by [SafetyGuard]
/// (`DurationLimitReached`); this only decides when the overlay shows the
/// remaining time.
library;

/// The countdown appears this long before the limit.
const Duration durationCountdownWindow = Duration(seconds: 30);

/// Remaining time until the limit when the countdown is due, else `null`.
///
/// `maxDurationSeconds` follows the stored setting: `0` means no limit, which
/// never shows a countdown. Once the limit is reached the stop takes over, so
/// no countdown is returned for zero or negative remainders.
Duration? remainingUntilDurationLimit({
  required Duration elapsed,
  required int maxDurationSeconds,
  Duration window = durationCountdownWindow,
}) {
  if (maxDurationSeconds <= 0) return null;
  final remaining = Duration(seconds: maxDurationSeconds) - elapsed;
  if (remaining <= Duration.zero || remaining > window) return null;
  return remaining;
}
