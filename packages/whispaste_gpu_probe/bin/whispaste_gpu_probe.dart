/// WhisPaste-GPU-Probe — standalone CLI entrypoint.
///
/// Runs a list of GPU probe candidates against a reference WAV + model,
/// writes a JSON + Markdown report and a ZIP bundle to the user's Desktop,
/// then exits 0.
///
/// Build commands:
///   Windows (on windows-latest runner):
///     dart compile exe bin/whispaste_gpu_probe.dart -o dist/WhisPaste-GPU-Probe.exe
///   macOS (arm64, on macos-latest runner):
///     dart compile exe bin/whispaste_gpu_probe.dart -o dist/WhisPaste-GPU-Probe
///
/// The orchestration logic lives in [runProbeOrchestrator] (injectable seams)
/// so the flow is fully unit-testable without this main().
library;

import 'dart:io';

import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

/// Fake candidate used for the tracer-bullet skeleton.
/// Returns an `ok` result immediately without touching any real engine.
class _FakeOkCandidate implements ProbeCandidate {
  const _FakeOkCandidate();

  @override
  String get id => 'fake-ok';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    return const CandidateResult(
      candidateId: 'fake-ok',
      outcome: Outcome.ok,
      durationMs: 0,
      transcribedText: 'fake transcription',
    );
  }
}

Future<void> main(List<String> args) async {
  // Stamp the report with the build version passed at compile time
  // (`dart compile exe --define=whispaste_version=<X>`). Falls back to
  // 'unbekannt' for ad-hoc local builds without the define.
  const version = String.fromEnvironment(
    'whispaste_version',
    defaultValue: 'unbekannt',
  );

  // Allow --output-dir override for CI smoke tests so the binary does not
  // write to a potentially non-existent Desktop on the runner.
  String outputDir = resolveDesktopPath();
  // --no-deliver suppresses file-manager reveal (used in CI).
  var skipDelivery = false;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--output-dir' && i + 1 < args.length) {
      outputDir = args[i + 1];
    }
    if (args[i] == '--no-deliver') {
      skipDelivery = true;
    }
  }

  // Minimal ProbeContext for the skeleton — no real WAV or model needed
  // because the fake candidate ignores them.
  const context = ProbeContext(
    referenceWavPath: '',
    modelPath: '',
    workDir: '',
  );

  try {
    final zipPath = await runProbeOrchestrator(
      candidates: const [_FakeOkCandidate()],
      context: context,
      outputDir: outputDir,
      version: version,
      deliveryStep: skipDelivery ? null : _revealZip,
    );

    final jsonPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.json');
    final mdPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.md');
    stderr.writeln('WhisPaste-GPU-Probe: Report geschrieben nach:');
    stderr.writeln('  $jsonPath');
    stderr.writeln('  $mdPath');
    stderr.writeln('  $zipPath');
    exit(0);
  } on Object catch (e, st) {
    stderr.writeln('WhisPaste-GPU-Probe: Fehler beim Schreiben des Reports:');
    stderr.writeln('  $e');
    stderr.writeln('  $st');
    exit(1);
  }
}

/// Opens the containing folder of the ZIP in the platform file manager.
Future<void> _revealZip(String zipPath) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', zipPath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,$zipPath']);
    } else {
      final parent = zipPath.substring(0, zipPath.lastIndexOf('/'));
      await Process.run('xdg-open', [parent]);
    }
  } on Object {
    // Best-effort: don't abort if reveal fails.
  }
}
