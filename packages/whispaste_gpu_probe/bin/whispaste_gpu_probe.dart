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
  // --no-deliver suppresses file-manager reveal + mail (used in CI).
  var skipDelivery = false;
  // --demo renders a representative synthetic report for preview purposes.
  var demoMode = false;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--output-dir' && i + 1 < args.length) {
      outputDir = args[i + 1];
    }
    if (args[i] == '--no-deliver') {
      skipDelivery = true;
    }
    if (args[i] == '--demo') {
      demoMode = true;
    }
  }

  try {
    final String zipPath;

    if (demoMode) {
      // --demo: build a synthetic representative report without running any
      // real engine. Useful for previewing the HTML output.
      final demoReport = buildDemoReport();
      final demoVersion = version == 'unbekannt' ? 'demo' : '$version-demo';

      // Wrap each synthetic result in a fake candidate so the orchestrator
      // can drive the standard pipeline (file writing, ZIP, delivery).
      final demoCandidates = demoReport.results
          .map<ProbeCandidate>((r) => _FixedResultCandidate(r))
          .toList();

      zipPath = await runProbeOrchestrator(
        candidates: demoCandidates,
        context: const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        ),
        outputDir: outputDir,
        version: demoVersion,
        deliveryStep: skipDelivery
            ? null
            : (zip) => deliverReport(zip, launcher: defaultDeliveryLauncher),
      );

      stderr.writeln(
        'WhisPaste-GPU-Probe (Demo-Modus): Report geschrieben nach:',
      );
    } else {
      // Minimal ProbeContext for the skeleton — no real WAV or model needed
      // because the fake candidate ignores them.
      const context = ProbeContext(
        referenceWavPath: '',
        modelPath: '',
        workDir: '',
      );

      zipPath = await runProbeOrchestrator(
        candidates: const [_FakeOkCandidate()],
        context: context,
        outputDir: outputDir,
        version: version,
        deliveryStep: skipDelivery
            ? null
            : (zip) => deliverReport(zip, launcher: defaultDeliveryLauncher),
      );

      stderr.writeln('WhisPaste-GPU-Probe: Report geschrieben nach:');
    }

    final jsonPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.json');
    final mdPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.md');
    final htmlPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.html');
    stderr.writeln('  $jsonPath');
    stderr.writeln('  $mdPath');
    stderr.writeln('  $htmlPath');
    stderr.writeln('  $zipPath');
    exit(0);
  } on Object catch (e, st) {
    stderr.writeln('WhisPaste-GPU-Probe: Fehler beim Schreiben des Reports:');
    stderr.writeln('  $e');
    stderr.writeln('  $st');
    exit(1);
  }
}

/// A [ProbeCandidate] that always returns a fixed pre-built [CandidateResult].
///
/// Used in `--demo` mode to replay synthetic results through the standard
/// orchestrator pipeline without running any real engine.
class _FixedResultCandidate implements ProbeCandidate {
  const _FixedResultCandidate(this._result);

  final CandidateResult _result;

  @override
  String get id => _result.candidateId;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async => _result;
}
