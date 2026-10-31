/// Tests for the German wav2vec2/Conformer DirectML candidate (Slice 15).
///
/// All tests use fake [ProcessLauncher] seams — no real engine process is
/// ever spawned.
///
/// ## AC coverage
///
/// - AC2: candidate is built on [OnnxDirectMlCandidate] with a custom parser,
///   NOT a new runner.
/// - AC4 (ok path): fake launcher → wav2vec2 ONNX stdout → Outcome.ok with WER.
/// - AC4 (skipped path): missing binary → Outcome.skipped, matrix continues.
/// - AC4 (parser golden): [parseWav2Vec2Transcript] golden test.
/// - AC5: WER normalization handles format differences (punctuation, casing).
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors onnx_direct_ml_candidate_test.dart)
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

/// Creates a [ProcessLauncher] that immediately returns a fake process with
/// the given [exitCode], optional [stdoutLines], and optional [stderrLines].
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

/// Creates a [ProcessLauncher] that throws to simulate a missing binary /
/// DirectML EP not loadable.
ProcessLauncher _missingBinaryLauncher() {
  return (executable, arguments, workingDirectory) async {
    throw Exception('No such file or directory: $executable');
  };
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Sample wav2vec2 runner stdout (info lines + text line).
const _sampleWav2Vec2Output = [
  '[wav2vec2] Loading ONNX model...',
  '[wav2vec2] DirectML execution provider active.',
  'text: Guten Tag, das ist ein Test.',
  '[wav2vec2] Inference complete.',
];

/// Expected transcript extracted from [_sampleWav2Vec2Output].
const _expectedTranscript = 'Guten Tag, das ist ein Test.';

/// Minimal [ProbeContext] for tests.
final _fakeCtx = ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/wav2vec2.onnx',
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
  // AC4 (parser golden): [parseWav2Vec2Transcript] pure-function golden tests
  // -------------------------------------------------------------------------

  group('parseWav2Vec2Transcript — parser golden test (AC4)', () {
    test('extracts text line and returns the transcript', () {
      final transcript = parseWav2Vec2Transcript(_sampleWav2Vec2Output);
      expect(transcript, equals(_expectedTranscript));
    });

    test('ignores [wav2vec2] info lines and returns first text: line', () {
      final output = [
        '[wav2vec2] Starting inference...',
        'text: Hallo Welt.',
        '[wav2vec2] Done.',
      ];
      expect(parseWav2Vec2Transcript(output), equals('Hallo Welt.'));
    });

    test('empty stdout → empty string', () {
      expect(parseWav2Vec2Transcript([]), isEmpty);
    });

    test('only info lines → empty string', () {
      expect(
        parseWav2Vec2Transcript(['[wav2vec2] Loading...', '[wav2vec2] Done.']),
        isEmpty,
      );
    });

    test('text: prefix is case-insensitive', () {
      final output = ['Text: Groß geschrieben.'];
      expect(parseWav2Vec2Transcript(output), equals('Groß geschrieben.'));
    });

    test('only first text: line is returned', () {
      final output = ['text: Erster Satz.', 'text: Zweiter Satz.'];
      expect(parseWav2Vec2Transcript(output), equals('Erster Satz.'));
    });

    test('leading/trailing whitespace in transcript text is stripped', () {
      final output = ['text:   Leerzeichen drumherum.   '];
      expect(parseWav2Vec2Transcript(output), equals('Leerzeichen drumherum.'));
    });
  });

  // -------------------------------------------------------------------------
  // AC2: candidate is built on OnnxDirectMlCandidate, not a new runner
  // -------------------------------------------------------------------------

  group('wav2vec2DirectMlCandidate — reuses OnnxDirectMlCandidate (AC2)', () {
    test('factory returns an OnnxDirectMlCandidate instance', () {
      final candidate = wav2vec2DirectMlCandidate(
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleWav2Vec2Output),
        ),
      );
      expect(
        candidate,
        isA<OnnxDirectMlCandidate>(),
        reason:
            'Slice 15 must reuse OnnxDirectMlCandidate, not a new runner class',
      );
    });

    test('candidate id is wav2vec2-directml-de', () {
      final candidate = wav2vec2DirectMlCandidate();
      expect(candidate.id, equals('wav2vec2-directml-de'));
    });

    test('backend label is wav2vec2-directml', () {
      final candidate = wav2vec2DirectMlCandidate();
      expect(candidate.backend, equals('wav2vec2-directml'));
    });

    test('outputParser is parseWav2Vec2Transcript', () {
      final candidate = wav2vec2DirectMlCandidate();
      // Confirm the parser is the wav2vec2-specific one, not the Whisper one.
      // We do this by feeding wav2vec2-format output through the candidate's
      // parser field directly.
      final result = candidate.outputParser(_sampleWav2Vec2Output);
      expect(result, equals(_expectedTranscript));
    });
  });

  // -------------------------------------------------------------------------
  // AC4 (ok path): fake launcher → exit 0 + wav2vec2 stdout → Outcome.ok
  // -------------------------------------------------------------------------

  group('wav2vec2DirectMlCandidate — ok path (AC4)', () {
    test(
      'exit 0 + transcript stdout → Outcome.ok with transcript and WER',
      () async {
        final candidate = wav2vec2DirectMlCandidate(
          runner: _fastRunner(
            _fakeLauncher(exitCode: 0, stdoutLines: _sampleWav2Vec2Output),
          ),
          referenceTranscript: _expectedTranscript,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.candidateId, equals('wav2vec2-directml-de'));
        expect(result.outcome, equals(Outcome.ok));
        expect(result.transcribedText, equals(_expectedTranscript));
        expect(result.wer, closeTo(0.0, 0.01));
        expect(result.backend, equals('wav2vec2-directml'));
        expect(result.durationMs, greaterThanOrEqualTo(0));
      },
    );

    test('no referenceTranscript → wer is null, outcome still ok', () async {
      final candidate = wav2vec2DirectMlCandidate(
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleWav2Vec2Output),
        ),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.wer, isNull);
      expect(result.outcome, equals(Outcome.ok));
    });

    test('spawns with explicit "de" language flag', () async {
      List<String>? capturedArgs;

      Future<ProcessStartResult> spyLauncher(
        String executable,
        List<String> arguments,
        String workingDirectory,
      ) async {
        capturedArgs = List.unmodifiable(arguments);
        final fake = _FakeProcess();
        scheduleMicrotask(() => fake.complete(0));
        final stdoutCtrl = StreamController<String>();
        for (final line in _sampleWav2Vec2Output) {
          stdoutCtrl.add(line);
        }
        stdoutCtrl.close();
        return ProcessStartResult(
          process: fake,
          stdout: stdoutCtrl.stream,
          stderr: const Stream.empty(),
        );
      }

      final candidate = wav2vec2DirectMlCandidate(
        runner: _fastRunner(spyLauncher),
      );

      await candidate.run(_fakeCtx);

      expect(capturedArgs, isNotNull);
      final langIdx = capturedArgs!.indexOf('--language');
      expect(langIdx, isNot(-1), reason: '--language flag must be present');
      expect(capturedArgs![langIdx + 1], equals('de'));
    });
  });

  // -------------------------------------------------------------------------
  // AC4 (skipped path): no GPU-accelerated path → skipped, matrix continues
  // -------------------------------------------------------------------------

  group('wav2vec2DirectMlCandidate — skipped path (AC4)', () {
    test(
      'missing binary / DirectML EP not loadable → Outcome.skipped with reason',
      () async {
        final candidate = wav2vec2DirectMlCandidate(
          runner: _fastRunner(_missingBinaryLauncher()),
        );

        final result = await candidate.run(_fakeCtx);

        expect(
          result.outcome,
          equals(Outcome.skipped),
          reason: 'skipped outcome must allow the matrix to continue',
        );
        expect(result.errorDetail, isNotNull);
        expect(
          result.errorDetail,
          isNotEmpty,
          reason: 'skipped result must include a human-readable reason',
        );
      },
    );

    test(
      'skipped result does not carry a transcript (matrix must continue cleanly)',
      () async {
        final candidate = wav2vec2DirectMlCandidate(
          runner: _fastRunner(_missingBinaryLauncher()),
        );

        final result = await candidate.run(_fakeCtx);

        // Transcript must be absent so downstream consumers do not treat a
        // skipped run as a successful one.
        expect(result.transcribedText, isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC5: WER normalization handles format differences
  // -------------------------------------------------------------------------

  group('wav2vec2DirectMlCandidate — WER normalization (AC5)', () {
    test(
      'wav2vec2 output with extra punctuation still yields low WER',
      () async {
        // wav2vec2 models may emit all-caps or add commas differently.
        // normalizeForWer strips punctuation and lowercases → WER is still 0.
        const wav2vec2StyleOutput = ['text: GUTEN TAG DAS IST EIN TEST'];

        final candidate = wav2vec2DirectMlCandidate(
          runner: _fastRunner(
            _fakeLauncher(exitCode: 0, stdoutLines: wav2vec2StyleOutput),
          ),
          // Reference uses canonical casing + punctuation.
          referenceTranscript: _expectedTranscript,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.outcome, equals(Outcome.ok));
        // After normalization both sides become identical → WER = 0.
        expect(result.wer, closeTo(0.0, 0.01));
      },
    );

    test(
      'normalization removes trailing periods and punctuation from both sides',
      () async {
        // Confirm normalizeForWer itself handles the format difference.
        const hypothesis = 'Guten Tag, das ist ein Test.';
        const reference = 'Guten Tag das ist ein Test';

        final wer = computeWer(hypothesis, reference);
        expect(wer, closeTo(0.0, 0.01));
      },
    );
  });

  // -------------------------------------------------------------------------
  // CandidateManifest — wav2vec2 entry present
  // -------------------------------------------------------------------------

  group('CandidateManifest — wav2vec2 entry (Slice 15)', () {
    test('defaults manifest includes wav2vec2-directml-de entry', () {
      final manifest = CandidateManifest.defaults();
      final entries = manifest.entries
          .where((e) => e.candidate.id == 'wav2vec2-directml-de')
          .toList();
      expect(
        entries,
        isNotEmpty,
        reason: 'manifest must contain a wav2vec2-directml-de entry',
      );
    });

    test('wav2vec2 entry references its own ModelManifest', () {
      final manifest = CandidateManifest.defaults();
      final entry = manifest.entries.firstWhere(
        (e) => e.candidate.id == 'wav2vec2-directml-de',
      );

      expect(entry.models, isA<ModelManifest>());
      expect(entry.models.entries, isNotEmpty);

      for (final size in entry.modelSizes) {
        expect(
          entry.models.find(size),
          isNotNull,
          reason: 'wav2vec2 size "$size" must resolve in its ModelManifest',
        );
      }
    });

    test('wav2vec2 model manifest contains the xlsr53-german entry', () {
      final manifest = CandidateManifest.defaults();
      final entry = manifest.entries.firstWhere(
        (e) => e.candidate.id == 'wav2vec2-directml-de',
      );

      expect(entry.modelSizes, contains(wav2vec2ModelSizeKey));
      expect(entry.models.find(wav2vec2ModelSizeKey), isNotNull);
    });

    test('existing Slice-14 onnx-directml entry is unaffected', () {
      final manifest = CandidateManifest.defaults();
      final onnxEntries = manifest.entries
          .where((e) => e.candidate.id == 'onnx-directml')
          .toList();
      expect(
        onnxEntries,
        isNotEmpty,
        reason: 'Slice-14 onnx-directml entry must remain in the manifest',
      );
    });

    test(
      'custom runner is forwarded to wav2vec2 subprocess candidate',
      () async {
        int callCount = 0;

        Future<ProcessStartResult> spyLauncher(
          String executable,
          List<String> arguments,
          String workingDirectory,
        ) async {
          callCount++;
          final fake = _FakeProcess();
          scheduleMicrotask(() => fake.complete(0));
          final stdoutCtrl = StreamController<String>();
          for (final line in _sampleWav2Vec2Output) {
            stdoutCtrl.add(line);
          }
          stdoutCtrl.close();
          return ProcessStartResult(
            process: fake,
            stdout: stdoutCtrl.stream,
            stderr: const Stream.empty(),
          );
        }

        final manifest = CandidateManifest.defaults(
          runner: _fastRunner(spyLauncher),
          referenceTranscript: _expectedTranscript,
        );

        for (final entry in manifest.entries) {
          if (entry.candidate.id == 'wav2vec2-directml-de') {
            await entry.candidate.run(_fakeCtx);
          }
        }

        expect(
          callCount,
          greaterThan(0),
          reason: 'wav2vec2-directml-de must invoke the launcher',
        );
      },
    );
  });
}
