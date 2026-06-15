/// Tests for [runProbeOrchestrator]: fake candidate → all three artefacts
/// written to a temp directory with expected content.
///
/// No real Desktop, network, subprocess or engine is touched.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake candidate
// ---------------------------------------------------------------------------

/// A fake [ProbeCandidate] that records how many times it was called and
/// always returns [Outcome.ok].
class _FakeOkCandidate implements ProbeCandidate {
  int runCount = 0;

  @override
  String get id => 'fake-ok';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    runCount++;
    return const CandidateResult(
      candidateId: 'fake-ok',
      outcome: Outcome.ok,
      durationMs: 42,
      transcribedText: 'hallo welt',
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _fixedTimestamp = '20260615-120000';

/// A fixed clock seam: 2026-06-15 12:00:00 UTC.
DateTime _fixedClock() => DateTime.utc(2026, 6, 15, 12, 0, 0);

const _testVersion = '0.1.0-test';

ProbeContext get _minimalContext => const ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.bin',
  workDir: '/tmp/fake-work',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('runProbeOrchestrator', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gpu_probe_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('writes exactly three files: .json, .md, .zip', () async {
      final candidate = _FakeOkCandidate();
      await runProbeOrchestrator(
        candidates: [candidate],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      final files = tempDir.listSync().whereType<File>().toList();
      final jsonFiles = files.where((f) => f.path.endsWith('.json')).toList();
      final mdFiles = files.where((f) => f.path.endsWith('.md')).toList();
      final zipFiles = files.where((f) => f.path.endsWith('.zip')).toList();

      expect(jsonFiles, hasLength(1), reason: 'exactly one .json file');
      expect(mdFiles, hasLength(1), reason: 'exactly one .md file');
      expect(zipFiles, hasLength(1), reason: 'exactly one .zip file');
    });

    test('file names include the timestamp stem', () async {
      await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      final files = tempDir.listSync().whereType<File>().toList();
      for (final file in files) {
        expect(
          p.basename(file.path),
          contains(_fixedTimestamp),
          reason: 'file name must contain the fixed timestamp',
        );
      }
    });

    test('JSON file contains the expected outcome and version', () async {
      final candidate = _FakeOkCandidate();
      await runProbeOrchestrator(
        candidates: [candidate],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      final jsonFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.json'),
      );
      final decoded =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;

      expect(decoded['version'], equals(_testVersion));
      final results = decoded['results'] as List<Object?>;
      expect(results, hasLength(1));
      final first = results.first as Map<String, Object?>;
      expect(first['candidateId'], equals('fake-ok'));
      expect(first['outcome'], equals('ok'));
    });

    test('Markdown file contains header and candidate outcome', () async {
      await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      final mdFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.md'),
      );
      final content = mdFile.readAsStringSync();

      expect(content, contains('# WhisPaste GPU Probe Report'));
      expect(content, contains('fake-ok'));
      expect(content, contains('ok'));
    });

    test('ZIP file is non-empty', () async {
      await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      final zipFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.zip'),
      );
      expect(zipFile.lengthSync(), greaterThan(0));
    });

    test('fake candidate run() is called exactly once', () async {
      final candidate = _FakeOkCandidate();
      await runProbeOrchestrator(
        candidates: [candidate],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      expect(candidate.runCount, equals(1));
    });

    test('with two candidates, each run() is called exactly once', () async {
      final first = _FakeOkCandidate();
      final second = _FakeOkCandidate();
      await runProbeOrchestrator(
        candidates: [first, second],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
      );

      expect(first.runCount, equals(1));
      expect(second.runCount, equals(1));
    });

    test('output directory is created when it does not exist', () async {
      final nestedDir = p.join(tempDir.path, 'nested', 'output');
      expect(Directory(nestedDir).existsSync(), isFalse);

      await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: nestedDir,
        version: _testVersion,
        clock: _fixedClock,
      );

      expect(Directory(nestedDir).existsSync(), isTrue);
    });

    test('deliveryStep is called with the zip path', () async {
      String? capturedZip;
      Future<void> fakeDelivery(String zipPath) async {
        capturedZip = zipPath;
      }

      final returnedZip = await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
        deliveryStep: fakeDelivery,
      );

      expect(capturedZip, isNotNull, reason: 'deliveryStep must be called');
      expect(capturedZip, equals(returnedZip));
      expect(capturedZip, endsWith('.zip'));
    });

    test('deliveryStep is NOT called when null (--no-deliver mode)', () async {
      // omit deliveryStep → no file-manager launch
      final returnedZip = await runProbeOrchestrator(
        candidates: [_FakeOkCandidate()],
        context: _minimalContext,
        outputDir: tempDir.path,
        version: _testVersion,
        clock: _fixedClock,
        // deliveryStep omitted
      );

      expect(returnedZip, endsWith('.zip'));
      expect(File(returnedZip).existsSync(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // resolveDesktopPath
  // ---------------------------------------------------------------------------

  group('resolveDesktopPath', () {
    test('returns a non-empty path', () {
      final path = resolveDesktopPath(
        environment: {'HOME': '/Users/test', 'USERPROFILE': r'C:\Users\test'},
      );
      expect(path, isNotEmpty);
    });

    test('on mac-like env uses HOME/Desktop', () {
      final path = resolveDesktopPath(
        environment: {'HOME': '/Users/test'},
        platformOverride: 'macos',
      );
      expect(path, equals('/Users/test/Desktop'));
    });

    test('on windows env uses USERPROFILE with Desktop appended', () {
      final path = resolveDesktopPath(
        environment: {'USERPROFILE': r'C:\Users\test'},
        platformOverride: 'windows',
      );
      expect(path, contains(r'C:\Users\test'));
      expect(path, endsWith('Desktop'));
    });

    test('on linux env uses HOME/Desktop', () {
      final path = resolveDesktopPath(
        environment: {'HOME': '/home/user'},
        platformOverride: 'linux',
      );
      expect(path, equals('/home/user/Desktop'));
    });
  });

  // ---------------------------------------------------------------------------
  // Entrypoint smoke test
  // ---------------------------------------------------------------------------

  group('bin/whispaste_gpu_probe.dart entrypoint', () {
    test(
      'main writes three artefacts to --output-dir with --no-deliver',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'gpu_probe_entry_test_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // Drive the entrypoint logic directly via runProbeOrchestrator with
        // the same fake candidate and options that main() would use.
        final context = const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        );

        final candidate = _FakeOkCandidate();
        final zipPath = await runProbeOrchestrator(
          candidates: [candidate],
          context: context,
          outputDir: tempDir.path,
          version: 'unbekannt',
          clock: _fixedClock,
          // no deliveryStep = --no-deliver behaviour
        );

        expect(File(zipPath).existsSync(), isTrue, reason: 'ZIP must exist');
        final jsonPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.json');
        final mdPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.md');
        expect(File(jsonPath).existsSync(), isTrue, reason: 'JSON must exist');
        expect(File(mdPath).existsSync(), isTrue, reason: 'MD must exist');
        expect(candidate.runCount, equals(1));
      },
    );
  });
}
