/// WhisPaste-Diagnose — standalone CLI entrypoint.
///
/// Gathers the full WhisPaste environment diagnostics, writes a .txt report
/// and a .zip bundle to the user's Desktop, then exits 0.
///
/// Build commands:
///   Windows (on windows-latest runner):
///     dart compile exe bin/whispaste_diagnose.dart -o dist/WhisPaste-Diagnose.exe
///   macOS (arm64, on macos-latest runner):
///     dart compile exe bin/whispaste_diagnose.dart -o dist/WhisPaste-Diagnose
///     (then wrapped into WhisPaste-Diagnose.app by tool/build_app_bundle.sh)
///
/// The orchestration logic lives in [buildAndWriteReport] (injectable seams)
/// so the gather → txt → zip flow is fully unit-testable without this main().
library;

import 'dart:io';

import 'package:whispaste_diagnostics/src/cli/cli_orchestrator.dart';
import 'package:whispaste_diagnostics/src/report/diagnostics_report.dart';

Future<void> main(List<String> args) async {
  // Allow --output-dir override for CI smoke tests so the binary does not
  // write to a potentially non-existent Desktop on the runner.
  String outputDir = resolveDesktopPath();
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--output-dir') {
      outputDir = args[i + 1];
      break;
    }
  }

  try {
    final zipPath = await buildAndWriteReport(
      outputDir: outputDir,
      reportProducer: () async => gatherDiagnosticsReport(),
    );

    final txtPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.txt');
    stderr.writeln('WhisPaste-Diagnose: Report geschrieben nach:');
    stderr.writeln('  $txtPath');
    stderr.writeln('  $zipPath');
    exit(0);
  } on Object catch (e, st) {
    stderr.writeln('WhisPaste-Diagnose: Fehler beim Schreiben des Reports:');
    stderr.writeln('  $e');
    stderr.writeln('  $st');
    exit(1);
  }
}
