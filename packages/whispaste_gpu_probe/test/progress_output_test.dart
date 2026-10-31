/// Tests for the progress output feature of [runProbeOrchestrator].
///
/// Verifies that:
///   - One progress line is emitted BEFORE each candidate.
///   - One outcome line is emitted AFTER each candidate.
///   - The progress line contains the correct position "k von n" and candidate id.
///   - The outcome line contains the candidate id and the outcome name.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake candidates
// ---------------------------------------------------------------------------

class _FakeCandidate implements ProbeCandidate {
  const _FakeCandidate(this._id, this._outcome);

  final String _id;
  final Outcome _outcome;

  @override
  String get id => _id;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    return CandidateResult(candidateId: _id, outcome: _outcome);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DateTime _fixedClock() => DateTime.utc(2026, 6, 15, 12, 0, 0);

ProbeContext get _ctx => const ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.bin',
  workDir: '/tmp/fake-work',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gpu_probe_progress_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('progress output', () {
    test('emits exactly 2 lines per candidate (progress + outcome)', () async {
      final logged = <String>[];
      final candidates = [
        const _FakeCandidate('alpha', Outcome.ok),
        const _FakeCandidate('beta', Outcome.crashed),
        const _FakeCandidate('gamma', Outcome.skipped),
      ];

      await runProbeOrchestrator(
        candidates: candidates,
        context: _ctx,
        outputDir: tempDir.path,
        version: 'test',
        clock: _fixedClock,
        logger: logged.add,
      );

      // 2 lines per candidate: progress before + outcome after.
      expect(logged, hasLength(candidates.length * 2));
    });

    test('each progress line contains correct "k von n" position', () async {
      final logged = <String>[];
      final candidates = [
        const _FakeCandidate('alpha', Outcome.ok),
        const _FakeCandidate('beta', Outcome.ok),
        const _FakeCandidate('gamma', Outcome.ok),
      ];

      await runProbeOrchestrator(
        candidates: candidates,
        context: _ctx,
        outputDir: tempDir.path,
        version: 'test',
        clock: _fixedClock,
        logger: logged.add,
      );

      // Progress lines are at indices 0, 2, 4 (every other line).
      expect(logged[0], contains('1 von 3'));
      expect(logged[2], contains('2 von 3'));
      expect(logged[4], contains('3 von 3'));
    });

    test('each progress line contains the candidate id', () async {
      final logged = <String>[];
      final candidates = [
        const _FakeCandidate('whisper-cpp-cuda', Outcome.ok),
        const _FakeCandidate('whisper-cpp-vulkan', Outcome.ok),
      ];

      await runProbeOrchestrator(
        candidates: candidates,
        context: _ctx,
        outputDir: tempDir.path,
        version: 'test',
        clock: _fixedClock,
        logger: logged.add,
      );

      expect(logged[0], contains('whisper-cpp-cuda'));
      expect(logged[2], contains('whisper-cpp-vulkan'));
    });

    test(
      'each outcome line contains the candidate id and outcome name',
      () async {
        final logged = <String>[];
        final candidates = [
          const _FakeCandidate('alpha', Outcome.ok),
          const _FakeCandidate('beta', Outcome.crashed),
        ];

        await runProbeOrchestrator(
          candidates: candidates,
          context: _ctx,
          outputDir: tempDir.path,
          version: 'test',
          clock: _fixedClock,
          logger: logged.add,
        );

        // Outcome lines are at indices 1, 3.
        expect(logged[1], contains('alpha'));
        expect(logged[1], contains('ok'));
        expect(logged[3], contains('beta'));
        expect(logged[3], contains('crashed'));
      },
    );

    test(
      'progress line is emitted BEFORE outcome line for each candidate',
      () async {
        // Verify ordering: for each candidate the progress line index < outcome
        // line index AND is consecutive (no interleaving with other candidates).
        final logged = <String>[];
        final candidates = [
          const _FakeCandidate('first', Outcome.ok),
          const _FakeCandidate('second', Outcome.ok),
        ];

        await runProbeOrchestrator(
          candidates: candidates,
          context: _ctx,
          outputDir: tempDir.path,
          version: 'test',
          clock: _fixedClock,
          logger: logged.add,
        );

        // Pair layout: [progress-1, outcome-1, progress-2, outcome-2]
        expect(logged[0], contains('1 von 2'));
        expect(logged[1], contains('first'));
        expect(logged[2], contains('2 von 2'));
        expect(logged[3], contains('second'));
      },
    );

    test('single candidate emits exactly 2 lines', () async {
      final logged = <String>[];

      await runProbeOrchestrator(
        candidates: [const _FakeCandidate('solo', Outcome.ok)],
        context: _ctx,
        outputDir: tempDir.path,
        version: 'test',
        clock: _fixedClock,
        logger: logged.add,
      );

      expect(logged, hasLength(2));
      expect(logged[0], contains('1 von 1'));
      expect(logged[0], contains('solo'));
      expect(logged[1], contains('solo'));
      expect(logged[1], contains('ok'));
    });

    test('logger defaults to print (no exception when omitted)', () async {
      // Just verify no exception is thrown when logger is omitted.
      await expectLater(
        runProbeOrchestrator(
          candidates: [const _FakeCandidate('x', Outcome.ok)],
          context: _ctx,
          outputDir: tempDir.path,
          version: 'test',
          clock: _fixedClock,
          // logger omitted → uses print
        ),
        completes,
      );
    });
  });
}
