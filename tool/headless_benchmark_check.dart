/// Compares `whispaste --transcribe-file … --json` reports against the stored
/// baseline (`tool/headless_benchmark_baseline.json`) and fails on a latency
/// regression. Run by `.github/workflows/headless-benchmark.yml`.
///
/// ```sh
/// dart "$REPO/tool/headless_benchmark_check.dart" \
///   --baseline "$REPO/tool/headless_benchmark_baseline.json" report1.json …
/// ```
///
/// Imports only `dart:` libraries; call it from outside the repo directory
/// so `dart` does not run the app package's native build hooks first.
///
/// Baseline keys are `<platform>/<engine>/<model>` → median RTF. A run fails
/// when its median RTF exceeds baseline × `tolerance` (default 1.5: hosted
/// runners are noisy, the gate is for real regressions, not jitter). A key
/// without a baseline only warns — calibrate it from that run's report.
library;

import 'dart:convert';
import 'dart:io';

const double _defaultTolerance = 1.5;

class HeadlessBenchmarkVerdict {
  HeadlessBenchmarkVerdict();

  final failures = <String>[];
  final warnings = <String>[];

  /// One Markdown table row per report.
  final summary = <String>[];
}

HeadlessBenchmarkVerdict checkHeadlessBenchmark(
  Map<String, Object?> baseline,
  List<Map<String, Object?>> reports,
) {
  final tolerance =
      (baseline['tolerance'] as num?)?.toDouble() ?? _defaultTolerance;
  final rtfBaseline = (baseline['rtfMedian'] as Map?) ?? const {};
  final verdict = HeadlessBenchmarkVerdict();

  for (final r in reports) {
    final key = '${r['platform']}/${r['engine']}/${r['model']}';
    final rtf = (r['rtfMedian']! as num).toDouble();
    final base = (rtfBaseline[key] as num?)?.toDouble();
    final rtfText = rtf.toStringAsFixed(3);
    String status;
    if (base == null) {
      status = 'no baseline';
      verdict.warnings.add(
        '$key: no baseline yet — measured median RTF $rtfText; add it to the '
        'baseline file to enable the regression gate.',
      );
    } else if (rtf > base * tolerance) {
      status = 'REGRESSION';
      verdict.failures.add(
        '$key: median RTF ${rtf.toStringAsFixed(2)} exceeds baseline '
        '${base.toStringAsFixed(3)} x $tolerance.',
      );
    } else {
      status = 'ok';
    }
    verdict.summary.add(
      '| $key | $rtfText | ${base?.toStringAsFixed(3) ?? '-'} '
      '| ${r['loadMs']} | $status |',
    );
  }
  return verdict;
}

void main(List<String> args) {
  final baselineIndex = args.indexOf('--baseline');
  if (baselineIndex < 0 || baselineIndex + 1 >= args.length) {
    stderr.writeln(
      'usage: headless_benchmark_check.dart --baseline <file> <report.json>…',
    );
    exitCode = 64;
    return;
  }
  Map<String, Object?> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  final baseline = readJson(args[baselineIndex + 1]);
  final reportPaths = [...args]..removeRange(baselineIndex, baselineIndex + 2);
  final verdict = checkHeadlessBenchmark(baseline, [
    for (final path in reportPaths) readJson(path),
  ]);

  stdout
    ..writeln('| Configuration | Median RTF | Baseline | Load ms | Status |')
    ..writeln('|---|---|---|---|---|')
    ..writeAll(verdict.summary.map((row) => '$row\n'));
  for (final w in verdict.warnings) {
    stderr.writeln('::warning::$w');
  }
  for (final f in verdict.failures) {
    stderr.writeln('::error::$f');
  }
  if (verdict.failures.isNotEmpty) exitCode = 1;
}
