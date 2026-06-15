/// Tests for WhisperCppCandidate and the CandidateManifest.
///
/// All tests use fake [ProcessLauncher] seams — no real engine processes are
/// spawned.  Tests are fully deterministic.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors probe_runner_test.dart)
// ---------------------------------------------------------------------------

/// Minimal fake [Process] that lets tests resolve the exit code on demand.
class _FakeProcess implements Process {
  _FakeProcess({this.exitOnKill = -1});

  final int exitOnKill;
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
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(exitOnKill);
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
    // Schedule exit asynchronously so ProbeRunner event loop can attach.
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

/// Creates a [ProcessLauncher] that never exits (simulates a hang).
/// Uses [tinyDeadline] for fast-failing watchdog in tests.
ProcessLauncher _hangingLauncher() {
  return (executable, arguments, workingDirectory) async {
    final fake = _FakeProcess(exitOnKill: -1);
    // Never completes on its own — ProbeRunner must kill it.
    return ProcessStartResult(
      process: fake,
      stdout: const Stream.empty(),
      stderr: const Stream.empty(),
    );
  };
}

/// Sample whisper.cpp stdout with a multi-segment German transcript.
const _sampleWhisperOutput = [
  'whisper_init_from_file_with_params_no_state: loading model from /model.bin',
  'whisper_model_load: loading model',
  '[00:00:00.000 --> 00:00:02.500]   Guten Tag.',
  '[00:00:02.500 --> 00:00:05.200]   Das ist ein Test.',
  '[00:00:05.200 --> 00:00:08.000]   Ich spreche Deutsch.',
  'whisper_print_timings:     load time =  120.50 ms',
  'whisper_print_timings:  sample time =    5.20 ms',
  'whisper_print_timings:   encode time =  350.00 ms',
  'whisper_print_timings:   decode time =   80.00 ms',
  'whisper_print_timings:    total time =  555.70 ms',
];

/// The transcript text expected from [_sampleWhisperOutput].
const _expectedTranscript = 'Guten Tag. Das ist ein Test. Ich spreche Deutsch.';

/// Minimal [ProbeContext] for tests.
///
/// The fake launcher never touches the filesystem, but the real candidates
/// target Windows, so use the portable system temp dir rather than `/tmp`.
final _fakeCtx = ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.bin',
  workDir: Directory.systemTemp.path,
  language: 'de',
  timeout: const Duration(seconds: 30),
);

// ---------------------------------------------------------------------------
// Tiny watchdog durations for hang tests
// ---------------------------------------------------------------------------

const _tinyDeadline = Duration(milliseconds: 5);
const _tinyHeartbeat = Duration(milliseconds: 5);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // AC5: Pure parser golden test
  // -------------------------------------------------------------------------

  group('parseWhisperCppTranscript — parser golden test (AC5)', () {
    test('extracts segment text and joins with spaces', () {
      final transcript = parseWhisperCppTranscript(_sampleWhisperOutput);
      expect(transcript, equals(_expectedTranscript));
    });

    test('ignores non-segment lines (progress, timings)', () {
      final output = [
        'whisper_init_from_file: loading model',
        'system_info: ...',
        '[00:00:00.000 --> 00:00:03.000]   Hallo Welt.',
        'whisper_print_timings: total time = 200 ms',
      ];
      final transcript = parseWhisperCppTranscript(output);
      expect(transcript, equals('Hallo Welt.'));
    });

    test('empty stdout → empty string', () {
      expect(parseWhisperCppTranscript([]), isEmpty);
    });

    test('only non-segment lines → empty string', () {
      expect(
        parseWhisperCppTranscript(['Loading...', 'Done.', 'timings: ...']),
        isEmpty,
      );
    });

    test('multiple segments are space-joined in order', () {
      final output = [
        '[00:00:00.000 --> 00:00:01.000]   Eins.',
        '[00:00:01.000 --> 00:00:02.000]   Zwei.',
        '[00:00:02.000 --> 00:00:03.000]   Drei.',
      ];
      expect(parseWhisperCppTranscript(output), equals('Eins. Zwei. Drei.'));
    });
  });

  // -------------------------------------------------------------------------
  // AC4: Per-variant fake-subprocess outcome tests
  // -------------------------------------------------------------------------

  group('WhisperCppCandidate — CPU ok path (AC4)', () {
    test(
      'exit 0 + transcript stdout → Outcome.ok with transcript and WER',
      () async {
        final runner = ProbeRunner(
          launcher: _fakeLauncher(
            exitCode: 0,
            stdoutLines: _sampleWhisperOutput,
          ),
          startupDeadline: const Duration(seconds: 10),
          heartbeatTimeout: const Duration(seconds: 10),
        );

        final candidate = whisperCppCpuCandidate(
          runner: runner,
          referenceTranscript: _expectedTranscript,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.candidateId, equals('whisper-cpp-cpu'));
        expect(result.outcome, equals(Outcome.ok));
        expect(result.transcribedText, equals(_expectedTranscript));
        expect(result.wer, closeTo(0.0, 0.01));
        expect(result.backend, equals('cpu'));
        expect(result.durationMs, greaterThanOrEqualTo(0));
      },
    );

    test('WER is computed against reference', () async {
      // Reference has 3 words, hypothesis replaces one → WER = 1/3
      const reference = 'eins zwei drei';
      const hypothesis = 'eins zwei vier';
      final stdoutWithHypothesis = [
        '[00:00:00.000 --> 00:00:02.000]   $hypothesis',
      ];

      final runner = ProbeRunner(
        launcher: _fakeLauncher(exitCode: 0, stdoutLines: stdoutWithHypothesis),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final candidate = whisperCppCpuCandidate(
        runner: runner,
        referenceTranscript: reference,
      );

      final result = await candidate.run(_fakeCtx);
      expect(result.wer, closeTo(1 / 3, 0.01));
    });

    test('no referenceTranscript → wer is null', () async {
      final runner = ProbeRunner(
        launcher: _fakeLauncher(exitCode: 0, stdoutLines: _sampleWhisperOutput),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final candidate = whisperCppCpuCandidate(runner: runner);
      final result = await candidate.run(_fakeCtx);

      expect(result.wer, isNull);
      expect(result.outcome, equals(Outcome.ok));
    });
  });

  group('WhisperCppCandidate — CUDA-12 crash (AC4)', () {
    test('non-zero exit code → Outcome.crashed', () async {
      final runner = ProbeRunner(
        launcher: _fakeLauncher(exitCode: 1),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final candidate = whisperCppCuda12Candidate(runner: runner);
      final result = await candidate.run(_fakeCtx);

      expect(result.candidateId, equals('whisper-cpp-cuda12'));
      expect(result.outcome, equals(Outcome.crashed));
      expect(result.exitCode, equals(1));
      expect(result.backend, equals('cuda12'));
    });

    test('exit 139 (SIGSEGV) → Outcome.crashed', () async {
      final runner = ProbeRunner(
        launcher: _fakeLauncher(exitCode: 139),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final candidate = whisperCppCuda12Candidate(runner: runner);
      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.crashed));
      expect(result.exitCode, equals(139));
    });
  });

  group('WhisperCppCandidate — Vulkan hang (AC4)', () {
    test('process never emits output before deadline → Outcome.hung', () async {
      final runner = ProbeRunner(
        launcher: _hangingLauncher(),
        startupDeadline: _tinyDeadline,
        heartbeatTimeout: _tinyHeartbeat,
      );

      final candidate = whisperCppVulkanCandidate(runner: runner);
      final result = await candidate.run(_fakeCtx);

      expect(result.candidateId, equals('whisper-cpp-vulkan'));
      expect(result.outcome, equals(Outcome.hung));
      expect(result.backend, equals('vulkan'));
    });
  });

  group('WhisperCppOpenClCandidate — always skipped (AC4)', () {
    test('returns Outcome.skipped without calling any launcher', () async {
      const candidate = WhisperCppOpenClCandidate();
      final result = await candidate.run(_fakeCtx);

      expect(result.candidateId, equals('whisper-cpp-opencl'));
      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, contains('Backend-Binary nicht beschaffbar'));
      expect(result.backend, equals('opencl'));
    });
  });

  group('WhisperCppCandidate — binary not found (AC4)', () {
    test('launcher throws → Outcome.skipped with error detail', () async {
      final runner = ProbeRunner(
        launcher: _missingBinaryLauncher(),
        startupDeadline: const Duration(seconds: 10),
        heartbeatTimeout: const Duration(seconds: 10),
      );

      final candidate = whisperCppCpuCandidate(runner: runner);
      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('nicht gefunden'));
    });
  });

  // -------------------------------------------------------------------------
  // CandidateManifest — structure tests
  // -------------------------------------------------------------------------

  group('CandidateManifest.defaults', () {
    test('contains exactly four candidates', () {
      final manifest = CandidateManifest.defaults();
      expect(manifest.candidates, hasLength(4));
    });

    test('candidate ids match expected names', () {
      final manifest = CandidateManifest.defaults();
      final ids = manifest.candidates.map((c) => c.id).toList();
      expect(
        ids,
        containsAll([
          'whisper-cpp-cpu',
          'whisper-cpp-cuda12',
          'whisper-cpp-vulkan',
          'whisper-cpp-opencl',
        ]),
      );
    });

    test('every entry exposes a non-empty model-size set (AC1)', () {
      final manifest = CandidateManifest.defaults();
      for (final entry in manifest.entries) {
        expect(
          entry.modelSizes,
          isNotEmpty,
          reason: '${entry.candidate.id} must declare a model-size set',
        );
      }
    });

    test('every entry references the same ModelManifest and its model-size '
        'set resolves to real ModelEntry names (AC1)', () {
      final manifest = CandidateManifest.defaults();
      for (final entry in manifest.entries) {
        // (b) ModelManifest reference is present.
        expect(entry.models, isA<ModelManifest>());
        expect(entry.models.entries, isNotEmpty);
        // (a) every declared size resolves to an entry in that manifest.
        for (final size in entry.modelSizes) {
          expect(
            entry.models.find(size),
            isNotNull,
            reason:
                '${entry.candidate.id} size "$size" must exist in ModelManifest',
          );
        }
      }
    });

    test('GPU/CPU backends cover the full size set; OpenCL is the legacy '
        'subset (AC1)', () {
      final manifest = CandidateManifest.defaults();
      Set<String> sizesFor(String id) =>
          manifest.entries.firstWhere((e) => e.candidate.id == id).modelSizes;

      const full = {modelSizeSmall, modelSizeMedium, modelSizeLargeTurbo};
      expect(sizesFor('whisper-cpp-cpu'), equals(full));
      expect(sizesFor('whisper-cpp-cuda12'), equals(full));
      expect(sizesFor('whisper-cpp-vulkan'), equals(full));
      expect(
        sizesFor('whisper-cpp-opencl'),
        equals({modelSizeSmall, modelSizeMedium}),
      );
    });

    test(
      'custom runner is threaded through subprocess-backed candidates',
      () async {
        // All subprocess candidates should use the injected fake launcher.
        final runner = ProbeRunner(
          launcher: _fakeLauncher(
            exitCode: 0,
            stdoutLines: _sampleWhisperOutput,
          ),
          startupDeadline: const Duration(seconds: 10),
          heartbeatTimeout: const Duration(seconds: 10),
        );

        final manifest = CandidateManifest.defaults(
          runner: runner,
          referenceTranscript: _expectedTranscript,
        );

        // Run all candidates — none should throw.
        final results = <CandidateResult>[];
        for (final candidate in manifest.candidates) {
          final result = await candidate.run(_fakeCtx);
          results.add(result);
        }

        // OpenCL is always skipped regardless of runner.
        final openClResult = results.firstWhere(
          (r) => r.candidateId == 'whisper-cpp-opencl',
        );
        expect(openClResult.outcome, equals(Outcome.skipped));

        // CPU with exit 0 and valid stdout → ok.
        final cpuResult = results.firstWhere(
          (r) => r.candidateId == 'whisper-cpp-cpu',
        );
        expect(cpuResult.outcome, equals(Outcome.ok));
      },
    );
  });
}
