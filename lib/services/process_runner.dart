import 'dart:io';

/// Injectable abstraction over [Process.start].
///
/// Exists solely to make [SttServerStateNotifier._start] testable without
/// spawning a real subprocess. The system implementation delegates directly;
/// tests supply a fake.
abstract class ProcessRunner {
  const ProcessRunner();

  /// Spawns [executable] with [arguments].
  ///
  /// [workingDirectory] sets the child's current directory. For whisper-server
  /// this MUST be the directory the binary and its sibling DLLs live in
  /// (`sttDir()`): the server resolves its ggml compute-backend DLLs at runtime
  /// relative to the process working directory / DLL search path. Without it,
  /// an MSIX-packaged launch on Windows fails to find the runtime DLLs and the
  /// process aborts with `STATUS_DLL_NOT_FOUND` (0xC0000135) even though every
  /// DLL is present on disk (FLUTTER_WHISPASTE-A0, GTX 650 Kepler).
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class SystemProcessRunner extends ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.normal,
  );
}
