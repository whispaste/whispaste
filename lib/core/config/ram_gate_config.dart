/// RAM-gate threshold resolution with test-override support.
///
/// Production defaults are [kMinRamMB] (8192) and [kRamCheckThresholdMB]
/// (7500). These can be lowered for test runs on low-RAM machines (e.g. the
/// 5.8-GB CI VM or the 4-GB Pi) by passing `--dart-define` when running
/// `flutter test`:
///
/// ```sh
/// flutter test \
///   --dart-define=WHISPASTE_TEST_RAM_MIN_MB=4096 \
///   --dart-define=WHISPASTE_TEST_RAM_THRESHOLD_MB=3500
/// ```
///
/// The override has **no effect** on release builds where the dart-define
/// flags are not set — the production defaults remain unchanged.
library;

import 'package:whispaste/services/hardware_info_service.dart' as hw;

// ---------------------------------------------------------------------------
// Compile-time dart-define knobs (test-only, never set in release builds).
// ---------------------------------------------------------------------------

const int _kEnvMinRamMB = int.fromEnvironment(
  'WHISPASTE_TEST_RAM_MIN_MB',
  defaultValue: 0,
);

const int _kEnvThresholdMB = int.fromEnvironment(
  'WHISPASTE_TEST_RAM_THRESHOLD_MB',
  defaultValue: 0,
);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Resolves the active RAM-gate thresholds.
///
/// Returns the production defaults ([hw.kMinRamMB] = 8192,
/// [hw.kRamCheckThresholdMB] = 7500) unless an explicit override is present:
///
/// - **`--dart-define`** at build/test time:
///   `WHISPASTE_TEST_RAM_MIN_MB` / `WHISPASTE_TEST_RAM_THRESHOLD_MB`
/// - **Direct injection** via [testMinRamMB] / [testThresholdMB] — for unit
///   tests only; must NOT be used in production code paths.
///
/// Priority (highest wins): direct injection → dart-define → production default.
({int minRamMB, int thresholdMB}) resolveRamThresholds({
  // ignore: invalid_use_of_visible_for_testing_member
  int? testMinRamMB,
  // ignore: invalid_use_of_visible_for_testing_member
  int? testThresholdMB,
}) {
  final min =
      testMinRamMB ?? (_kEnvMinRamMB > 0 ? _kEnvMinRamMB : hw.kMinRamMB);
  final threshold =
      testThresholdMB ??
      (_kEnvThresholdMB > 0 ? _kEnvThresholdMB : hw.kRamCheckThresholdMB);
  return (minRamMB: min, thresholdMB: threshold);
}
