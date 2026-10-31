/// Core types for the WhisPaste GPU probe tool.
///
/// These are plain data types — no engine logic, no subprocess handling.
/// Classification and ranking land in later slices.
library;

import 'ranking.dart';

/// Result outcome of a single [ProbeCandidate] run.
enum Outcome {
  /// The candidate completed successfully and produced expected output.
  ok,

  /// The candidate process failed to start (missing binary, bad args, etc.).
  failedToStart,

  /// The candidate process crashed with a non-zero exit code.
  crashed,

  /// The candidate exceeded the allowed timeout.
  hung,

  /// The candidate exited cleanly but the transcription was wrong.
  wrongOutput,

  /// The candidate was killed or failed due to GPU out-of-memory.
  outOfMemory,

  /// The candidate was skipped (e.g. not applicable for this platform).
  skipped,
}

/// Context passed to each [ProbeCandidate.run] call.
///
/// All paths and parameters needed to run a single probe candidate.
/// Fully injectable so candidates can be driven in unit tests without
/// real files or processes.
class ProbeContext {
  const ProbeContext({
    required this.referenceWavPath,
    required this.modelPath,
    required this.workDir,
    this.language = 'de',
    this.timeout = const Duration(minutes: 2),
  });

  /// Path to the reference WAV file used as transcription input.
  final String referenceWavPath;

  /// Path to the Whisper model file (`.bin`).
  final String modelPath;

  /// Working directory for the candidate process.
  final String workDir;

  /// BCP-47 language code for the transcription. Defaults to German (`de`).
  final String language;

  /// Maximum time to wait for a candidate to complete.
  final Duration timeout;
}

/// Result returned by a single [ProbeCandidate] run.
class CandidateResult {
  const CandidateResult({
    required this.candidateId,
    required this.outcome,
    this.durationMs,
    this.transcribedText,
    this.errorDetail,
    this.exitCode,
    this.stderrTail,
    this.realtimeFactor,
    this.modelId,
    this.backend,
    this.wer,
    this.peakVramMb,
  });

  /// Identifier of the candidate that produced this result.
  final String candidateId;

  /// How the run ended.
  final Outcome outcome;

  /// Wall-clock duration of the run in milliseconds, or null if not measured.
  final int? durationMs;

  /// The transcription text produced by the candidate, if any.
  final String? transcribedText;

  /// Human-readable error detail when [outcome] is not [Outcome.ok].
  final String? errorDetail;

  /// Process exit code, if the candidate was a subprocess.
  final int? exitCode;

  /// Last lines of stderr output, for post-mortem analysis.
  final String? stderrTail;

  /// Ratio of audio duration to wall-clock processing time (lower is faster).
  ///
  /// A value of 1.0 means real-time; 0.5 means twice as fast as real-time.
  final double? realtimeFactor;

  /// Identifier of the Whisper model that was loaded (e.g. `ggml-small-q5_1`).
  final String? modelId;

  /// Inference backend used by the candidate (e.g. `cuda`, `vulkan`, `cpu`).
  final String? backend;

  /// Word Error Rate of the transcription, as a fraction in [0, ∞).
  ///
  /// Values above [werWrongOutputThreshold] are classified as [Outcome.wrongOutput].
  final double? wer;

  /// Peak GPU VRAM usage in megabytes, if measurable.
  final int? peakVramMb;
}

/// Hardware context captured at probe time (optional; null fields mean unknown).
class HardwareContext {
  const HardwareContext({
    this.cpuModel,
    this.ramGb,
    this.gpuModel,
    this.vramGb,
    this.os,
    this.driverVersion,
  });

  /// CPU model string, e.g. `Intel Core i7-12700K`.
  final String? cpuModel;

  /// Total system RAM in gigabytes, e.g. `32`.
  final int? ramGb;

  /// GPU model string, e.g. `NVIDIA GeForce RTX 3070`.
  final String? gpuModel;

  /// Total GPU VRAM in gigabytes, e.g. `8`.
  final int? vramGb;

  /// Operating system identifier, e.g. `Windows 11 23H2`.
  final String? os;

  /// GPU driver version, e.g. `546.33`.
  final String? driverVersion;

  /// Converts to a JSON-serialisable map (omits null values).
  Map<String, Object?> toJson() => {
    if (cpuModel != null) 'cpuModel': cpuModel,
    if (ramGb != null) 'ramGb': ramGb,
    if (gpuModel != null) 'gpuModel': gpuModel,
    if (vramGb != null) 'vramGb': vramGb,
    if (os != null) 'os': os,
    if (driverVersion != null) 'driverVersion': driverVersion,
  };

  /// Renders a short prose summary for the Markdown hardware context section.
  String toMarkdownLines() {
    final lines = <String>[];
    if (cpuModel != null) lines.add('- **CPU:** $cpuModel');
    if (ramGb != null) lines.add('- **RAM:** $ramGb GB');
    if (gpuModel != null) lines.add('- **GPU:** $gpuModel');
    if (vramGb != null) lines.add('- **VRAM:** $vramGb GB');
    if (os != null) lines.add('- **OS:** $os');
    if (driverVersion != null) lines.add('- **Driver:** $driverVersion');
    return lines.join('\n');
  }
}

/// Aggregated report produced by the [ProbeOrchestrator].
class ProbeReport {
  const ProbeReport({
    required this.timestamp,
    required this.results,
    required this.version,
    this.hardwareContext,
  });

  /// When the probe run started (UTC).
  final DateTime timestamp;

  /// One [CandidateResult] per candidate, in run order.
  final List<CandidateResult> results;

  /// Tool version stamp (from `--define=whispaste_version=…`).
  final String version;

  /// Optional hardware context captured at probe time.
  final HardwareContext? hardwareContext;

  /// Converts the report to a JSON-serialisable map, including ranking data.
  Map<String, Object?> toJson() {
    final ranking = computeRanking(this);
    return {
      'timestamp': timestamp.toIso8601String(),
      'version': version,
      if (hardwareContext != null) 'hardwareContext': hardwareContext!.toJson(),
      'results': results
          .map(
            (r) => <String, Object?>{
              'candidateId': r.candidateId,
              'outcome': r.outcome.name,
              if (r.durationMs != null) 'durationMs': r.durationMs,
              if (r.transcribedText != null)
                'transcribedText': r.transcribedText,
              if (r.errorDetail != null) 'errorDetail': r.errorDetail,
              if (r.exitCode != null) 'exitCode': r.exitCode,
              if (r.realtimeFactor != null) 'realtimeFactor': r.realtimeFactor,
              if (r.wer != null) 'wer': r.wer,
              if (r.backend != null) 'backend': r.backend,
            },
          )
          .toList(),
      'ranking': rankingToJson(ranking),
    };
  }

  /// Converts the report to a Markdown document with hardware context,
  /// speed ranking table, failed-candidate section, and outcome overview.
  String toMarkdown() {
    final ranking = computeRanking(this);
    final b = StringBuffer();

    // Header
    b.writeln('# WhisPaste GPU Probe Report');
    b.writeln();
    b.writeln('**Timestamp:** ${timestamp.toIso8601String()}');
    b.writeln('**Version:** $version');
    b.writeln();

    // Hardware context
    if (hardwareContext != null) {
      b.writeln('## Hardware Context');
      b.writeln();
      b.writeln(hardwareContext!.toMarkdownLines());
      b.writeln();
    }

    // Ranking table + failed section
    b.write(rankingToMarkdown(ranking));

    // Outcome overview (raw results)
    b.writeln('## Outcome Overview');
    b.writeln();
    b.writeln('| Candidate | Outcome | Duration (ms) | WER | RTF |');
    b.writeln('|:---|:---|---:|---:|---:|');
    for (final r in results) {
      final dur = r.durationMs?.toString() ?? '—';
      final wer = r.wer != null
          ? '${(r.wer! * 100).toStringAsFixed(1)} %'
          : '—';
      final rtf = r.realtimeFactor != null
          ? r.realtimeFactor!.toStringAsFixed(2)
          : '—';
      b.writeln(
        '| ${r.candidateId} | ${r.outcome.name} | $dur | $wer | $rtf |',
      );
    }
    b.writeln();

    return b.toString();
  }
}

/// Interface every probe candidate must implement.
///
/// Implementations may be real engine wrappers (later slices) or fakes
/// (used in tests and the tracer-bullet skeleton).
abstract interface class ProbeCandidate {
  /// Unique identifier for this candidate (e.g. `whisper-cpp-cpu`).
  String get id;

  /// Runs the candidate against [ctx] and returns a [CandidateResult].
  ///
  /// Must not throw — any error should be captured in the returned
  /// [CandidateResult] with an appropriate [Outcome].
  Future<CandidateResult> run(ProbeContext ctx);
}
