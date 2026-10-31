/// Tests for VRAM gating (issue 04).
///
/// AC1: gate fn → fits / skipped+reason
/// AC2: verified structurally — sttModelVramMB imported from whispaste_diagnostics,
///      not copied; no copy of threshold values in this package.
/// AC3: medium@1024MB→skipped, small@2048MB→fits + expected reasons
/// AC4: VramGatedCandidate never calls delegate.run() when gate rejects
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _ctx = ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.bin',
  workDir: '/tmp/fake',
);

/// A fake candidate that records whether run() was ever called.
class _SpyCandidate implements ProbeCandidate {
  bool wasCalled = false;

  @override
  String get id => 'spy';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    wasCalled = true;
    return const CandidateResult(candidateId: 'spy', outcome: Outcome.ok);
  }
}

// ---------------------------------------------------------------------------
// checkVramGate (AC1 + AC3)
// ---------------------------------------------------------------------------

void main() {
  group('checkVramGate', () {
    // AC1: gate returns VramFits when model fits
    test('returns VramFits when vramBudgetMB is null (unknown)', () {
      final result = checkVramGate(
        modelSizeKey: 'whisper-medium',
        vramBudgetMB: null,
      );
      expect(result, isA<VramFits>());
    });

    test('returns VramFits for unknown modelSizeKey (fail-open)', () {
      final result = checkVramGate(
        modelSizeKey: 'whisper-unknown-model',
        vramBudgetMB: 512,
      );
      expect(result, isA<VramFits>());
    });

    // AC3 golden case 1: medium on 1 GB → skipped
    test('whisper-medium on 1024 MB → VramSkipped with reason', () {
      final result = checkVramGate(
        modelSizeKey: 'whisper-medium',
        vramBudgetMB: 1024,
      );
      expect(result, isA<VramSkipped>());
      final skipped = result as VramSkipped;
      expect(skipped.reason, contains('whisper-medium'));
      expect(skipped.reason, contains('1024'));
      expect(
        skipped.reason,
        contains('1500'),
      ); // sttModelVramMB['whisper-medium']
    });

    // AC3 golden case 2: small on 2 GB → fits
    test('whisper-small on 2048 MB → VramFits', () {
      final result = checkVramGate(
        modelSizeKey: 'whisper-small',
        vramBudgetMB: 2048,
      );
      expect(result, isA<VramFits>());
    });

    // AC1: exact budget at threshold is treated as fits
    test('budget exactly equal to required → VramFits', () {
      // whisper-small requires 900 MB
      final result = checkVramGate(
        modelSizeKey: 'whisper-small',
        vramBudgetMB: 900,
      );
      expect(result, isA<VramFits>());
    });

    // AC1: one MB below threshold → skipped
    test('budget one MB below required → VramSkipped', () {
      // whisper-small requires 900 MB; 899 is below
      final result = checkVramGate(
        modelSizeKey: 'whisper-small',
        vramBudgetMB: 899,
      );
      expect(result, isA<VramSkipped>());
    });

    // Large model sanity check
    test('whisper-large-v3-turbo on 2048 MB → VramSkipped', () {
      final result = checkVramGate(
        modelSizeKey: 'whisper-large-v3-turbo',
        vramBudgetMB: 2048,
      );
      expect(result, isA<VramSkipped>());
    });
  });

  // ---------------------------------------------------------------------------
  // VramGatedCandidate (AC4)
  // ---------------------------------------------------------------------------

  group('VramGatedCandidate', () {
    // AC4: delegate.run() is NOT called when gate rejects
    test(
      'does not call delegate.run() when model does not fit (medium@1024MB)',
      () async {
        final spy = _SpyCandidate();
        final gated = VramGatedCandidate(
          delegate: spy,
          modelSizeKey: 'whisper-medium',
          vramBudgetMB: 1024,
        );

        final result = await gated.run(_ctx);

        expect(spy.wasCalled, isFalse, reason: 'delegate.run() must not fire');
        expect(result.outcome, equals(Outcome.skipped));
        expect(result.candidateId, equals('spy'));
        expect(result.errorDetail, isNotEmpty);
        expect(result.errorDetail, contains('whisper-medium'));
      },
    );

    // AC4: delegate.run() IS called when gate passes (small@2048MB)
    test('calls delegate.run() when model fits (small@2048MB)', () async {
      final spy = _SpyCandidate();
      final gated = VramGatedCandidate(
        delegate: spy,
        modelSizeKey: 'whisper-small',
        vramBudgetMB: 2048,
      );

      final result = await gated.run(_ctx);

      expect(spy.wasCalled, isTrue, reason: 'delegate.run() must fire');
      expect(result.outcome, equals(Outcome.ok));
    });

    // AC4: null budget → gate passes, delegate runs
    test('passes gate and calls delegate when vramBudgetMB is null', () async {
      final spy = _SpyCandidate();
      final gated = VramGatedCandidate(
        delegate: spy,
        modelSizeKey: 'whisper-medium',
        vramBudgetMB: null,
      );

      await gated.run(_ctx);

      expect(spy.wasCalled, isTrue);
    });

    // id is forwarded from delegate
    test('id is forwarded from delegate', () {
      final spy = _SpyCandidate();
      final gated = VramGatedCandidate(
        delegate: spy,
        modelSizeKey: 'whisper-small',
        vramBudgetMB: 2048,
      );
      expect(gated.id, equals('spy'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: orchestrator-level integration
  // Via runProbeOrchestrator: a VramGatedCandidate(skipped) → delegate never runs
  // ---------------------------------------------------------------------------

  group('runProbeOrchestrator with VramGatedCandidate', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vram_gate_orch_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'skipped candidate appears in results and delegate.run() was never called',
      () async {
        final spy = _SpyCandidate();
        final gated = VramGatedCandidate(
          delegate: spy,
          modelSizeKey: 'whisper-medium',
          vramBudgetMB: 1024, // too small → will be skipped
        );

        await runProbeOrchestrator(
          candidates: [gated],
          context: _ctx,
          outputDir: tempDir.path,
          version: '0.0.0-test',
        );

        expect(spy.wasCalled, isFalse, reason: 'subprocess must not start');
      },
    );
  });
}
