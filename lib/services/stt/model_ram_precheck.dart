/// Pre-load RAM check for the on-device speech engine (decision 9a,
/// 2026-10-25, finding 23).
///
/// Before a local model is loaded, its estimated RAM need is compared with the
/// free memory the OS reports. Only a clear shortfall counts: the caller asks
/// the user, and never blocks. Unknown free memory or an unknown estimate never
/// counts as short.
library;

import '../../core/config/settings_enums.dart' show OnDeviceEngine;
import '../hardware_info_service.dart' show sttModelVramMB;
import '../stt_parakeet/parakeet_model_registry.dart'
    show parakeetModelTotalBytes;
import 'memory_pressure.dart';

/// Extra headroom above the free memory before a load counts as clearly short.
/// macOS reports free memory only as a whole percent of RAM (`memory_pressure
/// -Q`), so the reading is off by up to 1 % of RAM. Up to 51 GB that is at most
/// 512 MB, so the margin absorbs the reading's granularity and a near miss
/// never triggers the question.
const int kModelRamPrecheckMarginMB = 512;

const int _bytesPerMB = 1024 * 1024;

/// Estimated RAM in MB that loading [modelId] under [engine] needs, or null
/// when the model has no estimate.
///
/// Whisper uses [sttModelVramMB]: those are already the conservative weight
/// plus scratch figures, and the CPU path holds the same weights in RAM.
/// Parakeet ships as fixed files, so their total size is the estimate.
int? onDeviceRamEstimateMB({
  required OnDeviceEngine engine,
  required String modelId,
}) {
  return switch (engine) {
    OnDeviceEngine.whisper => sttModelVramMB[modelId],
    OnDeviceEngine.parakeet =>
      (parakeetModelTotalBytes + _bytesPerMB - 1) ~/ _bytesPerMB,
  };
}

/// True only when both figures are known and the estimate exceeds the free
/// memory plus [kModelRamPrecheckMarginMB].
bool ramClearlyShort({
  required int? estimateMB,
  required MemorySnapshot? snapshot,
}) {
  if (estimateMB == null || snapshot == null) return false;
  return estimateMB > snapshot.availableMB + kModelRamPrecheckMarginMB;
}
