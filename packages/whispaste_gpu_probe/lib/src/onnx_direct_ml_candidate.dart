/// ProbeCandidate implementation for ONNX Runtime + DirectML backend.
///
/// ONNX Runtime with the DirectML execution provider supports Whisper-ONNX
/// models on Windows.  Microsoft officially lists Kepler (GTX 600+) as
/// supported, but the medium model is known to trigger crash code `887A0006`
/// (DXGI_ERROR_DEVICE_HUNG) on hardware where DirectML is in maintenance mode.
/// This candidate exists to observe that crash empirically rather than assume
/// it.
///
/// ## Output format assumption
///
/// The ONNX DirectML runner is expected to emit one `transcript:` line
/// containing the full transcribed text:
///
///   `transcript: Guten Tag, das ist ein Test.`
///
/// Lines beginning with `[whisper-onnx]` are treated as progress/info lines
/// and are silently ignored.  All other lines are also ignored.  If the real
/// runner emits a different format, only this parser needs updating.
///
/// ## Reuse by Slice 15
///
/// [OnnxDirectMlCandidate] is parameterised by [binaryName], [modelSizeKey],
/// and the [outputParser] strategy function.  Slice 15 can construct a new
/// candidate with a different binary name and/or parser while reusing the
/// subprocess-spawn / WER / classify pipeline unchanged.
library;

import 'dart:async';

import 'outcome_classifier.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'wer.dart';

// ---------------------------------------------------------------------------
// Output parser
// ---------------------------------------------------------------------------

/// Parses ONNX DirectML runner output and returns the transcript text.
///
/// Scans [stdout] for lines matching `transcript: <text>`.  The first match
/// wins; subsequent `transcript:` lines are ignored (the runner emits exactly
/// one).
///
/// Returns an empty string when no transcript line is found.
String parseOnnxDirectMlTranscript(List<String> stdout) {
  for (final line in stdout) {
    final trimmed = line.trim();
    const prefix = 'transcript:';
    if (trimmed.toLowerCase().startsWith(prefix)) {
      final text = trimmed.substring(prefix.length).trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

// ---------------------------------------------------------------------------
// OnnxDirectMlCandidate
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that runs a Whisper-ONNX binary via the DirectML
/// execution provider.
///
/// ## Parameters
/// - [id] — unique candidate identifier (e.g. `onnx-directml`).
/// - [binaryName] — executable name on PATH
///   (e.g. `whisper-onnx-directml.exe`).
/// - [backend] — human-readable backend label stored in the result.
/// - [runner] — injectable [ProbeRunner]; defaults to production settings.
/// - [referenceTranscript] — soll-transcript for WER; `null` skips WER.
/// - [outputParser] — strategy function that extracts the transcript from
///   stdout lines.  Defaults to [parseOnnxDirectMlTranscript].  Slice 15 can
///   supply a different parser without subclassing.
///
/// ## Command line
/// `<binary> --model <modelPath> --language <language> --wav <wavPath>`
///
/// The `--language` flag is passed explicitly so the runner does not fall back
/// to auto-detection, which may produce non-German output on German clips.
///
/// ## 887A0006 crash handling
///
/// HRESULT `0x887A0006` = `DXGI_ERROR_DEVICE_HUNG`.  On Kepler hardware with
/// DirectML in maintenance mode, the runner exits with a non-zero exit code
/// (the exact integer depends on how the binary maps the HRESULT to a process
/// exit code).  [classifyOutcome] maps any non-zero exit code to
/// [Outcome.crashed]; the exit code + stderr tail are preserved in
/// [CandidateResult] as evidence.
class OnnxDirectMlCandidate implements ProbeCandidate {
  const OnnxDirectMlCandidate({
    required this.id,
    required this.binaryName,
    this.backend = 'directml',
    this.runner = const ProbeRunner(),
    this.referenceTranscript,
    this.outputParser = parseOnnxDirectMlTranscript,
  });

  @override
  final String id;

  /// Executable name looked up on PATH by the OS / [ProcessLauncher].
  final String binaryName;

  /// Backend label stored in [CandidateResult.backend].
  final String backend;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// Optional soll-transcript for WER computation.
  final String? referenceTranscript;

  /// Strategy function that extracts the transcript from stdout lines.
  ///
  /// Parameterised so Slice 15 can reuse the candidate with a different
  /// output format without subclassing.
  final String Function(List<String> stdout) outputParser;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    // Collect stdout lines so we can parse the transcript after exit.
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
        '--model',
        ctx.modelPath,
        '--language',
        ctx.language,
        '--wav',
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

    // Parse transcript via the injected strategy.
    final transcript = outputParser(stdoutLines);

    // Compute WER when reference transcript is available.
    double? wer;
    if (referenceTranscript != null && referenceTranscript!.isNotEmpty) {
      wer = computeWer(transcript, referenceTranscript!);
    }

    final outcome = classifyOutcome(
      exitCode: runResult.exitCode,
      timedOut: runResult.timedOut,
      transcript: transcript,
      detectedLanguage: null, // ONNX runner does not emit detected language
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

  // ---------------------------------------------------------------------------
  // Stdout capture wrapper (mirrors WhisperCppCandidate / ConstMeCandidate)
  // ---------------------------------------------------------------------------

  /// Wraps [base] so that stdout lines are appended to [capture] AND forwarded
  /// to [ProbeRunner]'s internal heartbeat listener.
  ProcessLauncher _makeCaptureWrapper(
    ProcessLauncher base,
    List<String> capture,
  ) {
    return (executable, arguments, workingDirectory) async {
      final result = await base(executable, arguments, workingDirectory);

      // Tee the single-subscription stdout into a broadcast stream so both
      // the capture list and ProbeRunner's heartbeat listener can subscribe.
      final teeCtrl = StreamController<String>.broadcast();

      result.stdout.listen(
        teeCtrl.add,
        onError: teeCtrl.addError,
        onDone: teeCtrl.close,
      );

      teeCtrl.stream.listen(capture.add);

      return ProcessStartResult(
        process: result.process,
        stdout: teeCtrl.stream,
        stderr: result.stderr,
      );
    };
  }
}

// ---------------------------------------------------------------------------
// Named factory constructor
// ---------------------------------------------------------------------------

/// Creates the default ONNX Runtime + DirectML candidate.
///
/// [runner] is the injectable [ProbeRunner]; override in tests with a fake
/// launcher.  [referenceTranscript] is the soll-transcript used for WER.
/// [outputParser] defaults to [parseOnnxDirectMlTranscript]; Slice 15 can
/// pass a different parser to reuse the subprocess pipeline for another model
/// format.
OnnxDirectMlCandidate onnxDirectMlCandidate({
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
  String Function(List<String>)? outputParser,
}) => OnnxDirectMlCandidate(
  id: 'onnx-directml',
  binaryName: 'whisper-onnx-directml.exe',
  backend: 'directml',
  runner: runner,
  referenceTranscript: referenceTranscript,
  outputParser: outputParser ?? parseOnnxDirectMlTranscript,
);
