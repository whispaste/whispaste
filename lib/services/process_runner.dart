import 'dart:io';

/// Injectable abstraction over [Process.start].
///
/// Exists solely to make [SttServiceNotifier._start] testable without
/// spawning a real subprocess. The system implementation delegates directly;
/// tests supply a fake.
abstract class ProcessRunner {
  const ProcessRunner();

  Future<Process> start(String executable, List<String> arguments);
}

class SystemProcessRunner extends ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(executable, arguments, mode: ProcessStartMode.normal);
}
