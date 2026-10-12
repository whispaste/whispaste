/// Discrete steps for the "Max Recording Duration" slider.
///
/// The stored setting (`behavior.maxRecordDuration`) stays a plain number of
/// seconds, `0` meaning Unlimited. The slider works on step indices: index
/// `kRecordDurationUnlimitedIndex` (the rightmost one) is Unlimited, every
/// index before it is one entry of [kRecordDurationStepSeconds].
library;

/// Finite limits in seconds, ascending: 30 s, 1-10 min, 15-20 min, 30-60 min.
const List<int> kRecordDurationStepSeconds = [
  30,
  60,
  120,
  180,
  240,
  300,
  360,
  420,
  480,
  540,
  600,
  900,
  1200,
  1800,
  2700,
  3600,
];

/// Index of the Unlimited step, always the last one.
final int kRecordDurationUnlimitedIndex = kRecordDurationStepSeconds.length;

/// Number of slider positions: all finite steps plus Unlimited.
final int kRecordDurationStepCount = kRecordDurationUnlimitedIndex + 1;

/// Seconds stored for the Unlimited step.
const int kRecordDurationUnlimitedSeconds = 0;

/// Stored seconds for the slider position [index]. Out-of-range indices are
/// clamped, so the last position is always Unlimited.
int recordDurationSecondsAt(int index) {
  if (index >= kRecordDurationUnlimitedIndex) {
    return kRecordDurationUnlimitedSeconds;
  }
  return kRecordDurationStepSeconds[index < 0 ? 0 : index];
}

/// Slider position that represents the stored [seconds].
///
/// `0` and negative values are Unlimited. Any other value, including legacy
/// values off the step grid such as 90 s or 150 s, maps to the nearest finite
/// step; on a tie the shorter limit wins. Does not change the stored value.
int recordDurationStepIndex(int seconds) {
  if (seconds <= 0) return kRecordDurationUnlimitedIndex;
  var best = 0;
  var bestDistance = (kRecordDurationStepSeconds[0] - seconds).abs();
  for (var i = 1; i < kRecordDurationStepSeconds.length; i++) {
    final distance = (kRecordDurationStepSeconds[i] - seconds).abs();
    if (distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}
