/// WhisPaste-GPU-Probe — standalone CLI entrypoint.
///
/// Default (serve mode): starts a local loopback server, opens the browser at
/// an "Analyse läuft…" page, streams per-candidate progress, then serves the
/// finished report with a live microphone test. Runs until the report's
/// "Tool beenden" button (or the window) closes it. The JSON/MD/HTML/ZIP
/// artifacts are written to the Desktop once the probe finishes.
///
/// Flags:
///   --serve / --no-serve   serve mode (default on) vs. one-shot write+exit
///   --demo                 render a representative synthetic report
///   --no-deliver           do not open the browser / reveal in file manager
///   --output-dir PATH      override the artifact output directory
///
/// Build commands:
///   Windows:  dart compile exe bin/whispaste_gpu_probe.dart -o dist/WhisPaste-GPU-Probe.exe
///   macOS:    dart compile exe bin/whispaste_gpu_probe.dart -o dist/WhisPaste-GPU-Probe
///
/// All orchestration lives in injectable seams (runProbeOrchestrator,
/// runLiveProbe) so the flow is fully unit-testable without this main().
library;

import 'dart:io';

import 'package:path/path.dart' as p;
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

/// A [ProbeCandidate] that always returns a fixed pre-built [CandidateResult].
///
/// Used in `--demo` mode to replay synthetic results through the standard
/// pipeline (probe loop, live server, artifact writing) without a real engine.
class _FixedResultCandidate implements ProbeCandidate {
  const _FixedResultCandidate(this._result);

  final CandidateResult _result;

  @override
  String get id => _result.candidateId;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async => _result;
}

/// Wraps a candidate with an artificial delay. Used ONLY for `--demo` serve
/// runs so the "Analyse läuft…" progress shell is actually visible — real
/// engines take seconds on their own, the synthetic demo candidates do not.
class _DelayedCandidate implements ProbeCandidate {
  const _DelayedCandidate(this._inner, this._delay);

  final ProbeCandidate _inner;
  final Duration _delay;

  @override
  String get id => _inner.id;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    await Future<void>.delayed(_delay);
    return _inner.run(ctx);
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

  var outputDir = resolveDesktopPath();
  var outputDirExplicit = false;
  var skipDelivery = false;
  var demoMode = false;
  var serve = true;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--output-dir' && i + 1 < args.length) {
      outputDir = args[i + 1];
      outputDirExplicit = true;
    } else if (a == '--no-deliver') {
      skipDelivery = true;
    } else if (a == '--demo') {
      demoMode = true;
    } else if (a == '--serve') {
      serve = true;
    } else if (a == '--no-serve') {
      serve = false;
    }
  }

  try {
    if (serve) {
      await _runServe(
        version: version,
        outputDir: outputDir,
        outputDirExplicit: outputDirExplicit,
        demoMode: demoMode,
        openBrowser: !skipDelivery,
      );
    } else {
      await _runOneShot(
        version: version,
        outputDir: outputDir,
        demoMode: demoMode,
        skipDelivery: skipDelivery,
      );
    }
    exit(0);
  } on Object catch (e, st) {
    stderr.writeln('WhisPaste-GPU-Probe: Fehler:');
    stderr.writeln('  $e');
    stderr.writeln('  $st');
    exit(1);
  }
}

/// Serve mode: progress shell → live report → live microphone test.
Future<void> _runServe({
  required String version,
  required String outputDir,
  required bool outputDirExplicit,
  required bool demoMode,
  required bool openBrowser,
}) async {
  // Default the on-disk output (log + any artifacts) NEXT TO THE EXE rather than
  // the Desktop — the interactive bench is the product and its results persist
  // in bench-history.jsonl next to the exe, so dumping report bundles on the
  // Desktop on every launch is just clutter. An explicit --output-dir wins.
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final effectiveOutputDir = outputDirExplicit ? outputDir : exeDir;

  final List<ProbeCandidate> candidates;
  final HardwareContext? hardware;
  final String effVersion;
  ModelStore? modelStore;
  List<ProbeEngine>? engines;
  BenchHistory? history;

  if (demoMode) {
    final demo = buildDemoReport();
    candidates = demo.results
        .map<ProbeCandidate>(
          (r) => _DelayedCandidate(
            _FixedResultCandidate(r),
            const Duration(milliseconds: 1100),
          ),
        )
        .toList();
    hardware = demo.hardwareContext;
    effVersion = version == 'unbekannt' ? 'demo' : '$version-demo';
  } else {
    // Real bench: engines (whisper.cpp family, CPU bundled next to the exe)
    // and an on-demand model catalogue stored alongside the exe. The auto-probe
    // ranking is intentionally empty — the bench is interactive (download a
    // model, then run the live test against engine × model).
    modelStore = ModelStore(directory: p.join(exeDir, 'models'));
    engines = defaultEngineRegistry(exeDir: exeDir);
    // Persistent benchmark history travels with the tool install (next to exe).
    history = BenchHistory(File(p.join(exeDir, 'bench-history.jsonl')));
    candidates = const <ProbeCandidate>[];
    hardware = null;
    effVersion = version;
  }

  // Persistent log file next to the exe — for field debugging and so beta
  // testers can send back a diagnostic trail. Tees every log line to stderr
  // (visible console) and the file.
  final logDir = Directory(effectiveOutputDir);
  if (!logDir.existsSync()) logDir.createSync(recursive: true);
  final logFile = File(p.join(effectiveOutputDir, 'WhisPaste-GPU-Probe.log'));
  void log(String m) {
    stderr.writeln(m);
    try {
      logFile.writeAsStringSync(
        '${DateTime.now().toIso8601String()}  $m\n',
        mode: FileMode.append,
      );
    } on Object catch (e) {
      stderr.writeln('WhisPaste-GPU-Probe: Log-Schreiben fehlgeschlagen: $e');
    }
  }

  log('=== WhisPaste-GPU-Probe $effVersion gestartet (serve) ===');

  await runLiveProbe(
    candidates: candidates,
    context: const ProbeContext(
      referenceWavPath: '',
      modelPath: '',
      workDir: '',
    ),
    version: effVersion,
    hardwareContext: hardware,
    modelStore: modelStore,
    engines: engines,
    history: history,
    logger: log,
    openBrowser: (url) async {
      stderr.writeln('WhisPaste-GPU-Probe: Server läuft auf $url');
      stderr.writeln(
        '  Der Report öffnet sich im Browser. Zum Beenden den '
        '„Tool beenden"-Knopf klicken oder dieses Fenster schließen.',
      );
      if (openBrowser) {
        final cmd = openInBrowserCommand(url.toString());
        await defaultDeliveryLauncher(cmd.first, cmd.sublist(1));
      }
    },
    onComplete: (report) async {
      // The interactive bench has no auto-probe results — don't write an empty
      // report bundle (that was the Desktop clutter). Only archive when there
      // is something to archive (e.g. demo mode).
      if (report.results.isEmpty) return;
      final stem = buildProbeStem(report.timestamp);
      final zipPath = writeProbeArtifacts(
        report: report,
        outputDir: effectiveOutputDir,
        stem: stem,
      );
      stderr.writeln('WhisPaste-GPU-Probe: Report-Artefakte geschrieben:');
      stderr.writeln('  $zipPath');
    },
  );
}

/// One-shot mode: run, write artifacts, optionally reveal/open, exit.
Future<void> _runOneShot({
  required String version,
  required String outputDir,
  required bool demoMode,
  required bool skipDelivery,
}) async {
  ProbeDeliveryStep? delivery() => skipDelivery
      ? null
      : (zip) => deliverReport(zip, launcher: defaultDeliveryLauncher);

  final String zipPath;
  if (demoMode) {
    final demoReport = buildDemoReport();
    final demoVersion = version == 'unbekannt' ? 'demo' : '$version-demo';
    final demoCandidates = demoReport.results
        .map<ProbeCandidate>(_FixedResultCandidate.new)
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
      deliveryStep: delivery(),
    );
    stderr.writeln(
      'WhisPaste-GPU-Probe (Demo-Modus): Report geschrieben nach:',
    );
  } else {
    zipPath = await runProbeOrchestrator(
      candidates: const [_FakeOkCandidate()],
      context: const ProbeContext(
        referenceWavPath: '',
        modelPath: '',
        workDir: '',
      ),
      outputDir: outputDir,
      version: version,
      deliveryStep: delivery(),
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
}
