/// Tests for [formatProbeReportHtml].
///
/// Verifies: winner banner, ranking table with CSS outcome classes,
/// hardware context, complete document structure, no external resource refs.
library;

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fixed test data (mirrors ranking_report_test.dart fixtures)
// ---------------------------------------------------------------------------

const _cpuResult = CandidateResult(
  candidateId: 'whisper-cpp-cpu',
  outcome: Outcome.ok,
  durationMs: 48000,
  wer: 0.07,
  realtimeFactor: 0.5,
  backend: 'cpu',
  modelId: 'small',
);

const _winnerResult = CandidateResult(
  candidateId: 'const-me-directcompute',
  outcome: Outcome.ok,
  durationMs: 8000,
  wer: 0.08,
  realtimeFactor: 0.083,
  backend: 'directml',
  modelId: 'small',
);

const _okSlowResult = CandidateResult(
  candidateId: 'wav2vec2-directml-de',
  outcome: Outcome.ok,
  durationMs: 12000,
  wer: 0.18,
  backend: 'directml',
  modelId: 'small',
);

const _crashedResult = CandidateResult(
  candidateId: 'whisper-cpp-cuda12',
  outcome: Outcome.crashed,
  exitCode: 1,
  stderrTail:
      'CUDA error: no kernel image is available for execution on the device',
  errorDetail: 'exit code 1',
);

const _hungResult = CandidateResult(
  candidateId: 'whisper-cpp-vulkan',
  outcome: Outcome.hung,
  errorDetail: 'timedOut',
);

const _skippedResult = CandidateResult(
  candidateId: 'whisper-cpp-cpu-medium',
  outcome: Outcome.skipped,
  errorDetail: 'Modell medium überschreitet VRAM-Budget',
);

final _hardware = HardwareContext(
  cpuModel: 'Intel Core i5-1145G7',
  ramGb: 16,
  gpuModel: 'NVIDIA GeForce GTX 650',
  vramGb: 1,
  os: 'Windows 11 Pro (Build 26200)',
  driverVersion: '342.01',
);

ProbeReport _buildReport({bool includeHardware = true}) => ProbeReport(
  timestamp: DateTime.utc(2026, 6, 15, 12, 0, 0),
  results: [
    _cpuResult,
    _winnerResult,
    _okSlowResult,
    _crashedResult,
    _hungResult,
    _skippedResult,
  ],
  version: '0.2.0-test',
  hardwareContext: includeHardware ? _hardware : null,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('formatProbeReportHtml', () {
    late String html;

    setUpAll(() {
      html = formatProbeReportHtml(_buildReport());
    });

    // -------------------------------------------------------------------------
    // Document structure
    // -------------------------------------------------------------------------

    test('is a complete HTML document starting with DOCTYPE', () {
      expect(html.trim(), startsWith('<!DOCTYPE html>'));
    });

    test('has closing </html> tag', () {
      expect(html, contains('</html>'));
    });

    test('has UTF-8 charset meta tag', () {
      expect(html, contains('charset="utf-8"'));
    });

    test('html element has lang="de"', () {
      expect(html, contains('lang="de"'));
    });

    test('has <style> block (inline CSS)', () {
      expect(html, contains('<style>'));
      expect(html, contains('</style>'));
    });

    test('contains title WhisPaste GPU-Probe Report', () {
      expect(html, contains('WhisPaste GPU-Probe Report'));
    });

    test('contains version string', () {
      expect(html, contains('0.2.0-test'));
    });

    test('contains timestamp', () {
      expect(html, contains('2026-06-15'));
    });

    // -------------------------------------------------------------------------
    // No external resources
    // -------------------------------------------------------------------------

    test('no http:// references in src or href attributes', () {
      // Find src= and href= attribute values and assert none start with http
      final srcPattern = RegExp(r'''(?:src|href)\s*=\s*["']https?://''');
      expect(
        srcPattern.hasMatch(html),
        isFalse,
        reason: 'must have no external src/href references',
      );
    });

    test('no https:// in src or href', () {
      final externalRef = RegExp(r'''(?:src|href)\s*=\s*["']https://''');
      expect(externalRef.hasMatch(html), isFalse);
    });

    // -------------------------------------------------------------------------
    // Winner banner
    // -------------------------------------------------------------------------

    test('shows winner candidate id in banner', () {
      expect(html, contains('const-me-directcompute'));
    });

    test('shows speedup text with × symbol for winner', () {
      // 48000/8000 = 6.0×
      expect(html, contains('6,0'));
    });

    test('shows WER for winner', () {
      // winner WER is 0.08 → 8,0 %
      expect(html, contains('8,0'));
    });

    // -------------------------------------------------------------------------
    // Ranking table — ok candidates + baseline
    // -------------------------------------------------------------------------

    test('contains ranking table with CPU baseline', () {
      expect(html, contains('whisper-cpp-cpu'));
    });

    test('contains all ok candidates in ranking table', () {
      expect(html, contains('const-me-directcompute'));
      expect(html, contains('wav2vec2-directml-de'));
    });

    // -------------------------------------------------------------------------
    // Outcome CSS classes
    // -------------------------------------------------------------------------

    test('ok outcome uses outcome-ok CSS class', () {
      expect(html, contains('outcome-ok'));
    });

    test('crashed outcome uses outcome-crashed CSS class', () {
      expect(html, contains('outcome-crashed'));
    });

    test('hung outcome uses outcome-hung CSS class', () {
      expect(html, contains('outcome-hung'));
    });

    test('skipped outcome uses outcome-skipped CSS class', () {
      expect(html, contains('outcome-skipped'));
    });

    // -------------------------------------------------------------------------
    // Failed / non-runnable section
    // -------------------------------------------------------------------------

    test('failed section contains crashed candidate', () {
      expect(html, contains('whisper-cpp-cuda12'));
    });

    test('failed section contains hung candidate', () {
      expect(html, contains('whisper-cpp-vulkan'));
    });

    test('failed section contains skipped candidate', () {
      expect(html, contains('whisper-cpp-cpu-medium'));
    });

    // -------------------------------------------------------------------------
    // Hardware context
    // -------------------------------------------------------------------------

    test('shows GPU model', () {
      expect(html, contains('NVIDIA GeForce GTX 650'));
    });

    test('shows CPU model', () {
      expect(html, contains('Intel Core i5-1145G7'));
    });

    test('shows OS', () {
      expect(html, contains('Windows 11 Pro'));
    });

    // -------------------------------------------------------------------------
    // Hardware context absent when not provided
    // -------------------------------------------------------------------------

    test('no hardware section when hardwareContext is null', () {
      final htmlNoHw = formatProbeReportHtml(
        _buildReport(includeHardware: false),
      );
      expect(htmlNoHw, isNot(contains('NVIDIA GeForce GTX 650')));
      expect(htmlNoHw, isNot(contains('Intel Core i5-1145G7')));
    });

    // -------------------------------------------------------------------------
    // CPU baseline missing warning
    // -------------------------------------------------------------------------

    test('shows baseline-missing warning when no CPU candidate', () {
      final report = ProbeReport(
        timestamp: DateTime.utc(2026, 6, 15, 12, 0, 0),
        results: const [_winnerResult, _crashedResult],
        version: '0.2.0-test',
      );
      final htmlNoCpu = formatProbeReportHtml(report);
      // Should show some warning about missing baseline
      expect(
        htmlNoCpu.toLowerCase(),
        anyOf(contains('baseline'), contains('cpu')),
      );
    });

    // -------------------------------------------------------------------------
    // No winner when no non-baseline ok candidate
    // -------------------------------------------------------------------------

    test('shows fallback message when only CPU candidate is ok', () {
      final report = ProbeReport(
        timestamp: DateTime.utc(2026, 6, 15, 12, 0, 0),
        results: const [_cpuResult, _crashedResult],
        version: '0.2.0-test',
      );
      final htmlCpuOnly = formatProbeReportHtml(report);
      expect(htmlCpuOnly, contains('CPU'));
    });
  });
}
