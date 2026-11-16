/// Stateless resilience policy for in-process whisper FFI failures.
///
/// The FFI-era analogue of [`SttGpuFallbackPolicy`] (which keys on the
/// subprocess exit-code [`SttExitKind`]). Pure and stateless — no Riverpod,
/// no I/O — so the notifier's recovery decisions stay unit-testable in
/// isolation.
library;

import 'whisper_engine.dart';

/// Decides how the notifier should react to a [WhisperFailureKind].
class WhisperResiliencePolicy {
  const WhisperResiliencePolicy();

  /// Returns `true` when [kind] is a GPU fault the app can recover from by
  /// re-running the transcription on CPU.
  ///
  /// [WhisperFailureKind.gpuCrash] and [WhisperFailureKind.gpuBackendLost]
  /// (once rebuilding the backend did not help) degrade to CPU.
  /// [WhisperFailureKind.oom]
  /// is deliberately excluded — out-of-memory is recovered by the orchestrator's
  /// `OomRecoveryHandler` (smaller model / cloud), not by a same-hardware CPU
  /// retry that would still not fit.
  bool shouldRetryOnCpu(WhisperFailureKind kind) =>
      kind == WhisperFailureKind.gpuCrash ||
      kind == WhisperFailureKind.gpuBackendLost;

  /// Returns `true` when [kind] means the GPU backend itself is unusable but a
  /// fresh context on the same hardware recovers it. The notifier then
  /// reloads the model on the same engine once before degrading to CPU.
  bool shouldRebuildBackend(WhisperFailureKind kind) =>
      kind == WhisperFailureKind.gpuBackendLost;
}
