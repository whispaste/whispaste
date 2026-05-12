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
