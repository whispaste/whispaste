/// Perceptual dBFS → visual-level mapper, the single level curve of WhisPaste.
///
/// Every live waveform reads its level through this mapper: the floating
/// overlay, the onboarding microphone test and the safety guard's silence
/// detection. One curve keeps the element the same everywhere (design
/// system rule: same element, same behaviour).
///
/// The input is the peak dBFS of one meter window ([AmplitudeFromPcm], 40 ms),
/// computed in Dart from 16-bit PCM on every platform, so the scale is the
/// same on macOS, Windows and Linux.
///
/// Curve: the window `[floorDb, ceilingDb] = [-60, -8]` is normalised to
/// `x ∈ [0, 1]` and bent with `x^1.5`. The exponent gives a soft knee above
/// the noise floor and keeps normal speech mid-range, with headroom so only
/// loud speech reaches the top:
///
/// | peak dBFS | level |
/// |---|---|
/// | -50 (room tone) | ≈ 0.08 |
/// | -40 (quiet) | ≈ 0.24 |
/// | -30 (soft speech) | ≈ 0.44 |
/// | -24 (normal speech) | ≈ 0.58 |
/// | -18 (clear speech) | ≈ 0.73 |
/// | -12 (loud) | ≈ 0.89 |
/// | ≥ -8 | 1.0 |
///
/// Defined zero-fallback for `double.negativeInfinity` and `double.nan`, so
/// silent frames and degenerate readings collapse to a clean resting level.
library;

import 'dart:math' as math;

/// Lower edge of the speech window in dBFS. At or below → `0.0`.
const double speechLevelFloorDb = -60.0;

/// Upper edge of the speech window in dBFS. At or above → `1.0`.
const double speechLevelCeilingDb = -8.0;

/// Exponent that bends the normalised window. Above 1 it softens the knee
/// over the noise floor and keeps normal speech mid-range.
const double speechLevelExponent = 1.5;

/// Maps raw peak dBFS values onto a normalised `[0.0, 1.0]` visual level.
class SpeechLevelMapper {
  /// Creates a mapper. The mapper is stateless — instances are
  /// interchangeable.
  const SpeechLevelMapper();

  /// Returns the normalised visual level for the given raw [dbFs] reading.
  double map(double dbFs) {
    if (dbFs.isNaN || dbFs <= speechLevelFloorDb) return 0.0;
    if (dbFs >= speechLevelCeilingDb) return 1.0;
    final x =
        (dbFs - speechLevelFloorDb) /
        (speechLevelCeilingDb - speechLevelFloorDb);
    return math.pow(x, speechLevelExponent).toDouble();
  }
}
