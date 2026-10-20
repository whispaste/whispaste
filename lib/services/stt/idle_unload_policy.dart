/// Decides how long the on-device speech model stays loaded after a use.
///
/// An explicit `stt.idleTimeoutMinutes` (0 = always, n = minutes) is always
/// honored. For [kSttIdleAutomatic] the app keeps the model loaded when the
/// machine has room for it, with the thresholds below:
///
/// * total RAM ≥ model memory + [kAlwaysLoadedTotalReserveMB], and
/// * available RAM ≥ model memory + [kAlwaysLoadedAvailableReserveMB]
///   (checked on the latest reading; skipped if none exists yet).
///
/// Otherwise the model unloads after [kSttIdleFallbackMinutes]. The memory
/// pressure monitor unloads it under pressure in any case, so a default of
/// "always loaded" cannot hold RAM that other apps need.
library;

import 'memory_pressure.dart';

/// `stt.idleTimeoutMinutes` value for automatic mode (the settings default).
const int kSttIdleAutomatic = -1;

/// Idle minutes used for automatic mode when the machine is short on memory,
/// and by smart mode when automatic is set (it has no always-loaded mode).
const int kSttIdleFallbackMinutes = 5;

const int kAlwaysLoadedTotalReserveMB = 4096;
const int kAlwaysLoadedAvailableReserveMB = 2048;

/// Minutes to keep the model after its last use; 0 keeps it loaded.
int resolveIdleUnloadMinutes({
  required int configured,
  required MemorySnapshot? snapshot,
  required int? modelMB,
}) {
  if (configured != kSttIdleAutomatic) return configured;
  if (snapshot == null || modelMB == null) return kSttIdleFallbackMinutes;
  final roomy =
      snapshot.totalMB >= modelMB + kAlwaysLoadedTotalReserveMB &&
      snapshot.availableMB >= modelMB + kAlwaysLoadedAvailableReserveMB;
  return roomy ? 0 : kSttIdleFallbackMinutes;
}
