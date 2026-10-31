/// Pure exit-code classifier for whisper-server subprocesses.
///
/// No Riverpod dependencies — can be tested in isolation.
library;

import 'dart:io';

/// Classified kind of a whisper-server subprocess exit.
///
/// - [modelLoad]      Exit code 3 — whisper_init_from_file failed.
/// - [dllMissing]     Windows 0xC0000135 — STATUS_DLL_NOT_FOUND.
/// - [dllEntryPoint]  Windows 0xC0000139 — STATUS_ENTRYPOINT_NOT_FOUND.
/// - [gpuFatal]       Windows 0xC0000409 — STATUS_STACK_BUFFER_OVERRUN /
///                    CUDA fatal abort.
/// - [heapCorruption] Windows 0xC0000005 — STATUS_ACCESS_VIOLATION.
/// - [other]          Any other exit code.
enum SttExitKind {
  modelLoad,
  dllMissing,
  dllEntryPoint,
  gpuFatal,
  heapCorruption,
  other,
}

/// Maps a whisper-server process [exitCode] to a [SttExitKind].
///
/// Only the five Windows NTSTATUS codes listed in the spec are classified;
/// all others map to [SttExitKind.other]. Pure — no side-effects.
SttExitKind classifySttExitCode(int exitCode) {
  // Exit code 3: whisper_init_from_file failed (all platforms).
  if (exitCode == 3) return SttExitKind.modelLoad;

  if (!Platform.isWindows) return SttExitKind.other;

  // Windows NTSTATUS codes (reported as negative signed 32-bit ints by Dart).
  //   0xC0000135 = STATUS_DLL_NOT_FOUND       = -1073741515
  //   0xC0000139 = STATUS_ENTRYPOINT_NOT_FOUND = -1073741511
  //   0xC0000409 = STATUS_STACK_BUFFER_OVERRUN = -1073740791
  //   0xC0000005 = STATUS_ACCESS_VIOLATION     = -1073741819
  return switch (exitCode) {
    -1073741515 => SttExitKind.dllMissing,
    -1073741511 => SttExitKind.dllEntryPoint,
    -1073740791 => SttExitKind.gpuFatal,
    -1073741819 => SttExitKind.heapCorruption,
    _ => SttExitKind.other,
  };
}

/// Why a [SttExitKind.modelLoad] (exit code 3) failure happened, refined by
/// the server's own stderr rather than the exit code alone.
///
/// - [fileUnreadable] whisper.cpp could not even open the model file
///   (`whisper_init_from_file…: failed to open '<path>'`). The binary started
///   fine; the file at the given path was unreachable *from the server
///   process*. This is NOT an ABI drift — a different binary variant
///   (vulkan→cpu) cannot fix a path/access fault, so the recovery
///   orchestrator must not treat it as such. Field repro: FLUTTER_WHISPASTE-A0
///   (MSIX child process could not see the model under the virtualised
///   `%APPDATA%\Roaming` path).
/// - [abiMismatch] the file opened but the whisper context failed to
///   initialise — the classic binary/model ABI drift between server versions.
enum ModelLoadFailureCause { fileUnreadable, abiMismatch }

/// Marker whisper.cpp prints when [`whisper_init_from_file_with_params_no_state`]
/// cannot open the model file. Lower-cased substring match keeps it robust
/// against the surrounding function-name prefix and path.
const String _failedToOpenMarker = 'failed to open';

/// Refines an exit-code-3 model-load failure using the captured [stderrLines].
///
/// Defaults to [ModelLoadFailureCause.abiMismatch] — the historical
/// behaviour — and only downgrades to [ModelLoadFailureCause.fileUnreadable]
/// when the server explicitly reports it could not open the model file. Pure;
/// no side-effects.
ModelLoadFailureCause classifyModelLoadFailure(Iterable<String> stderrLines) {
  for (final line in stderrLines) {
    if (line.toLowerCase().contains(_failedToOpenMarker)) {
      return ModelLoadFailureCause.fileUnreadable;
    }
  }
  return ModelLoadFailureCause.abiMismatch;
}
