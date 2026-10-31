/// Ranking logic: CPU baseline detection, speedup factors, ranked output.
///
/// The CPU baseline (candidateId starting with `whisper-cpp-cpu` or backend
/// `cpu`) is mandatory — every [ProbeReport] carries a [RankingResult] that
/// flags its presence. GPU candidates with outcome `ok` are ranked by
/// (speedup descending, WER ascending). Non-`ok` candidates appear in the
/// "failed" section without a speedup factor.
library;

import 'probe_types.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Candidate ID prefix that identifies the mandatory CPU baseline.
const String cpuBaselineIdPrefix = 'whisper-cpp-cpu';

/// Backend name that identifies the CPU baseline as fallback.
const String cpuBaselineBackend = 'cpu';

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// One row in the ranked speed table (only `ok` candidates).
class RankedCandidate {
  const RankedCandidate({
    required this.result,
    required this.speedupFactor,
    required this.isCpuBaseline,
  });

  /// The underlying probe result.
  final CandidateResult result;

  /// How many times faster (> 1) or slower (< 1) this candidate is relative
  /// to the CPU baseline. Always 1.0 for the CPU baseline itself.
  final double speedupFactor;

  /// True when this row is the mandatory CPU baseline.
  final bool isCpuBaseline;
}

/// Full ranking result computed from a [ProbeReport].
class RankingResult {
  const RankingResult({
    required this.cpuBaseline,
    required this.ranked,
    required this.failed,
    required this.cpuBaselineMissing,
  });

  /// The CPU baseline result, or null if absent.
  final CandidateResult? cpuBaseline;

  /// `ok` candidates sorted by (speedup desc, WER asc); includes the CPU
  /// baseline at its natural position (speedup == 1.0).
  final List<RankedCandidate> ranked;

  /// Non-`ok` candidates (excluding the CPU baseline if it failed).
  final List<CandidateResult> failed;

  /// True when no CPU baseline was found in the results.
  final bool cpuBaselineMissing;
}

// ---------------------------------------------------------------------------
// Ranking logic
// ---------------------------------------------------------------------------

/// Returns true when [r] is the mandatory CPU baseline.
bool isCpuBaseline(CandidateResult r) {
  if (r.candidateId.startsWith(cpuBaselineIdPrefix)) return true;
  if (r.backend != null &&
      r.backend!.toLowerCase() == cpuBaselineBackend &&
      r.outcome == Outcome.ok) {
    return true;
  }
  return false;
}

/// Computes the [RankingResult] for [report].
///
/// Algorithm:
/// 1. Find the CPU baseline (first result where [isCpuBaseline] is true).
/// 2. For every `ok` candidate compute speedup = cpuMs / candidateMs.
///    If durationMs is null → speedup is 0.0 (sort to bottom of ok list).
/// 3. Sort ok list by (speedupFactor desc, WER asc).
/// 4. Non-ok candidates go to [RankingResult.failed].
RankingResult computeRanking(ProbeReport report) {
  CandidateResult? baseline;

  // Find the CPU baseline.
  for (final r in report.results) {
    if (isCpuBaseline(r)) {
      baseline = r;
      break;
    }
  }

  final baselineMs = baseline?.durationMs;

  final okCandidates = <RankedCandidate>[];
  final failedCandidates = <CandidateResult>[];

  for (final r in report.results) {
    if (r.outcome == Outcome.ok) {
      final isBaseline = isCpuBaseline(r);
      double factor;
      if (isBaseline) {
        factor = 1.0;
      } else if (baselineMs != null &&
          baselineMs > 0 &&
          r.durationMs != null &&
          r.durationMs! > 0) {
        factor = baselineMs / r.durationMs!;
      } else {
        factor = 0.0; // unknown
      }
      okCandidates.add(
        RankedCandidate(
          result: r,
          speedupFactor: factor,
          isCpuBaseline: isBaseline,
        ),
      );
    } else {
      failedCandidates.add(r);
    }
  }

  // Sort ok candidates: speedup desc, then WER asc.
  okCandidates.sort((a, b) {
    final speedCmp = b.speedupFactor.compareTo(a.speedupFactor);
    if (speedCmp != 0) return speedCmp;
    final werA = a.result.wer ?? double.infinity;
    final werB = b.result.wer ?? double.infinity;
    return werA.compareTo(werB);
  });

  return RankingResult(
    cpuBaseline: baseline,
    ranked: List.unmodifiable(okCandidates),
    failed: List.unmodifiable(failedCandidates),
    cpuBaselineMissing: baseline == null,
  );
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

/// Converts [ranking] to a JSON-serialisable map (used by [ProbeReport.toJson]).
Map<String, Object?> rankingToJson(RankingResult ranking) {
  return {
    'cpuBaselineMissing': ranking.cpuBaselineMissing,
    if (ranking.cpuBaseline != null)
      'cpuBaselineCandidateId': ranking.cpuBaseline!.candidateId,
    'ranked': ranking.ranked
        .map(
          (rc) => <String, Object?>{
            'candidateId': rc.result.candidateId,
            'outcome': rc.result.outcome.name,
            'isCpuBaseline': rc.isCpuBaseline,
            'speedupFactor': rc.speedupFactor,
            if (rc.result.durationMs != null)
              'durationMs': rc.result.durationMs,
            if (rc.result.wer != null) 'wer': rc.result.wer,
            if (rc.result.realtimeFactor != null)
              'realtimeFactor': rc.result.realtimeFactor,
          },
        )
        .toList(),
    'failed': ranking.failed
        .map(
          (r) => <String, Object?>{
            'candidateId': r.candidateId,
            'outcome': r.outcome.name,
            if (r.errorDetail != null) 'errorDetail': r.errorDetail,
            if (r.exitCode != null) 'exitCode': r.exitCode,
          },
        )
        .toList(),
  };
}

// ---------------------------------------------------------------------------
// Markdown helpers
// ---------------------------------------------------------------------------

/// Formats a speedup factor as a human-readable string like `2.5×` or `0.8×`.
String formatSpeedup(double factor) {
  if (factor == 0.0) return 'n/a';
  return '${factor.toStringAsFixed(2)}×';
}

/// Formats a WER fraction as a percentage string like `5.2 %`.
String formatWer(double? wer) {
  if (wer == null) return '—';
  return '${(wer * 100).toStringAsFixed(1)} %';
}

/// Formats a realtime factor, e.g. `0.42`.
String formatRtf(double? rtf) {
  if (rtf == null) return '—';
  return rtf.toStringAsFixed(2);
}

/// Converts [ranking] to a Markdown snippet (ranking table + failed section).
String rankingToMarkdown(RankingResult ranking) {
  final b = StringBuffer();

  // CPU baseline warning.
  if (ranking.cpuBaselineMissing) {
    b.writeln(
      '> **WARNING: CPU baseline missing.** '
      'No candidate with id prefix `$cpuBaselineIdPrefix` or backend `$cpuBaselineBackend` found. '
      'Speedup factors cannot be computed.',
    );
    b.writeln();
  }

  // Speed ranking table.
  b.writeln('## Speed Ranking');
  b.writeln();
  b.writeln(
    '| Rank | Candidate | Speedup vs CPU | WER | RTF | Duration (ms) |',
  );
  b.writeln('|---:|:---|---:|---:|---:|---:|');

  for (var i = 0; i < ranking.ranked.length; i++) {
    final rc = ranking.ranked[i];
    final rank = i + 1;
    final cpuMarker = rc.isCpuBaseline ? ' *(baseline)*' : '';
    final candidateLabel = '${rc.result.candidateId}$cpuMarker';
    final speedup = formatSpeedup(rc.speedupFactor);
    final wer = formatWer(rc.result.wer);
    final rtf = formatRtf(rc.result.realtimeFactor);
    final dur = rc.result.durationMs?.toString() ?? '—';
    b.writeln('| $rank | $candidateLabel | $speedup | $wer | $rtf | $dur |');
  }

  b.writeln();

  // Failed / non-ok section.
  if (ranking.failed.isNotEmpty) {
    b.writeln('## Failed / Skipped Candidates');
    b.writeln();
    b.writeln('| Candidate | Outcome | Detail |');
    b.writeln('|:---|:---|:---|');
    for (final r in ranking.failed) {
      final detail = r.errorDetail ?? '—';
      b.writeln('| ${r.candidateId} | ${r.outcome.name} | $detail |');
    }
    b.writeln();
  }

  return b.toString();
}
