/// whisper.cpp ProbeCandidate implementations for CPU, CUDA-12, Vulkan, and
/// OpenCL/CLBlast backends.
///
/// All four share the same stdout parser and subprocess contract; they differ
/// only in binary name and expected failure mode.
library;

import 'dart:async';

import 'outcome_classifier.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'wer.dart';

// ---------------------------------------------------------------------------
// Transcript parser
// ---------------------------------------------------------------------------

/// Parses whisper.cpp segment lines from [stdout] and returns the joined
/// transcript text.
///
/// whisper.cpp emits lines of the form:
///   `[00:00:00.000 --> 00:00:04.320]   Guten Tag, das ist ein Test.`
///
/// Lines that do not match this pattern are silently ignored (they are
/// progress/info lines, not transcript segments).
///
/// Returns an empty string when no segment lines are present.
String parseWhisperCppTranscript(List<String> stdout) {
  // Pattern matches: [00:00:00.000 --> 00:00:04.320]   text...
  // The timestamp block contains digits, colons, dots, spaces, dashes, and '>'.
  final segmentPattern = RegExp(r'^\[[\d:.\s\->]+\]\s+(.+)$');
  final segments = <String>[];
  for (final line in stdout) {
    final m = segmentPattern.firstMatch(line);
    if (m != null) {
      final text = m.group(1)!.trim();
      if (text.isNotEmpty) segments.add(text);
    }
  }
  return segments.join(' ');
}

// ---------------------------------------------------------------------------
// WhisperCppCandidate
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that runs a whisper.cpp binary via [ProbeRunner].
///
/// [id] — unique candidate identifier (e.g. `whisper-cpp-cpu`).
/// [binaryName] — executable name on PATH (e.g. `whisper`, `whisper-cuda12`).
/// [backend] — human-readable backend label stored in the result.
/// [runner] — injectable [ProbeRunner]; defaults to production settings.
/// [referenceTranscript] — soll-transcript used for WER; when null WER is
///   skipped (and the candidate can still be classified [Outcome.ok] as long
///   as a non-empty transcript was produced).
///
/// Command line built: `<binary> -m <modelPath> -l <language> -f <wavPath>`
class WhisperCppCandidate implements ProbeCandidate {
  const WhisperCppCandidate({
    required this.id,
    required this.binaryName,
    required this.backend,
    this.runner = const ProbeRunner(),
    this.referenceTranscript,
  });

  @override
  final String id;

  /// Executable name (looked up on PATH by the OS / [ProcessLauncher]).
  final String binaryName;

  /// Backend label stored in [CandidateResult.backend].
  final String backend;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// Optional soll-transcript for WER computation.
  final String? referenceTranscript;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    // Collect stdout so we can parse the transcript after the process exits.
    final stdoutLines = <String>[];

    // Wrap the runner's launcher to intercept stdout lines.
    final capturingRunner = ProbeRunner(
      launcher: _makeCaptureWrapper(runner.launcher, stdoutLines),
      startupDeadline: runner.startupDeadline,
      heartbeatTimeout: runner.heartbeatTimeout,
      stderrTailLines: runner.stderrTailLines,
    );

    final runResult = await capturingRunner.run(
      executable: binaryName,
      arguments: [
        '-m',
        ctx.modelPath,
        '-l',
        ctx.language,
        '-f',
        ctx.referenceWavPath,
      ],
      workingDirectory: ctx.workDir,
    );

    // Binary not found → launcher threw → exitCode is null, not timed out.
    if (runResult.exitCode == null && !runResult.timedOut) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        durationMs: runResult.durationMs,
        errorDetail: 'Binary "$binaryName" nicht gefunden oder nicht startbar.',
        backend: backend,
      );
    }

    // Parse transcript from captured stdout.
    final transcript = parseWhisperCppTranscript(stdoutLines);

    // Compute WER when reference transcript is available.
    double? wer;
    if (referenceTranscript != null && referenceTranscript!.isNotEmpty) {
      wer = computeWer(transcript, referenceTranscript!);
    }

    final outcome = classifyOutcome(
      exitCode: runResult.exitCode,
      timedOut: runResult.timedOut,
      transcript: transcript,
      detectedLanguage: null, // whisper.cpp stdout does not emit detected lang
      expectedLanguage: ctx.language,
      wer: wer,
    );

    String? errorDetail;
    if (outcome != Outcome.ok) {
      if (runResult.timedOut) {
        errorDetail = 'Prozess überschritt Deadline und wurde beendet.';
      } else if (runResult.exitCode != null && runResult.exitCode != 0) {
        errorDetail =
            'Prozess beendete sich mit Exit-Code ${runResult.exitCode}.';
      }
    }

    return CandidateResult(
      candidateId: id,
      outcome: outcome,
      durationMs: runResult.durationMs,
      transcribedText: transcript.isEmpty ? null : transcript,
      errorDetail: errorDetail,
      exitCode: runResult.exitCode,
      stderrTail: runResult.stderrTail.isEmpty ? null : runResult.stderrTail,
      wer: wer,
      backend: backend,
    );
  }

  /// Wraps [base] so that stdout lines are appended to [capture] AND forwarded
  /// to [ProbeRunner]'s internal listener.
  ///
  /// A broadcast [StreamController] is used as a tee: the original single-
  /// subscription stdout stream is drained once into the controller, which
  /// distributes each line to both the capture list and [ProbeRunner]'s
  /// heartbeat listener.  This avoids the race where an eager first listener
  /// on a broadcast stream consumes all buffered events before the second
  /// listener subscribes.
  ProcessLauncher _makeCaptureWrapper(
    ProcessLauncher base,
    List<String> capture,
  ) {
    return (executable, arguments, workingDirectory) async {
      final result = await base(executable, arguments, workingDirectory);

      // Create a broadcast controller that both consumers subscribe to.
      final teeCtrl = StreamController<String>.broadcast();

      // Subscribe to the original (single-subscription) stdout and forward
      // every event into the tee controller.  We subscribe *before* returning
      // so no events can be missed even if the stream is already closed.
      result.stdout.listen(
        teeCtrl.add,
        onError: teeCtrl.addError,
        onDone: teeCtrl.close,
      );

      // Subscribe our capture list to the tee.
      teeCtrl.stream.listen(capture.add);

      return ProcessStartResult(
        process: result.process,
        // Hand the same broadcast stream to ProbeRunner.
        stdout: teeCtrl.stream,
        stderr: result.stderr,
      );
    };
  }
}

// ---------------------------------------------------------------------------
// Named factory constructors (one per whisper.cpp variant)
// ---------------------------------------------------------------------------

/// CPU-Baseline candidate — the reference against which GPU backends are judged.
WhisperCppCandidate whisperCppCpuCandidate({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => WhisperCppCandidate(
  id: 'whisper-cpp-cpu',
  binaryName: 'whisper',
  backend: 'cpu',
  runner: runner,
  referenceTranscript: referenceTranscript,
);

/// CUDA-12 candidate — expected to crash on Kepler (sm_3x) because CUDA 12
/// dropped support for compute capability 3.x.
WhisperCppCandidate whisperCppCuda12Candidate({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => WhisperCppCandidate(
  id: 'whisper-cpp-cuda12',
  binaryName: 'whisper-cuda12',
  backend: 'cuda12',
  runner: runner,
  referenceTranscript: referenceTranscript,
);

/// Vulkan candidate — expected to hang on Kepler due to stalled Vulkan driver.
WhisperCppCandidate whisperCppVulkanCandidate({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => WhisperCppCandidate(
  id: 'whisper-cpp-vulkan',
  binaryName: 'whisper-vulkan',
  backend: 'vulkan',
  runner: runner,
  referenceTranscript: referenceTranscript,
);

/// OpenCL/CLBlast candidate — skipped when no binary is available (the
/// OpenCL-patched whisper.cpp build is not distributed as a pre-built binary).
///
/// This candidate always returns [Outcome.skipped] immediately because the
/// binary is not distributable — the ProbeRunner is never invoked.
class WhisperCppOpenClCandidate implements ProbeCandidate {
  const WhisperCppOpenClCandidate();

  @override
  String get id => 'whisper-cpp-opencl';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    return const CandidateResult(
      candidateId: 'whisper-cpp-opencl',
      outcome: Outcome.skipped,
      errorDetail: 'Backend-Binary nicht beschaffbar',
      backend: 'opencl',
    );
  }
}
