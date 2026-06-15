/// ProbeOrchestrator — iterates candidates, builds the report, writes artefacts.
///
/// All dependencies are injectable: candidate list, output directory, clock,
/// and the delivery step. This makes the orchestrator fully unit-testable
/// without real engines, subprocesses, or a real Desktop path.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show sanitizePaths;

import 'probe_types.dart';

/// Injectable delivery step: receives the ZIP path after writing.
///
/// In production: reveal in file manager.
/// In tests: a fake that captures the call without side effects.
typedef ProbeDeliveryStep = Future<void> Function(String zipPath);

/// Returns the platform-appropriate Desktop path.
///
/// [environment] and [platformOverride] are injectable for testing;
/// production code omits both and relies on [Platform.environment] /
/// [Platform.operatingSystem].
String resolveDesktopPath({
  Map<String, String>? environment,
  String? platformOverride,
}) {
  final env = environment ?? Platform.environment;
  final platform = platformOverride ?? Platform.operatingSystem;

  if (platform == 'windows') {
    final userProfile = env['USERPROFILE'] ?? env['HOME'] ?? '';
    return p.join(userProfile, 'Desktop');
  }
  // macOS and Linux both put the Desktop under $HOME/Desktop.
  final home = env['HOME'] ?? '';
  return p.join(home, 'Desktop');
}

/// Timestamp-based file stem, e.g. `WhisPaste-GPU-Probe-20260615-143022`.
String buildProbeStem(DateTime now) {
  final y = now.year.toString().padLeft(4, '0');
  final mo = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final h = now.hour.toString().padLeft(2, '0');
  final mi = now.minute.toString().padLeft(2, '0');
  final s = now.second.toString().padLeft(2, '0');
  return 'WhisPaste-GPU-Probe-$y$mo$d-$h$mi$s';
}

/// Formats the probe report as Markdown.
String formatProbeReportMarkdown(ProbeReport report) {
  final b = StringBuffer()
    ..writeln('# WhisPaste GPU Probe Report')
    ..writeln()
    ..writeln('**Timestamp:** ${report.timestamp.toIso8601String()}')
    ..writeln('**Version:** ${report.version}')
    ..writeln()
    ..writeln('## Results')
    ..writeln();

  for (final r in report.results) {
    b.writeln('### ${r.candidateId}');
    b.writeln('- **Outcome:** ${r.outcome.name}');
    if (r.durationMs != null) {
      b.writeln('- **Duration:** ${r.durationMs} ms');
    }
    if (r.transcribedText != null) {
      b.writeln('- **Transcription:** ${r.transcribedText}');
    }
    if (r.errorDetail != null) {
      b.writeln('- **Error:** ${r.errorDetail}');
    }
    if (r.exitCode != null) {
      b.writeln('- **Exit code:** ${r.exitCode}');
    }
    b.writeln();
  }

  return b.toString();
}

/// Runs all [candidates], collects results, writes `.json` + `.md` + `.zip`
/// to [outputDir], then optionally calls [deliveryStep].
///
/// [clock] is an injectable seam (defaults to [DateTime.now]).
/// [context] is the [ProbeContext] passed to every candidate.
/// [deliveryStep] is called with the ZIP path when non-null.
/// [logger] receives progress and outcome lines (defaults to [print]).
///
/// Returns the path to the written ZIP file.
Future<String> runProbeOrchestrator({
  required List<ProbeCandidate> candidates,
  required ProbeContext context,
  required String outputDir,
  required String version,
  DateTime Function()? clock,
  ProbeDeliveryStep? deliveryStep,
  void Function(String)? logger,
}) async {
  final log = logger ?? print;
  final now = (clock ?? DateTime.now)();
  final stem = buildProbeStem(now);

  final dir = Directory(outputDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  // Run each candidate exactly once, emitting progress lines.
  final results = <CandidateResult>[];
  final total = candidates.length;
  for (var i = 0; i < total; i++) {
    final candidate = candidates[i];
    log('${i + 1} von $total — ${candidate.id}');
    final result = await candidate.run(context);
    log('${candidate.id}: ${result.outcome.name}');
    results.add(result);
  }

  final report = ProbeReport(
    timestamp: now,
    results: results,
    version: version,
  );

  final jsonPath = p.join(outputDir, '$stem.json');
  final mdPath = p.join(outputDir, '$stem.md');
  final zipPath = p.join(outputDir, '$stem.zip');

  // Write JSON — sanitized before touching disk.
  final jsonContent = sanitizePaths(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  File(jsonPath).writeAsStringSync(jsonContent);

  // Write Markdown — sanitized before touching disk.
  final mdContent = sanitizePaths(formatProbeReportMarkdown(report));
  File(mdPath).writeAsStringSync(mdContent);

  // Bundle both into ZIP.
  final archive = Archive();
  final jsonBytes = File(jsonPath).readAsBytesSync();
  archive.addFile(ArchiveFile('$stem.json', jsonBytes.length, jsonBytes));
  final mdBytes = File(mdPath).readAsBytesSync();
  archive.addFile(ArchiveFile('$stem.md', mdBytes.length, mdBytes));
  final zipBytes = ZipEncoder().encode(archive);
  File(zipPath).writeAsBytesSync(zipBytes);

  await deliveryStep?.call(zipPath);

  return zipPath;
}
