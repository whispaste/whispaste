/// AC3: Version stamp in ProbeReport (JSON + Markdown).
///
/// Verifies that the version string passed to [runProbeOrchestrator] (which
/// originates from `--define=whispaste_version=…` at compile time) appears
/// verbatim in both the written `.json` file and the written `.md` file.
///
/// AC4: CI smoke-test simulation via --output-dir / --no-deliver mode.
///
/// Verifies that the entrypoint logic (driven through [runProbeOrchestrator]
/// with no deliveryStep) writes all three artefacts (.json, .md, .zip) and
/// exits successfully. Mirrors what a CI runner does with
/// `WhisPaste-GPU-Probe.exe --output-dir <tmp> --no-deliver`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

class _FakeOkCandidate implements ProbeCandidate {
  const _FakeOkCandidate();

  @override
  String get id => 'fake-version-ok';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    return const CandidateResult(
      candidateId: 'fake-version-ok',
      outcome: Outcome.ok,
      durationMs: 1,
      transcribedText: 'test',
    );
  }
}

DateTime _fixedClock() => DateTime.utc(2026, 6, 15, 9, 0, 0);

const _context = ProbeContext(referenceWavPath: '', modelPath: '', workDir: '');

// ---------------------------------------------------------------------------
// AC3 — Version stamp appears in ProbeReport JSON and Markdown
// ---------------------------------------------------------------------------

void main() {
  group('AC3 — version stamp in ProbeReport', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gpu_probe_version_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('version string appears in JSON output', () async {
      const version = '1.2.39';
      await runProbeOrchestrator(
        candidates: const [_FakeOkCandidate()],
        context: _context,
        outputDir: tempDir.path,
        version: version,
        clock: _fixedClock,
      );

      final jsonFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.json'),
      );
      final decoded =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;

      expect(
        decoded['version'],
        equals(version),
        reason: 'ProbeReport.toJson() must include the stamped version',
      );
    });

    test('version string appears in Markdown output', () async {
      const version = '1.2.39';
      await runProbeOrchestrator(
        candidates: const [_FakeOkCandidate()],
        context: _context,
        outputDir: tempDir.path,
        version: version,
        clock: _fixedClock,
      );

      final mdFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.md'),
      );
      final content = mdFile.readAsStringSync();

      expect(
        content,
        contains('**Version:** $version'),
        reason: 'ProbeReport Markdown must include the stamped version line',
      );
    });

    test(
      'fallback version "unbekannt" appears in JSON when not stamped',
      () async {
        const version = 'unbekannt';
        await runProbeOrchestrator(
          candidates: const [_FakeOkCandidate()],
          context: _context,
          outputDir: tempDir.path,
          version: version,
          clock: _fixedClock,
        );

        final jsonFile = tempDir.listSync().whereType<File>().firstWhere(
          (f) => f.path.endsWith('.json'),
        );
        final decoded =
            jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;

        expect(decoded['version'], equals('unbekannt'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC4 — CI smoke: --output-dir / --no-deliver produces all three artefacts
  // ---------------------------------------------------------------------------

  group('AC4 — CI smoke: --output-dir + --no-deliver', () {
    test('produces .json, .md and .zip; exit is clean (no delivery)', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'gpu_probe_smoke_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Simulate what the compiled exe does when invoked as:
      //   WhisPaste-GPU-Probe.exe --output-dir <tmp> --no-deliver
      // The --no-deliver flag maps to deliveryStep: null.
      final zipPath = await runProbeOrchestrator(
        candidates: const [_FakeOkCandidate()],
        context: _context,
        outputDir: tempDir.path,
        version: 'unbekannt', // no --define stamp in dev/CI ad-hoc run
        clock: _fixedClock,
        // deliveryStep omitted == --no-deliver
      );

      // All three artefacts must exist.
      final jsonPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.json');
      final mdPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.md');

      expect(
        File(zipPath).existsSync(),
        isTrue,
        reason: 'ZIP must be produced by --no-deliver run',
      );
      expect(
        File(jsonPath).existsSync(),
        isTrue,
        reason: 'JSON report must be produced',
      );
      expect(
        File(mdPath).existsSync(),
        isTrue,
        reason: 'Markdown report must be produced',
      );

      // JSON must be valid and contain the expected top-level keys.
      final decoded =
          jsonDecode(File(jsonPath).readAsStringSync()) as Map<String, Object?>;
      expect(decoded.containsKey('timestamp'), isTrue);
      expect(decoded.containsKey('version'), isTrue);
      expect(decoded.containsKey('results'), isTrue);

      // Markdown must include the standard header.
      final mdContent = File(mdPath).readAsStringSync();
      expect(mdContent, contains('# WhisPaste GPU Probe Report'));

      // ZIP must be non-empty.
      expect(File(zipPath).lengthSync(), greaterThan(0));
    });

    test('output-dir is created if it does not exist (nested path)', () async {
      final baseDir = Directory.systemTemp.createTempSync(
        'gpu_probe_smoke_nested_',
      );
      addTearDown(() => baseDir.deleteSync(recursive: true));

      final nestedOutputDir = p.join(baseDir.path, 'sub', 'output');
      expect(Directory(nestedOutputDir).existsSync(), isFalse);

      final zipPath = await runProbeOrchestrator(
        candidates: const [_FakeOkCandidate()],
        context: _context,
        outputDir: nestedOutputDir,
        version: 'unbekannt',
        clock: _fixedClock,
      );

      expect(Directory(nestedOutputDir).existsSync(), isTrue);
      expect(File(zipPath).existsSync(), isTrue);
    });
  });
}
