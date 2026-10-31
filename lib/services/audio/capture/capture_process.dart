/// Child-process runner for the capture folder on Linux and Windows.
///
/// Kept out of `capture_dir.dart` on purpose: on macOS that file calls libc in
/// process, because the Mac App Store sandbox blocks child processes. The MAS
/// symbol scan covers `capture_dir.dart`, so the spawn lives here.
library;

import 'dart:io';
import 'dart:isolate';

/// Default runner: `Process.run` on its own isolate. A `fork()`+`exec()` that
/// deadlocks wedges the thread it runs on (see `_runProcessGuarded` in
/// `gpu_info.dart`). On a separate isolate the timeout in `_runOk` still fires,
/// and the recording start path stays responsive.
Future<ProcessResult> runCaptureProcess(
  String executable,
  List<String> arguments,
) => Isolate.run(() => Process.run(executable, arguments));
