/// Core types for the WhisPaste GPU probe tool.
///
/// These are plain data types — no engine logic, no subprocess handling.
/// Classification and ranking land in later slices.
library;

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
}

/// Aggregated report produced by the [ProbeOrchestrator].
class ProbeReport {
  const ProbeReport({
    required this.timestamp,
    required this.results,
    required this.version,
  });

  /// When the probe run started (UTC).
  final DateTime timestamp;

  /// One [CandidateResult] per candidate, in run order.
  final List<CandidateResult> results;

  /// Tool version stamp (from `--define=whispaste_version=…`).
  final String version;

  /// Converts the report to a JSON-serialisable map.
  Map<String, Object> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'version': version,
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
            },
          )
          .toList(),
    };
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
