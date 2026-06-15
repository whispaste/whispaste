/// ProbeCandidate implementation for Const-me/Whisper (DirectCompute).
///
/// Const-me/Whisper uses Direct3D 11 Compute Shaders (DirectCompute) for GPU
/// inference and runs on Windows only. It reads GGML model files compatible with
/// whisper.cpp but has its own CLI interface.
///
/// ## CPU preconditions
///
/// Const-me/Whisper requires AVX1 and F16C. The hybrid model size additionally
/// requires FMA3 and BMI1. A missing feature skips the candidate immediately
/// without starting a subprocess.
///
/// ## Output format assumption
///
/// Const-me's CLI emits transcript segments in the same bracket-timestamp
/// format as whisper.cpp:
///   `[HH:MM:SS.mmm --> HH:MM:SS.mmm]  <text>`
///
/// This format is documented in the Const-me/Whisper repository and matches
/// what is observed in whisper.cpp (which shares the same GGML decoding
/// infrastructure). Lines not matching this pattern are silently ignored.
/// If the real binary deviates, the parser can be updated here without touching
/// any other module.
///
/// ## CPU feature seam
///
/// `whispaste_diagnostics` does not expose a CPU instruction-set API, so a
/// minimal injectable [CpuFeatureSet] seam is defined locally. In tests,
/// pass a [CpuFeatureSet] with the features you want to simulate. Production
/// code must call the platform-specific detection and build the set from the
/// result — the actual live detection is out of scope for this module.
library;

import 'dart:async';

import 'outcome_classifier.dart';
import 'probe_runner.dart';
import 'probe_types.dart';
import 'wer.dart';

// ---------------------------------------------------------------------------
// CPU feature seam
// ---------------------------------------------------------------------------

/// Named constants for CPU instruction-set features required by Const-me/Whisper.
///
/// These string identifiers are the canonical keys for the [CpuFeatureSet].
const String cpuFeatureAvx = 'avx';
const String cpuFeatureF16c = 'f16c';
const String cpuFeatureFma3 = 'fma3';
const String cpuFeatureBmi1 = 'bmi1';

/// Injectable CPU feature set.
///
/// A [Set<String>] of feature names the current CPU supports. Use the
/// `cpuFeature*` constants as keys. In tests, construct directly:
/// ```dart
/// const features = {cpuFeatureAvx, cpuFeatureF16c};
/// ```
/// In production, populate from a platform-specific detection call
/// (outside this module's scope).
typedef CpuFeatureSet = Set<String>;

// ---------------------------------------------------------------------------
// Model size that additionally requires FMA3/BMI1
// ---------------------------------------------------------------------------

/// The model size that requires FMA3 + BMI1 in addition to AVX + F16C.
///
/// This mirrors the "hybrid" model designation in `FLUTTER_WHISPASTE-A0` and
/// corresponds to the medium-size quantised variant.
const String constMeHybridModelSize = 'whisper-medium';

// ---------------------------------------------------------------------------
// Output parser
// ---------------------------------------------------------------------------

/// Parses Const-me/Whisper segment lines from [stdout] and returns the joined
/// transcript text.
///
/// Const-me/Whisper emits segments in the same bracket-timestamp format as
/// whisper.cpp:
///   `[00:00:00.000 --> 00:00:05.000]  Hallo Welt.`
///
/// This assumption is documented in `decisions:` of the issue file and mirrors
/// the observation that both tools share the GGML decoding infrastructure.
/// Lines not matching this pattern are silently ignored.
///
/// Returns an empty string when no segment lines are present.
String parseConstMeTranscript(List<String> stdout) {
  // Pattern matches: [00:00:00.000 --> 00:00:05.000]  text...
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
// ConstMeCandidate
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that runs the Const-me/Whisper binary via [ProbeRunner].
///
/// Before spawning the subprocess, checks that the CPU meets the minimum
/// instruction-set requirements. A missing feature returns [Outcome.skipped]
/// immediately — no subprocess is ever started.
///
/// ## Parameters
/// - [id] — unique candidate identifier (e.g. `const-me-directcompute`).
/// - [binaryName] — executable name on PATH (e.g. `main.exe` or `constme-whisper`).
/// - [modelSizeKey] — the model-size key from `CandidateManifest`; used to
///   decide whether FMA3/BMI1 are also required.
/// - [cpuFeatures] — injectable [CpuFeatureSet]; must contain the features the
///   current CPU supports.
/// - [runner] — injectable [ProbeRunner]; defaults to production settings.
/// - [referenceTranscript] — soll-transcript used for WER; `null` skips WER.
///
/// ## Command line
/// `<binary> -m <modelPath> --language <language> -f <wavPath>`
///
/// The `--language` flag is required because Const-me/Whisper does not perform
/// automatic language detection; omitting it would produce incorrect output.
class ConstMeCandidate implements ProbeCandidate {
  const ConstMeCandidate({
    required this.id,
    required this.binaryName,
    required this.modelSizeKey,
    required this.cpuFeatures,
    this.runner = const ProbeRunner(),
    this.referenceTranscript,
  });

  @override
  final String id;

  /// Executable name looked up on PATH by the OS / [ProcessLauncher].
  final String binaryName;

  /// Model-size key used to decide which CPU features are required.
  final String modelSizeKey;

  /// Injectable CPU feature set (the features the current CPU supports).
  final CpuFeatureSet cpuFeatures;

  /// Injectable runner (production default; override in tests).
  final ProbeRunner runner;

  /// Optional soll-transcript for WER computation.
  final String? referenceTranscript;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    // CPU pre-flight: AVX1 + F16C are always required.
    final missingBase = _missingBaseFeatures(cpuFeatures);
    if (missingBase.isNotEmpty) {
      return CandidateResult(
        candidateId: id,
        outcome: Outcome.skipped,
        errorDetail:
            'CPU fehlen erforderliche Instruktionen für Const-me/Whisper: '
            '${missingBase.join(", ")}. Mindestanforderung: AVX1 + F16C.',
        backend: 'directcompute',
      );
    }

    // For the hybrid model size, FMA3 + BMI1 are additionally required.
    if (modelSizeKey == constMeHybridModelSize) {
      final missingHybrid = _missingHybridFeatures(cpuFeatures);
      if (missingHybrid.isNotEmpty) {
        return CandidateResult(
          candidateId: id,
          outcome: Outcome.skipped,
          errorDetail:
              'CPU fehlen erforderliche Instruktionen für das Hybrid-Modell '
              '("$modelSizeKey"): ${missingHybrid.join(", ")}. '
              'Mindestanforderung: FMA3 + BMI1.',
          backend: 'directcompute',
        );
      }
    }

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
        '--language',
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
        backend: 'directcompute',
      );
    }

    // Parse transcript from captured stdout.
    final transcript = parseConstMeTranscript(stdoutLines);

    // Compute WER when reference transcript is available.
    double? wer;
    if (referenceTranscript != null && referenceTranscript!.isNotEmpty) {
      wer = computeWer(transcript, referenceTranscript!);
    }

    final outcome = classifyOutcome(
      exitCode: runResult.exitCode,
      timedOut: runResult.timedOut,
      transcript: transcript,
      detectedLanguage: null, // Const-me does not emit detected language
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
      backend: 'directcompute',
    );
  }

  // ---------------------------------------------------------------------------
  // CPU feature helpers (pure)
  // ---------------------------------------------------------------------------

  /// Returns the list of base features (AVX1 + F16C) missing from [features].
  static List<String> _missingBaseFeatures(CpuFeatureSet features) {
    const required = [cpuFeatureAvx, cpuFeatureF16c];
    return required.where((f) => !features.contains(f)).toList();
  }

  /// Returns the list of hybrid-model features (FMA3 + BMI1) missing from [features].
  static List<String> _missingHybridFeatures(CpuFeatureSet features) {
    const required = [cpuFeatureFma3, cpuFeatureBmi1];
    return required.where((f) => !features.contains(f)).toList();
  }

  // ---------------------------------------------------------------------------
  // Stdout capture wrapper (mirrors WhisperCppCandidate)
  // ---------------------------------------------------------------------------

  /// Wraps [base] so that stdout lines are appended to [capture] AND forwarded
  /// to [ProbeRunner]'s internal listener.
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

/// Creates the default Const-me/Whisper DirectCompute candidate.
///
/// [cpuFeatures] must be the set of CPU instruction-set features supported by
/// the current machine. In production, populate from a platform-specific
/// detection call. In tests, pass any [Set<String>].
///
/// [modelSizeKey] determines whether FMA3/BMI1 are also checked (hybrid model).
ConstMeCandidate constMeDirectComputeCandidate({
  required String modelSizeKey,
  required CpuFeatureSet cpuFeatures,
  ProbeRunner runner = const ProbeRunner(),
  String? referenceTranscript,
}) => ConstMeCandidate(
  id: 'const-me-directcompute',
  binaryName: 'main.exe',
  modelSizeKey: modelSizeKey,
  cpuFeatures: cpuFeatures,
  runner: runner,
  referenceTranscript: referenceTranscript,
);
