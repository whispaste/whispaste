/// Tests for the --demo entrypoint mode.
///
/// Verifies that invoking the demo logic (via a shared demo builder function)
/// produces a report where const-me-directcompute is the top non-baseline
/// ok candidate, and all expected candidates appear with correct outcomes.
///
/// No real subprocesses or engines are invoked.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('--demo mode', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gpu_probe_demo_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'demo report has const-me-directcompute as top non-baseline ok candidate',
      () async {
        final report = buildDemoReport();
        final ranking = computeRanking(report);

        // Find the best non-baseline candidate.
        final nonBaseline = ranking.ranked
            .where((rc) => !rc.isCpuBaseline)
            .toList();
        expect(
          nonBaseline,
          isNotEmpty,
          reason: 'must have at least one non-baseline ok candidate',
        );
        expect(
          nonBaseline.first.result.candidateId,
          equals('const-me-directcompute'),
        );
      },
    );

    test('demo report has cpu baseline with id whisper-cpp-cpu', () {
      final report = buildDemoReport();
      final ranking = computeRanking(report);
      expect(ranking.cpuBaselineMissing, isFalse);
      expect(ranking.cpuBaseline?.candidateId, equals('whisper-cpp-cpu'));
    });

    test('demo report const-me speedup is approximately 6x', () {
      final report = buildDemoReport();
      final ranking = computeRanking(report);
      final winner = ranking.ranked.firstWhere(
        (rc) => rc.result.candidateId == 'const-me-directcompute',
      );
      // 48000/8000 = 6.0
      expect(winner.speedupFactor, closeTo(6.0, 0.01));
    });

    test('demo report has failed candidates: hung, crashed, skipped', () {
      final report = buildDemoReport();
      final ranking = computeRanking(report);
      final failedIds = ranking.failed.map((r) => r.candidateId).toSet();
      expect(failedIds, contains('whisper-cpp-vulkan'));
      expect(failedIds, contains('whisper-cpp-cuda12'));
      expect(failedIds, contains('whisper-cpp-cpu-medium'));
    });

    test('demo report has correct outcome for whisper-cpp-vulkan (hung)', () {
      final report = buildDemoReport();
      final vulkan = report.results.firstWhere(
        (r) => r.candidateId == 'whisper-cpp-vulkan',
      );
      expect(vulkan.outcome, equals(Outcome.hung));
    });

    test(
      'demo report has correct outcome for whisper-cpp-cuda12 (crashed)',
      () {
        final report = buildDemoReport();
        final cuda = report.results.firstWhere(
          (r) => r.candidateId == 'whisper-cpp-cuda12',
        );
        expect(cuda.outcome, equals(Outcome.crashed));
      },
    );

    test(
      'demo report has correct outcome for whisper-cpp-cpu-medium (skipped)',
      () {
        final report = buildDemoReport();
        final medium = report.results.firstWhere(
          (r) => r.candidateId == 'whisper-cpp-cpu-medium',
        );
        expect(medium.outcome, equals(Outcome.skipped));
      },
    );

    test('demo report has hardware context with GPU GTX 650', () {
      final report = buildDemoReport();
      expect(report.hardwareContext, isNotNull);
      expect(report.hardwareContext!.gpuModel, contains('GTX 650'));
    });

    test(
      'runProbeOrchestrator with demo candidates writes HTML containing winner',
      () async {
        // Build the demo report and write it via the orchestrator.
        final report = buildDemoReport();

        // Write artefacts manually using the orchestrator flow via fake candidates.
        final zipPath = await runProbeOrchestrator(
          candidates: report.results
              .map((r) => _FixedResultCandidate(r))
              .toList(),
          context: const ProbeContext(
            referenceWavPath: '',
            modelPath: '',
            workDir: '',
          ),
          outputDir: tempDir.path,
          version: '0.1.0-demo',
          // no deliveryStep
        );

        final htmlPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.html');
        expect(
          File(htmlPath).existsSync(),
          isTrue,
          reason: 'HTML file must exist',
        );
        final html = File(htmlPath).readAsStringSync();
        expect(
          html,
          contains('const-me-directcompute'),
          reason: 'winner must appear in HTML',
        );
        expect(html, contains('<!DOCTYPE html>'));
      },
    );

    test(
      'demo JSON written by orchestrator contains const-me as first ranked non-baseline',
      () async {
        final report = buildDemoReport();
        final zipPath = await runProbeOrchestrator(
          candidates: report.results
              .map((r) => _FixedResultCandidate(r))
              .toList(),
          context: const ProbeContext(
            referenceWavPath: '',
            modelPath: '',
            workDir: '',
          ),
          outputDir: tempDir.path,
          version: '0.1.0-demo',
        );

        final jsonPath = zipPath.replaceAll(RegExp(r'\.zip$'), '.json');
        final decoded =
            jsonDecode(File(jsonPath).readAsStringSync())
                as Map<String, Object?>;
        final ranking = decoded['ranking'] as Map<String, Object?>;
        final ranked = ranking['ranked'] as List<Object?>;

        // First ranked candidate that is not the baseline should be const-me.
        final nonBaseline = ranked
            .cast<Map<String, Object?>>()
            .where((m) => m['isCpuBaseline'] != true)
            .toList();
        expect(nonBaseline, isNotEmpty);
        expect(
          nonBaseline.first['candidateId'],
          equals('const-me-directcompute'),
        );
      },
    );

    test('demo stem path uses --output-dir', () async {
      final report = buildDemoReport();
      final nestedDir = p.join(tempDir.path, 'demo-output');

      await runProbeOrchestrator(
        candidates: report.results
            .map((r) => _FixedResultCandidate(r))
            .toList(),
        context: const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        ),
        outputDir: nestedDir,
        version: '0.1.0-demo',
      );

      expect(Directory(nestedDir).existsSync(), isTrue);
      final files = Directory(nestedDir).listSync().whereType<File>().toList();
      expect(files.any((f) => f.path.endsWith('.html')), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that always returns a fixed [CandidateResult].
class _FixedResultCandidate implements ProbeCandidate {
  const _FixedResultCandidate(this._result);

  final CandidateResult _result;

  @override
  String get id => _result.candidateId;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async => _result;
}
