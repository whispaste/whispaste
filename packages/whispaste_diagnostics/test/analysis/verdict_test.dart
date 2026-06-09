/// Unit tests for verdict.dart (AC4, AC5).
///
/// Drives the verdict from fixture probe-model instances. Tests the full
/// required coverage: missing DLL, missing VC++, AV-quarantine, RAM < 7500,
/// stale TCC, model ABI mismatch — each mapped to a canonical fingerprint.
/// Includes healthy/negative cases (no suspicions → healthy verdict).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/analysis/verdict.dart';
import 'package:whispaste_diagnostics/src/analysis/dll_analysis.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Healthy case (AC5 negative/healthy path)
  // ---------------------------------------------------------------------------

  group('buildVerdict — healthy', () {
    test('returns healthy verdict when no suspicions are present', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isTrue);
      expect(v.suspicions, isEmpty);
      expect(v.primaryFingerprint, isNull);
    });

    test('healthy verdict has empty suspicions list', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: 0,
      );
      expect(v.healthy, isTrue);
      expect(v.suspicions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: missing DLL → stt-exit-dll-missing
  // ---------------------------------------------------------------------------

  group('buildVerdict — missing DLL', () {
    test('missing DLL gives stt-exit-dll-missing fingerprint', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: ['ggml-cpu.dll'],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(v.primaryFingerprint, 'stt-exit-dll-missing');
      expect(
        v.suspicions.any((s) => s.fingerprint == 'stt-exit-dll-missing'),
        isTrue,
      );
    });

    test('suspicion detail names the missing DLL', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: ['ggml-cpu.dll'],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final suspicion = v.suspicions.first;
      expect(suspicion.detail, contains('ggml-cpu.dll'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: missing VC++ runtime → stt-exit-dll-missing
  // ---------------------------------------------------------------------------

  group('buildVerdict — missing VC++ runtime', () {
    test('vcRuntimeMissing gives stt-exit-dll-missing fingerprint', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: ['vcruntime140.dll'],
          vcRuntimeMissing: true,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(v.primaryFingerprint, 'stt-exit-dll-missing');
    });

    test('VC++ suspicion detail mentions VC++ Redistributable', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: ['vcruntime140.dll'],
          vcRuntimeMissing: true,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final vcSuspicion = v.suspicions.firstWhere(
        (s) => s.fingerprint == 'stt-exit-dll-missing',
      );
      expect(vcSuspicion.detail.toLowerCase(), contains('vc++'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: AV quarantine → stt-exit-dll-missing (binary can't load)
  // ---------------------------------------------------------------------------

  group('buildVerdict — AV quarantine', () {
    test('avQuarantined=true adds stt-exit-dll-missing suspicion', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: true,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(v.primaryFingerprint, 'stt-exit-dll-missing');
      expect(
        v.suspicions.any(
          (s) =>
              s.fingerprint == 'stt-exit-dll-missing' &&
              s.detail.toLowerCase().contains('quarantine'),
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: RAM < 7500 MB → stt-exit-other
  // ---------------------------------------------------------------------------

  group('buildVerdict — RAM scarce', () {
    test('ramScarce=true adds stt-exit-other suspicion', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: true,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(
        v.suspicions.any((s) => s.fingerprint == 'stt-exit-other'),
        isTrue,
      );
    });

    test('RAM suspicion detail mentions 7500 MB or RAM threshold', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: true,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final ramSuspicion = v.suspicions.firstWhere(
        (s) => s.fingerprint == 'stt-exit-other',
      );
      expect(ramSuspicion.detail, contains('7500'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: stale TCC → stt-exit-other (macOS)
  // ---------------------------------------------------------------------------

  group('buildVerdict — stale TCC', () {
    test('staleTcc=true adds stt-exit-other suspicion', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: true,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(
        v.suspicions.any((s) => s.fingerprint == 'stt-exit-other'),
        isTrue,
      );
    });

    test('stale-TCC suspicion detail mentions TCC', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: true,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      final tccSuspicion = v.suspicions.firstWhere(
        (s) => s.fingerprint == 'stt-exit-other',
      );
      expect(tccSuspicion.detail.toUpperCase(), contains('TCC'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: model ABI mismatch → stt-model-abi-mismatch
  // ---------------------------------------------------------------------------

  group('buildVerdict — model ABI mismatch', () {
    test('modelAbiMismatch=true adds stt-model-abi-mismatch suspicion', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: true,
        serverExitCode: null,
      );
      expect(v.healthy, isFalse);
      expect(v.primaryFingerprint, 'stt-model-abi-mismatch');
      expect(
        v.suspicions.any((s) => s.fingerprint == 'stt-model-abi-mismatch'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple suspicions — primary fingerprint priority
  // ---------------------------------------------------------------------------

  group('buildVerdict — primary fingerprint priority', () {
    test('DLL missing outranks RAM scarce for primaryFingerprint', () {
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: ['vcruntime140.dll'],
          vcRuntimeMissing: true,
        ),
        ramScarce: true,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: null,
      );
      expect(v.primaryFingerprint, 'stt-exit-dll-missing');
      expect(v.suspicions.length, greaterThan(1));
    });

    test('exit code overrides DLL analysis when present', () {
      // Exit 0xC0000409 (heap corruption) should surface in primaryFingerprint.
      final v = buildVerdict(
        dllAnalysis: const DllAnalysisResult(
          missingDlls: [],
          vcRuntimeMissing: false,
        ),
        ramScarce: false,
        avQuarantined: false,
        staleTcc: false,
        modelAbiMismatch: false,
        serverExitCode: 0xC0000409,
      );
      expect(v.primaryFingerprint, 'stt-exit-heap-corruption');
    });
  });

  // ---------------------------------------------------------------------------
  // VerdictSuspicion model
  // ---------------------------------------------------------------------------

  group('VerdictSuspicion', () {
    test('toString contains fingerprint and detail', () {
      const s = VerdictSuspicion(
        fingerprint: 'stt-exit-dll-missing',
        detail: 'vcruntime140.dll is missing',
      );
      final str = s.toString();
      expect(str, contains('stt-exit-dll-missing'));
      expect(str, contains('vcruntime140.dll is missing'));
    });
  });
}
