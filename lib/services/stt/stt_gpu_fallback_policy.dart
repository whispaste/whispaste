/// Stateless GPU-fallback policy for whisper-server exits.
library;

import 'stt_exit_classifier.dart';

/// Determines whether a whisper-server exit kind warrants a CPU retry.
///
/// Stateless and pure — no Riverpod dependencies.
class SttGpuFallbackPolicy {
  const SttGpuFallbackPolicy();

  /// Returns `true` when [kind] represents a GPU-related fatal that can be
  /// recovered by restarting on CPU.
  ///
  /// - [SttExitKind.gpuFatal]      → true (CUDA / Vulkan fatal abort)
  /// - [SttExitKind.dllMissing]    → true (wrong binary variant for GPU)
  /// - [SttExitKind.dllEntryPoint] → true (wrong binary variant for GPU)
  /// - [SttExitKind.heapCorruption]→ true (memory access violation, GPU-induced)
  /// - all others                  → false
  bool shouldRetryOnCpu(SttExitKind kind) {
    return switch (kind) {
      SttExitKind.gpuFatal => true,
      SttExitKind.dllMissing => true,
      SttExitKind.dllEntryPoint => true,
      SttExitKind.heapCorruption => true,
      _ => false,
    };
  }
}
