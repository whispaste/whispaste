/// Perceptual dBFS → visual-level mapper for the floating-overlay waveform.
///
/// Translates a raw dBFS reading (logarithmic, ≤ 0 dB) into a normalised
/// visual level in `[0.0, 1.0]` by linearly remapping the perceptual speech
/// window `[floorDb, ceilingDb] = [-50.0, -3.0]` to `[0.0, 1.0]` and hard
/// clamping outside that window.
///
/// The mapper is intentionally minimal:
/// - No platform branches.
/// - No `sqrt` / amplitude conversions.
/// - Defined zero-fallback for `double.negativeInfinity` and `double.nan`,
///   so silent mic frames and degenerate readings collapse to a clean
///   resting level rather than propagating poisoned values downstream.
library;

/// Lower edge of the perceptual speech window in dBFS.
///
/// Readings at or below this level map to a visual level of `0.0`.
const double speechLevelFloorDb = -50.0;

/// Upper edge of the perceptual speech window in dBFS.
///
/// Readings at or above this level map to a visual level of `1.0`.
const double speechLevelCeilingDb = -3.0;

/// Maps raw dBFS values onto a normalised `[0.0, 1.0]` visual level using a
/// pure linear remap of the `[speechLevelFloorDb, speechLevelCeilingDb]`
/// window.
class SpeechLevelMapper {
  /// Creates a mapper. The mapper is stateless — instances are
  /// interchangeable.
  const SpeechLevelMapper();

  /// Returns the normalised visual level for the given raw [dbFs] reading.
  ///
  /// Behaviour:
  /// - `dbFs <= speechLevelFloorDb` → `0.0`
  /// - `dbFs >= speechLevelCeilingDb` → `1.0`
  /// - In-between: linear interpolation between `0.0` and `1.0`.
  /// - `double.negativeInfinity` and `double.nan` → `0.0`.
  double map(double dbFs) {
    if (dbFs.isNaN || dbFs == double.negativeInfinity) {
      return 0.0;
    }
    if (dbFs <= speechLevelFloorDb) {
      return 0.0;
    }
    if (dbFs >= speechLevelCeilingDb) {
      return 1.0;
    }
    return (dbFs - speechLevelFloorDb) /
        (speechLevelCeilingDb - speechLevelFloorDb);
  }
}
