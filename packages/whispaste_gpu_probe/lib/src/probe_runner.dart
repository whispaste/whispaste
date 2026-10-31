/// ProbeRunner — subprocess launcher with wall-clock deadline + heartbeat.
///
/// Starts an engine subprocess via an injectable [ProcessLauncher] seam,
/// drains stdout/stderr, and kills the process if no progress is observed
/// within [heartbeatTimeout] **or** if the total run exceeds
/// [startupDeadline].
///
/// The hang-detection contract:
///   - "Progress" = any byte arriving on stdout **or** stderr.
///   - If the last progress timestamp is more than [heartbeatTimeout] ago,
///     the process is killed and [timedOut] is set to `true`.
///   - If the total elapsed wall-clock time exceeds [startupDeadline],
///     the process is killed and [timedOut] is set to `true`.
///
/// Both deadlines are injectable so tests can use tiny durations (e.g.
/// 1 ms) and never block on real wall-clock time.
///
/// Conceptual model: mirrors `SttServerStateNotifier` with
/// `stt_heartbeat_timeout` / `stt_startup_deadline` from the main app.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Injectable seam types
// ---------------------------------------------------------------------------

/// Result of launching a subprocess.
///
/// Carries the OS-level process handle so [ProbeRunner] can kill it on
/// timeout, plus the live stdout and stderr streams.
class ProcessStartResult {
  const ProcessStartResult({
    required this.process,
    required this.stdout,
    required this.stderr,
  });

  /// The live process handle. [ProbeRunner] calls [Process.kill] on timeout.
  final Process process;

  /// Decoded (UTF-8) stdout lines emitted by the process.
  final Stream<String> stdout;

  /// Decoded (UTF-8) stderr lines emitted by the process.
  final Stream<String> stderr;
}

/// Injectable subprocess launcher seam.
///
/// Production code uses [defaultProcessLauncher]; tests supply a
/// [FakeProcessLauncher] that never blocks.
typedef ProcessLauncher =
    Future<ProcessStartResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

/// Production launcher — wraps [Process.start] directly.
Future<ProcessStartResult> defaultProcessLauncher(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  return ProcessStartResult(
    process: process,
    stdout: process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
    stderr: process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );
}

// ---------------------------------------------------------------------------
// Named injectable deadline/heartbeat constants
// ---------------------------------------------------------------------------

/// Maximum total wall-clock duration before a candidate is killed as [hung].
///
/// Covers the Kepler-Vulkan scenario: the engine loads fully but then stalls
/// indefinitely with no output. This is the hard outer bound.
///
/// Override by passing a custom value to [ProbeRunner] in tests.
const Duration kProbeStartupDeadline = Duration(minutes: 3);

/// Maximum silence interval (no stdout/stderr bytes) before the process is
/// killed as [hung].
///
/// A healthy engine emits at least one progress line per this interval.
/// A stalled Kepler-Vulkan candidate produces zero output after model-load.
///
/// Override by passing a custom value to [ProbeRunner] in tests.
const Duration kProbeHeartbeatTimeout = Duration(seconds: 30);

// ---------------------------------------------------------------------------
// Runner output
// ---------------------------------------------------------------------------

/// Raw output from a [ProbeRunner] run.
///
/// All fields consumed by [classifyOutcome] in `outcome_classifier.dart`.
class ProbeRunResult {
  const ProbeRunResult({
    required this.exitCode,
    required this.stderrTail,
    required this.durationMs,
    required this.timedOut,
  });

  /// Process exit code, or `null` when the process failed to start.
  final int? exitCode;

  /// Last [ProbeRunner.stderrTailLines] lines of stderr, joined by `\n`.
  final String stderrTail;

  /// Wall-clock duration of the run in milliseconds.
  final int durationMs;

  /// `true` when the process was killed due to a deadline or heartbeat miss.
  final bool timedOut;
}

// ---------------------------------------------------------------------------
// ProbeRunner
// ---------------------------------------------------------------------------

/// Runs an engine subprocess and enforces wall-clock deadline + heartbeat.
///
/// Inject [launcher], [startupDeadline], and [heartbeatTimeout] to make tests
/// fully deterministic without real wall-clock sleeps.
class ProbeRunner {
  const ProbeRunner({
    this.launcher = defaultProcessLauncher,
    this.startupDeadline = kProbeStartupDeadline,
    this.heartbeatTimeout = kProbeHeartbeatTimeout,
    this.stderrTailLines = 20,
  });

  /// Injectable process launcher seam (default: [defaultProcessLauncher]).
  final ProcessLauncher launcher;

  /// Hard outer deadline for the entire run.
  final Duration startupDeadline;

  /// Maximum allowed silence between any stdout/stderr bytes.
  final Duration heartbeatTimeout;

  /// Number of trailing stderr lines to capture for post-mortem.
  final int stderrTailLines;

  /// Starts [executable] with [arguments] in [workingDirectory] and waits
  /// for it to finish or be killed by the hang-detection logic.
  ///
  /// Never throws — any launch failure is captured as [exitCode] == `null`.
  Future<ProbeRunResult> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final stopwatch = Stopwatch()..start();
    final stderrBuffer = <String>[];

    ProcessStartResult startResult;
    try {
      startResult = await launcher(executable, arguments, workingDirectory);
    } catch (_) {
      // Failed to start (e.g. binary not found).
      return ProbeRunResult(
        exitCode: null,
        stderrTail: '',
        durationMs: stopwatch.elapsedMilliseconds,
        timedOut: false,
      );
    }

    final process = startResult.process;
    bool timedOut = false;
    int? exitCode;

    // Track last-progress timestamp via a mutable wrapper so stream callbacks
    // can update it without closures capturing a stale value.
    final lastProgress = _Ref<DateTime>(DateTime.now());

    // Collect stdout lines (we don't use them for hang detection output, but
    // their arrival resets the heartbeat — same contract as whisper.cpp progress).
    final stdoutDone = startResult.stdout.listen((_) {
      lastProgress.value = DateTime.now();
    }).asFuture<void>();

    // Collect stderr lines for post-mortem tail.
    final stderrDone = startResult.stderr.listen((line) {
      lastProgress.value = DateTime.now();
      stderrBuffer.add(line);
      if (stderrBuffer.length > stderrTailLines * 2) {
        // Trim aggressively to avoid unbounded growth on noisy processes.
        stderrBuffer.removeRange(0, stderrBuffer.length - stderrTailLines);
      }
    }).asFuture<void>();

    // Heartbeat / deadline watchdog.
    //
    // The Timer fires every [heartbeatTimeout]. On each tick it checks:
    //   (a) total elapsed > startupDeadline → kill
    //   (b) time since last progress > heartbeatTimeout → kill
    //
    // Using a repeating timer means the check granularity equals
    // [heartbeatTimeout] — fine for production (30 s) and for tests
    // with injected tiny durations the timer fires quickly.
    final watchdog = Timer.periodic(heartbeatTimeout, (_) {
      final now = DateTime.now();
      final elapsed = stopwatch.elapsed;
      final silence = now.difference(lastProgress.value);

      if (elapsed >= startupDeadline || silence >= heartbeatTimeout) {
        timedOut = true;
        process.kill();
      }
    });

    // Wait for the process to exit AND both streams to close.
    try {
      exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
    } finally {
      watchdog.cancel();
    }

    stopwatch.stop();

    // Build stderr tail.
    final tail = stderrBuffer.length <= stderrTailLines
        ? stderrBuffer
        : stderrBuffer.sublist(stderrBuffer.length - stderrTailLines);

    return ProbeRunResult(
      exitCode: exitCode,
      stderrTail: tail.join('\n'),
      durationMs: stopwatch.elapsedMilliseconds,
      timedOut: timedOut,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Mutable reference wrapper so closures can share a single mutable slot.
class _Ref<T> {
  _Ref(this.value);
  T value;
}
