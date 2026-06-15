/// Golden tests for [ProbeReport.toJson()] and [ProbeReport.toMarkdown()]
/// covering ranking, CPU baseline detection, speedup factors, and the
/// failed-candidate section.
///
/// Uses a fixed [ProbeReport] so the output is deterministic.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fixed test data
// ---------------------------------------------------------------------------

/// CPU baseline — 4 000 ms, WER 5 %.
const _cpuResult = CandidateResult(
  candidateId: 'whisper-cpp-cpu',
  outcome: Outcome.ok,
  durationMs: 4000,
  transcribedText: 'hallo welt',
  wer: 0.05,
  realtimeFactor: 0.5,
  backend: 'cpu',
);

/// Fast GPU — 1 000 ms, WER 3 % → speedup 4.0×.
const _gpuFastResult = CandidateResult(
  candidateId: 'whisper-cpp-cuda',
  outcome: Outcome.ok,
  durationMs: 1000,
  transcribedText: 'hallo welt',
  wer: 0.03,
  realtimeFactor: 0.125,
  backend: 'cuda',
);

/// Slower GPU — 2 000 ms, WER 6 % → speedup 2.0×.
const _gpuSlowResult = CandidateResult(
  candidateId: 'whisper-cpp-vulkan',
  outcome: Outcome.ok,
  durationMs: 2000,
  transcribedText: 'hallo welt',
  wer: 0.06,
  realtimeFactor: 0.25,
  backend: 'vulkan',
);

/// Crashed candidate — no duration.
const _crashedResult = CandidateResult(
  candidateId: 'whisper-cpp-metal',
  outcome: Outcome.crashed,
  exitCode: 1,
  errorDetail: 'Metal not supported',
);

/// OOM candidate.
const _oomResult = CandidateResult(
  candidateId: 'whisper-cpp-opencl',
  outcome: Outcome.outOfMemory,
  errorDetail: 'VRAM exhausted',
);

final _hardware = HardwareContext(
  cpuModel: 'Intel Core i7-12700K',
  ramGb: 32,
  gpuModel: 'NVIDIA GeForce RTX 3070',
  vramGb: 8,
  os: 'Windows 11 23H2',
  driverVersion: '546.33',
);

final _fixedTimestamp = DateTime.utc(2026, 6, 15, 12, 0, 0);

ProbeReport _buildReport({
  bool includeCpu = true,
  bool includeHardware = true,
}) {
  final results = <CandidateResult>[
    if (includeCpu) _cpuResult,
    _gpuFastResult,
    _gpuSlowResult,
    _crashedResult,
    _oomResult,
  ];
  return ProbeReport(
    timestamp: _fixedTimestamp,
    results: results,
    version: '0.1.0-test',
    hardwareContext: includeHardware ? _hardware : null,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // AC1: CPU baseline
  // -------------------------------------------------------------------------
  group('AC1 — CPU baseline is mandatory reference', () {
    test('isCpuBaseline identifies candidate by id prefix', () {
      expect(isCpuBaseline(_cpuResult), isTrue);
      expect(isCpuBaseline(_gpuFastResult), isFalse);
    });

    test('isCpuBaseline identifies candidate by backend=cpu', () {
      const r = CandidateResult(
        candidateId: 'some-other-id',
        outcome: Outcome.ok,
        backend: 'cpu',
      );
      expect(isCpuBaseline(r), isTrue);
    });

    test('ranking.cpuBaseline is set when CPU candidate is present', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      expect(ranking.cpuBaselineMissing, isFalse);
      expect(ranking.cpuBaseline?.candidateId, equals('whisper-cpp-cpu'));
    });

    test('ranking flags cpuBaselineMissing when no CPU candidate', () {
      final report = _buildReport(includeCpu: false);
      final ranking = computeRanking(report);
      expect(ranking.cpuBaselineMissing, isTrue);
      expect(ranking.cpuBaseline, isNull);
    });

    test('toJson ranking.cpuBaselineMissing is false when CPU present', () {
      final report = _buildReport();
      final json = report.toJson();
      final ranking = json['ranking'] as Map<String, Object?>;
      expect(ranking['cpuBaselineMissing'], isFalse);
      expect(ranking['cpuBaselineCandidateId'], equals('whisper-cpp-cpu'));
    });

    test('toJson ranking.cpuBaselineMissing is true when CPU absent', () {
      final report = _buildReport(includeCpu: false);
      final json = report.toJson();
      final ranking = json['ranking'] as Map<String, Object?>;
      expect(ranking['cpuBaselineMissing'], isTrue);
    });

    test('toMarkdown contains WARNING when CPU baseline missing', () {
      final report = _buildReport(includeCpu: false);
      final md = report.toMarkdown();
      expect(md, contains('WARNING: CPU baseline missing'));
    });

    test('toMarkdown does NOT warn when CPU baseline is present', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, isNot(contains('WARNING: CPU baseline missing')));
    });
  });

  // -------------------------------------------------------------------------
  // AC2: GPU candidates ranked by speedup, with baseline = 1.0×
  // -------------------------------------------------------------------------
  group('AC2 — GPU candidates ranked by speed desc, WER asc', () {
    test('CPU baseline has speedupFactor 1.0', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      final baseline = ranking.ranked.firstWhere((rc) => rc.isCpuBaseline);
      expect(baseline.speedupFactor, equals(1.0));
    });

    test('fast GPU has speedupFactor 4.0 (4000/1000)', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      final fast = ranking.ranked.firstWhere(
        (rc) => rc.result.candidateId == 'whisper-cpp-cuda',
      );
      expect(fast.speedupFactor, closeTo(4.0, 0.001));
    });

    test('slow GPU has speedupFactor 2.0 (4000/2000)', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      final slow = ranking.ranked.firstWhere(
        (rc) => rc.result.candidateId == 'whisper-cpp-vulkan',
      );
      expect(slow.speedupFactor, closeTo(2.0, 0.001));
    });

    test(
      'ranked list is sorted: cuda (4×) before vulkan (2×) before cpu (1×)',
      () {
        final report = _buildReport();
        final ranking = computeRanking(report);
        final ids = ranking.ranked.map((rc) => rc.result.candidateId).toList();
        expect(
          ids.indexOf('whisper-cpp-cuda'),
          lessThan(ids.indexOf('whisper-cpp-vulkan')),
        );
        expect(
          ids.indexOf('whisper-cpp-vulkan'),
          lessThan(ids.indexOf('whisper-cpp-cpu')),
        );
      },
    );

    test('toJson ranked list matches expected order', () {
      final report = _buildReport();
      final json = report.toJson();
      final ranking = json['ranking'] as Map<String, Object?>;
      final ranked = ranking['ranked'] as List<Object?>;
      expect(ranked, hasLength(3)); // cpu + 2 gpu ok candidates
      final firstId = (ranked[0] as Map<String, Object?>)['candidateId'];
      final secondId = (ranked[1] as Map<String, Object?>)['candidateId'];
      final thirdId = (ranked[2] as Map<String, Object?>)['candidateId'];
      expect(firstId, equals('whisper-cpp-cuda'));
      expect(secondId, equals('whisper-cpp-vulkan'));
      expect(thirdId, equals('whisper-cpp-cpu'));
    });

    test('toMarkdown ranking table shows cuda before vulkan before cpu', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      final cudaPos = md.indexOf('whisper-cpp-cuda');
      final vulkanPos = md.indexOf('whisper-cpp-vulkan');
      final cpuPos = md.indexOf('whisper-cpp-cpu');
      // All three must appear
      expect(cudaPos, greaterThanOrEqualTo(0));
      expect(vulkanPos, greaterThanOrEqualTo(0));
      expect(cpuPos, greaterThanOrEqualTo(0));
      // Ranking order
      expect(cudaPos, lessThan(vulkanPos));
      expect(vulkanPos, lessThan(cpuPos));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: Non-ok candidates outside speed ranking
  // -------------------------------------------------------------------------
  group('AC3 — non-ok candidates in failed section', () {
    test('crashed and oom are in ranking.failed', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      final failedIds = ranking.failed.map((r) => r.candidateId).toSet();
      expect(failedIds, contains('whisper-cpp-metal'));
      expect(failedIds, contains('whisper-cpp-opencl'));
    });

    test('failed candidates are NOT in ranking.ranked', () {
      final report = _buildReport();
      final ranking = computeRanking(report);
      final rankedIds = ranking.ranked
          .map((rc) => rc.result.candidateId)
          .toSet();
      expect(rankedIds, isNot(contains('whisper-cpp-metal')));
      expect(rankedIds, isNot(contains('whisper-cpp-opencl')));
    });

    test('toJson failed list contains crashed and oom with outcome', () {
      final report = _buildReport();
      final json = report.toJson();
      final ranking = json['ranking'] as Map<String, Object?>;
      final failed = ranking['failed'] as List<Object?>;
      expect(failed, hasLength(2));
      final failedMap = failed.map((e) => e as Map<String, Object?>).toList();
      final outcomes = failedMap.map((m) => m['outcome']).toSet();
      expect(outcomes, containsAll(['crashed', 'outOfMemory']));
    });

    test('toMarkdown shows failed candidates with outcome', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('whisper-cpp-metal'));
      expect(md, contains('crashed'));
      expect(md, contains('whisper-cpp-opencl'));
      expect(md, contains('outOfMemory'));
    });
  });

  // -------------------------------------------------------------------------
  // AC4: Golden JSON / Markdown structure
  // -------------------------------------------------------------------------
  group('AC4 — toJson / toMarkdown golden structure', () {
    test('toJson top-level keys present', () {
      final report = _buildReport();
      final json = report.toJson();
      expect(
        json.keys,
        containsAll(['timestamp', 'version', 'results', 'ranking']),
      );
    });

    test('toJson timestamp is ISO-8601', () {
      final report = _buildReport();
      final json = report.toJson();
      expect(json['timestamp'], equals('2026-06-15T12:00:00.000Z'));
    });

    test('toJson hardwareContext present when provided', () {
      final report = _buildReport();
      final json = report.toJson();
      final hw = json['hardwareContext'] as Map<String, Object?>;
      expect(hw['cpuModel'], equals('Intel Core i7-12700K'));
      expect(hw['gpuModel'], equals('NVIDIA GeForce RTX 3070'));
      expect(hw['vramGb'], equals(8));
      expect(hw['driverVersion'], equals('546.33'));
    });

    test('toJson hardwareContext absent when not provided', () {
      final report = _buildReport(includeHardware: false);
      final json = report.toJson();
      expect(json.containsKey('hardwareContext'), isFalse);
    });

    test('toJson is valid JSON (round-trip via jsonEncode/jsonDecode)', () {
      final report = _buildReport();
      final encoded = jsonEncode(report.toJson());
      final decoded = jsonDecode(encoded);
      expect(decoded, isA<Map<String, dynamic>>());
    });

    test('toMarkdown contains main header', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, startsWith('# WhisPaste GPU Probe Report'));
    });

    test('toMarkdown contains hardware context section', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('## Hardware Context'));
      expect(md, contains('Intel Core i7-12700K'));
      expect(md, contains('NVIDIA GeForce RTX 3070'));
    });

    test('toMarkdown contains speed ranking table header', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('## Speed Ranking'));
      expect(md, contains('Speedup vs CPU'));
    });

    test('toMarkdown contains outcome overview section', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('## Outcome Overview'));
    });

    test('toMarkdown CPU baseline row marked as baseline', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('*(baseline)*'));
    });

    test('toMarkdown speedup 4.00× shown for cuda candidate', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('4.00×'));
    });

    test('toMarkdown hardware context absent when not provided', () {
      final report = _buildReport(includeHardware: false);
      final md = report.toMarkdown();
      expect(md, isNot(contains('## Hardware Context')));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: Realtime factor shown, not used as gate
  // -------------------------------------------------------------------------
  group('AC5 — realtime factor displayed, never a pass/fail gate', () {
    test('toJson includes realtimeFactor in results when present', () {
      final report = _buildReport();
      final json = report.toJson();
      final results = json['results'] as List<Object?>;
      final cpuRow = (results as List)
          .map((e) => e as Map<String, Object?>)
          .firstWhere((m) => m['candidateId'] == 'whisper-cpp-cpu');
      expect(cpuRow['realtimeFactor'], equals(0.5));
    });

    test('toMarkdown shows RTF column in outcome overview', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      expect(md, contains('RTF'));
      expect(md, contains('0.50')); // CPU RTF
    });

    test('toMarkdown shows RTF column in ranking table', () {
      final report = _buildReport();
      final md = report.toMarkdown();
      // RTF appears in ranking table header
      final rankingStart = md.indexOf('## Speed Ranking');
      final rankingSection = md.substring(rankingStart);
      expect(rankingSection, contains('RTF'));
    });

    test('computeRanking does not filter by realtimeFactor', () {
      // A candidate with a high RTF (slow) should still be in ranked if ok.
      const slowRtfResult = CandidateResult(
        candidateId: 'whisper-cpp-cpu',
        outcome: Outcome.ok,
        durationMs: 10000,
        realtimeFactor: 10.0, // very slow, but still ok
        backend: 'cpu',
      );
      final report = ProbeReport(
        timestamp: _fixedTimestamp,
        results: [slowRtfResult],
        version: '0.1.0-test',
      );
      final ranking = computeRanking(report);
      expect(ranking.ranked, hasLength(1));
      expect(ranking.failed, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // AC6 is checked by gate commands (format + analyze)
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Edge cases
  // -------------------------------------------------------------------------
  group('Edge cases', () {
    test('empty results list produces empty ranked and failed', () {
      final report = ProbeReport(
        timestamp: _fixedTimestamp,
        results: const [],
        version: '0.1.0-test',
      );
      final ranking = computeRanking(report);
      expect(ranking.ranked, isEmpty);
      expect(ranking.failed, isEmpty);
      expect(ranking.cpuBaselineMissing, isTrue);
    });

    test('ok candidate without durationMs gets speedup 0.0', () {
      const noDur = CandidateResult(
        candidateId: 'whisper-cpp-cuda',
        outcome: Outcome.ok,
        backend: 'cuda',
      );
      final report = ProbeReport(
        timestamp: _fixedTimestamp,
        results: [_cpuResult, noDur],
        version: '0.1.0-test',
      );
      final ranking = computeRanking(report);
      final noDurRow = ranking.ranked.firstWhere(
        (rc) => rc.result.candidateId == 'whisper-cpp-cuda',
      );
      expect(noDurRow.speedupFactor, equals(0.0));
    });

    test('toMarkdown RTF shows — when realtimeFactor is null', () {
      final report = ProbeReport(
        timestamp: _fixedTimestamp,
        results: const [
          CandidateResult(
            candidateId: 'whisper-cpp-cpu',
            outcome: Outcome.ok,
            durationMs: 4000,
            backend: 'cpu',
          ),
        ],
        version: '0.1.0-test',
      );
      final md = report.toMarkdown();
      // RTF column should contain — for missing value
      expect(md, contains('—'));
    });

    test('tie-break by WER: same speedup, lower WER ranks first', () {
      const fastLowWer = CandidateResult(
        candidateId: 'gpu-a',
        outcome: Outcome.ok,
        durationMs: 1000,
        wer: 0.02,
        backend: 'cuda',
      );
      const fastHighWer = CandidateResult(
        candidateId: 'gpu-b',
        outcome: Outcome.ok,
        durationMs: 1000,
        wer: 0.08,
        backend: 'vulkan',
      );
      final report = ProbeReport(
        timestamp: _fixedTimestamp,
        results: [_cpuResult, fastHighWer, fastLowWer],
        version: '0.1.0-test',
      );
      final ranking = computeRanking(report);
      final ids = ranking.ranked.map((rc) => rc.result.candidateId).toList();
      expect(ids.indexOf('gpu-a'), lessThan(ids.indexOf('gpu-b')));
    });
  });
}
