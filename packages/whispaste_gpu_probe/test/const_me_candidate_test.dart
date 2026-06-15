/// Tests for ConstMeCandidate (Const-me/Whisper, DirectCompute backend).
///
/// All tests use fake [ProcessLauncher] seams — no real engine process is ever
/// spawned. CPU feature flags are injected directly via [CpuFeatureSet].
///
/// ## AC5 note — real GTX-650 measurement
///
/// Running a live probe against a real GTX-650 (or any DirectCompute-capable
/// GPU) is a MANUAL step and must NOT be part of CI. The expected outcome on a
/// GTX-650 with AVX+F16C capable CPU is [Outcome.ok] with a reasonable German
/// transcript. Document the result in `.scratch/gpu-probe-tool/` after the
/// manual run.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors whisper_cpp_candidate_test.dart)
// ---------------------------------------------------------------------------

/// Minimal fake [Process] that lets tests resolve the exit code on demand.
class _FakeProcess implements Process {
  _FakeProcess();

  bool wasKilled = false;
  final _exitCompleter = Completer<int>();

  void complete(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(-1);
    return true;
  }

  @override
  int get pid => 0;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => throw UnimplementedError();
  @override
  Stream<List<int>> get stderr => throw UnimplementedError();
}

/// Creates a [ProcessLauncher] that immediately returns a fake process with the
/// given [exitCode], optional [stdoutLines], and optional [stderrLines].
ProcessLauncher _fakeLauncher({
  required int exitCode,
  List<String> stdoutLines = const [],
  List<String> stderrLines = const [],
}) {
  return (executable, arguments, workingDirectory) async {
    final fake = _FakeProcess();
    scheduleMicrotask(() => fake.complete(exitCode));

    final stdoutCtrl = StreamController<String>();
    final stderrCtrl = StreamController<String>();
    for (final line in stdoutLines) {
      stdoutCtrl.add(line);
    }
    stdoutCtrl.close();
    for (final line in stderrLines) {
      stderrCtrl.add(line);
    }
    stderrCtrl.close();

    return ProcessStartResult(
      process: fake,
      stdout: stdoutCtrl.stream,
      stderr: stderrCtrl.stream,
    );
  };
}

/// Creates a [ProcessLauncher] that throws to simulate a missing binary.
ProcessLauncher _missingBinaryLauncher() {
  return (executable, arguments, workingDirectory) async {
    throw Exception('No such file or directory: $executable');
  };
}

// ---------------------------------------------------------------------------
// Spy launcher — records whether it was called
// ---------------------------------------------------------------------------

/// A spy launcher that tracks call count and delegates to [inner].
class _SpyLauncher {
  _SpyLauncher(this._inner);

  final ProcessLauncher _inner;
  int callCount = 0;

  ProcessLauncher get launcher => (exe, args, dir) async {
    callCount++;
    return _inner(exe, args, dir);
  };
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Sample Const-me/Whisper stdout (segment lines + noise lines).
const _sampleConstMeOutput = [
  'Const-me/Whisper v1.0 loading model /model.bin',
  '[00:00:00.000 --> 00:00:02.500]  Guten Tag.',
  '[00:00:02.500 --> 00:00:05.200]  Das ist ein Test.',
  '[00:00:05.200 --> 00:00:08.000]  Ich spreche Deutsch.',
  'compute time: 420 ms',
];

/// Expected joined transcript from [_sampleConstMeOutput].
const _expectedTranscript = 'Guten Tag. Das ist ein Test. Ich spreche Deutsch.';

/// Full CPU feature set (all required features present).
const CpuFeatureSet _fullFeatures = {
  cpuFeatureAvx,
  cpuFeatureF16c,
  cpuFeatureFma3,
  cpuFeatureBmi1,
};

/// Feature set with only AVX1 + F16C (no FMA3/BMI1 — sufficient for small
/// model but not for the hybrid medium model).
const CpuFeatureSet _baseOnlyFeatures = {cpuFeatureAvx, cpuFeatureF16c};

/// Empty feature set — nothing supported.
const CpuFeatureSet _noFeatures = {};

/// Minimal [ProbeContext] for tests.
final _fakeCtx = ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.bin',
  workDir: Directory.systemTemp.path,
  language: 'de',
  timeout: const Duration(seconds: 30),
);

/// Fast runner configuration for tests.
ProbeRunner _fastRunner(ProcessLauncher launcher) => ProbeRunner(
  launcher: launcher,
  startupDeadline: const Duration(seconds: 10),
  heartbeatTimeout: const Duration(seconds: 10),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Parser golden tests (AC4 — parsing)
  // -------------------------------------------------------------------------

  group('parseConstMeTranscript — parser golden test', () {
    test('extracts segment text and joins with spaces', () {
      final transcript = parseConstMeTranscript(_sampleConstMeOutput);
      expect(transcript, equals(_expectedTranscript));
    });

    test('ignores non-segment lines (header, compute time)', () {
      final output = [
        'Const-me/Whisper v1.0 loading model',
        '[00:00:00.000 --> 00:00:03.000]  Hallo Welt.',
        'compute time: 200 ms',
      ];
      expect(parseConstMeTranscript(output), equals('Hallo Welt.'));
    });

    test('empty stdout → empty string', () {
      expect(parseConstMeTranscript([]), isEmpty);
    });

    test('only non-segment lines → empty string', () {
      expect(
        parseConstMeTranscript(['Loading...', 'Done.', 'compute time: 100 ms']),
        isEmpty,
      );
    });

    test('multiple segments are space-joined in order', () {
      final output = [
        '[00:00:00.000 --> 00:00:01.000]  Eins.',
        '[00:00:01.000 --> 00:00:02.000]  Zwei.',
        '[00:00:02.000 --> 00:00:03.000]  Drei.',
      ];
      expect(parseConstMeTranscript(output), equals('Eins. Zwei. Drei.'));
    });

    test(
      'two-space variant before text is handled (Const-me uses two spaces)',
      () {
        // Const-me may emit two spaces after the closing bracket; both variants
        // should parse correctly since the regex matches one or more spaces.
        final output = ['[00:00:00.000 --> 00:00:02.000]   Doppelt.'];
        expect(parseConstMeTranscript(output), equals('Doppelt.'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC4 ok-path: full features present, fake subprocess succeeds
  // -------------------------------------------------------------------------

  group('ConstMeCandidate — ok path (AC4)', () {
    test('exit 0 + transcript stdout + full CPU features → Outcome.ok with '
        'transcript and WER', () async {
      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
        ),
        referenceTranscript: _expectedTranscript,
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.candidateId, equals('const-me-directcompute'));
      expect(result.outcome, equals(Outcome.ok));
      expect(result.transcribedText, equals(_expectedTranscript));
      expect(result.wer, closeTo(0.0, 0.01));
      expect(result.backend, equals('directcompute'));
      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test(
      'base features only + small model → ok (FMA3/BMI1 not required)',
      () async {
        final candidate = ConstMeCandidate(
          id: 'const-me-directcompute',
          binaryName: 'main.exe',
          modelSizeKey: modelSizeSmall,
          cpuFeatures: _baseOnlyFeatures,
          runner: _fastRunner(
            _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
          ),
          referenceTranscript: _expectedTranscript,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.outcome, equals(Outcome.ok));
      },
    );

    test('no referenceTranscript → wer is null, outcome still ok', () async {
      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
        ),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.wer, isNull);
      expect(result.outcome, equals(Outcome.ok));
    });
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4: missing AVX1/F16C → skipped, no subprocess
  // -------------------------------------------------------------------------

  group('ConstMeCandidate — missing base CPU features (AC3, AC4)', () {
    test(
      'no CPU features at all → Outcome.skipped, spy proves run() NOT called',
      () async {
        final spy = _SpyLauncher(_fakeLauncher(exitCode: 0));

        final candidate = ConstMeCandidate(
          id: 'const-me-directcompute',
          binaryName: 'main.exe',
          modelSizeKey: modelSizeSmall,
          cpuFeatures: _noFeatures,
          runner: _fastRunner(spy.launcher),
        );

        final result = await candidate.run(_fakeCtx);

        // No subprocess must have been started.
        expect(spy.callCount, equals(0), reason: 'launcher must NOT be called');
        expect(result.outcome, equals(Outcome.skipped));
        expect(result.errorDetail, isNotNull);
        expect(result.errorDetail, contains('AVX'));
        expect(result.backend, equals('directcompute'));
      },
    );

    test('has AVX but missing F16C → Outcome.skipped, no subprocess', () async {
      final spy = _SpyLauncher(_fakeLauncher(exitCode: 0));

      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: {cpuFeatureAvx}, // F16C missing
        runner: _fastRunner(spy.launcher),
      );

      final result = await candidate.run(_fakeCtx);

      expect(spy.callCount, equals(0));
      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, contains('f16c'));
    });

    test('has F16C but missing AVX → Outcome.skipped, no subprocess', () async {
      final spy = _SpyLauncher(_fakeLauncher(exitCode: 0));

      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: {cpuFeatureF16c}, // AVX missing
        runner: _fastRunner(spy.launcher),
      );

      final result = await candidate.run(_fakeCtx);

      expect(spy.callCount, equals(0));
      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, contains('avx'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4: hybrid model missing FMA3/BMI1 → skipped, no subprocess
  // -------------------------------------------------------------------------

  group('ConstMeCandidate — hybrid model missing FMA3/BMI1 (AC3, AC4)', () {
    test('medium model + base features only (no FMA3/BMI1) → Outcome.skipped, '
        'no subprocess', () async {
      final spy = _SpyLauncher(_fakeLauncher(exitCode: 0));

      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: constMeHybridModelSize, // 'whisper-medium'
        cpuFeatures: _baseOnlyFeatures, // AVX+F16C only, no FMA3/BMI1
        runner: _fastRunner(spy.launcher),
      );

      final result = await candidate.run(_fakeCtx);

      expect(spy.callCount, equals(0));
      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('Hybrid'));
      expect(result.backend, equals('directcompute'));
    });

    test('medium model + full features → subprocess is called', () async {
      final spy = _SpyLauncher(
        _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
      );

      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: constMeHybridModelSize,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(spy.launcher),
        referenceTranscript: _expectedTranscript,
      );

      final result = await candidate.run(_fakeCtx);

      expect(spy.callCount, equals(1), reason: 'launcher must be called');
      expect(result.outcome, equals(Outcome.ok));
    });

    test('missing only FMA3 → skipped for medium model', () async {
      final spy = _SpyLauncher(_fakeLauncher(exitCode: 0));
      final featuresWithoutFma3 = {
        cpuFeatureAvx,
        cpuFeatureF16c,
        cpuFeatureBmi1,
      };

      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: constMeHybridModelSize,
        cpuFeatures: featuresWithoutFma3,
        runner: _fastRunner(spy.launcher),
      );

      final result = await candidate.run(_fakeCtx);

      expect(spy.callCount, equals(0));
      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, contains('fma3'));
    });
  });

  // -------------------------------------------------------------------------
  // Binary not found
  // -------------------------------------------------------------------------

  group('ConstMeCandidate — binary not found', () {
    test('launcher throws → Outcome.skipped with error detail', () async {
      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(_missingBinaryLauncher()),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('nicht gefunden'));
    });
  });

  // -------------------------------------------------------------------------
  // Non-zero exit code
  // -------------------------------------------------------------------------

  group('ConstMeCandidate — non-zero exit', () {
    test('exit code 1 → Outcome.crashed', () async {
      final candidate = ConstMeCandidate(
        id: 'const-me-directcompute',
        binaryName: 'main.exe',
        modelSizeKey: modelSizeSmall,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(_fakeLauncher(exitCode: 1)),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.crashed));
      expect(result.exitCode, equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // CandidateManifest — Const-me entry present (AC1)
  // -------------------------------------------------------------------------

  group('CandidateManifest — Const-me entry (AC1)', () {
    test(
      'defaults manifest includes at least one const-me-directcompute entry',
      () {
        final manifest = CandidateManifest.defaults(cpuFeatures: _fullFeatures);
        final constMeIds = manifest.entries
            .where((e) => e.candidate.id == 'const-me-directcompute')
            .toList();
        expect(
          constMeIds,
          isNotEmpty,
          reason: 'manifest must contain at least one Const-me entry',
        );
      },
    );

    test(
      'Const-me entries declare DirectCompute backend and GGML model manifest',
      () {
        final manifest = CandidateManifest.defaults(cpuFeatures: _fullFeatures);
        final constMeEntries = manifest.entries
            .where((e) => e.candidate.id == 'const-me-directcompute')
            .toList();

        for (final entry in constMeEntries) {
          // Each entry must reference a valid ModelManifest.
          expect(entry.models, isA<ModelManifest>());
          expect(entry.models.entries, isNotEmpty);

          // Each declared model size must resolve in the manifest.
          for (final size in entry.modelSizes) {
            expect(
              entry.models.find(size),
              isNotNull,
              reason:
                  'Const-me size "$size" must resolve in the GGML ModelManifest',
            );
          }
        }
      },
    );

    test('Const-me entries cover small and medium model sizes', () {
      final manifest = CandidateManifest.defaults(cpuFeatures: _fullFeatures);

      // Collect all sizes declared across const-me entries.
      final constMeSizes = manifest.entries
          .where((e) => e.candidate.id == 'const-me-directcompute')
          .expand((e) => e.modelSizes)
          .toSet();

      expect(constMeSizes, contains(modelSizeSmall));
      expect(constMeSizes, contains(modelSizeMedium));
    });

    test(
      'existing whisper.cpp candidates are unaffected by adding Const-me',
      () {
        final manifest = CandidateManifest.defaults(cpuFeatures: _fullFeatures);
        final ids = manifest.entries.map((e) => e.candidate.id).toSet();

        expect(ids, contains('whisper-cpp-cpu'));
        expect(ids, contains('whisper-cpp-cuda12'));
        expect(ids, contains('whisper-cpp-vulkan'));
        expect(ids, contains('whisper-cpp-opencl'));
      },
    );

    test(
      'custom runner is forwarded to Const-me subprocess-backed candidates',
      () async {
        final spy = _SpyLauncher(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
        );

        final manifest = CandidateManifest.defaults(
          runner: _fastRunner(spy.launcher),
          cpuFeatures: _fullFeatures,
          referenceTranscript: _expectedTranscript,
        );

        // Run only the Const-me entries.
        for (final entry in manifest.entries) {
          if (entry.candidate.id == 'const-me-directcompute') {
            await entry.candidate.run(_fakeCtx);
          }
        }

        // At least one Const-me subprocess should have been called.
        expect(
          spy.callCount,
          greaterThan(0),
          reason: 'Const-me with full features must invoke the launcher',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Factory constructor
  // -------------------------------------------------------------------------

  group('constMeDirectComputeCandidate factory', () {
    test('produces candidate with correct id and backend', () async {
      final candidate = constMeDirectComputeCandidate(
        modelSizeKey: modelSizeSmall,
        cpuFeatures: _fullFeatures,
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleConstMeOutput),
        ),
      );

      expect(candidate.id, equals('const-me-directcompute'));

      final result = await candidate.run(_fakeCtx);
      expect(result.backend, equals('directcompute'));
    });
  });
}
