/// Tests for OnnxDirectMlCandidate (ONNX Runtime + DirectML backend).
///
/// All tests use fake [ProcessLauncher] seams — no real engine process is ever
/// spawned.
///
/// ## AC5 note — reuse by Slice 15
///
/// The [outputParser] parameter on [OnnxDirectMlCandidate] lets Slice 15
/// supply a different transcript-extraction strategy while reusing the entire
/// subprocess-spawn / WER / classify pipeline.  A test demonstrates this by
/// constructing a candidate with a custom parser.
///
/// ## 887A0006 note
///
/// HRESULT `0x887A0006` = `DXGI_ERROR_DEVICE_HUNG` (-2005270522 signed 32-bit).
/// When a Windows runner exits due to this error, the process typically
/// terminates with a non-zero exit code.  [classifyOutcome] maps any non-zero
/// exit code to [Outcome.crashed] and preserves the exit code + stderr tail as
/// evidence in [CandidateResult].
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors const_me_candidate_test.dart)
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
// Test fixtures
// ---------------------------------------------------------------------------

/// Sample ONNX DirectML runner stdout (info lines + transcript line).
const _sampleOnnxOutput = [
  '[whisper-onnx] Transcribing with DirectML...',
  '[whisper-onnx] Model loaded in 312 ms',
  'transcript: Guten Tag, das ist ein Test.',
  '[whisper-onnx] Done.',
];

/// Expected transcript extracted from [_sampleOnnxOutput].
const _expectedTranscript = 'Guten Tag, das ist ein Test.';

/// Minimal [ProbeContext] for tests.
final _fakeCtx = ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: '/fake/model.onnx',
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
  // AC4 (parsing): Parser golden test (pure function)
  // -------------------------------------------------------------------------

  group('parseOnnxDirectMlTranscript — parser golden test (AC4)', () {
    test('extracts transcript line and returns the text', () {
      final transcript = parseOnnxDirectMlTranscript(_sampleOnnxOutput);
      expect(transcript, equals(_expectedTranscript));
    });

    test('ignores [whisper-onnx] info lines and returns first transcript', () {
      final output = [
        '[whisper-onnx] Loading model...',
        'transcript: Hallo Welt.',
        '[whisper-onnx] Done.',
      ];
      expect(parseOnnxDirectMlTranscript(output), equals('Hallo Welt.'));
    });

    test('empty stdout → empty string', () {
      expect(parseOnnxDirectMlTranscript([]), isEmpty);
    });

    test('only info lines → empty string', () {
      expect(
        parseOnnxDirectMlTranscript([
          '[whisper-onnx] Transcribing...',
          '[whisper-onnx] Done.',
        ]),
        isEmpty,
      );
    });

    test('transcript: prefix is case-insensitive', () {
      final output = ['Transcript: Groß geschrieben.'];
      expect(parseOnnxDirectMlTranscript(output), equals('Groß geschrieben.'));
    });

    test('only first transcript: line is returned', () {
      final output = ['transcript: Erster Satz.', 'transcript: Zweiter Satz.'];
      // Only the first match is returned.
      expect(parseOnnxDirectMlTranscript(output), equals('Erster Satz.'));
    });

    test('leading/trailing whitespace in transcript text is stripped', () {
      final output = ['transcript:   Leerzeichen drumherum.   '];
      expect(
        parseOnnxDirectMlTranscript(output),
        equals('Leerzeichen drumherum.'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC2 + AC4 (ok path): fake launcher → exit 0 + sample output → Outcome.ok
  // -------------------------------------------------------------------------

  group('OnnxDirectMlCandidate — ok path (AC2, AC4)', () {
    test(
      'exit 0 + transcript stdout → Outcome.ok with transcript and WER',
      () async {
        final candidate = OnnxDirectMlCandidate(
          id: 'onnx-directml',
          binaryName: 'whisper-onnx-directml.exe',
          runner: _fastRunner(
            _fakeLauncher(exitCode: 0, stdoutLines: _sampleOnnxOutput),
          ),
          referenceTranscript: _expectedTranscript,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.candidateId, equals('onnx-directml'));
        expect(result.outcome, equals(Outcome.ok));
        expect(result.transcribedText, equals(_expectedTranscript));
        expect(result.wer, closeTo(0.0, 0.01));
        expect(result.backend, equals('directml'));
        expect(result.durationMs, greaterThanOrEqualTo(0));
      },
    );

    test('no referenceTranscript → wer is null, outcome still ok', () async {
      final candidate = OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: 'whisper-onnx-directml.exe',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleOnnxOutput),
        ),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.wer, isNull);
      expect(result.outcome, equals(Outcome.ok));
    });

    test('spawns with explicit "de" language flag (AC2)', () async {
      // Capture the arguments passed to the launcher.
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
        for (final line in _sampleOnnxOutput) {
          stdoutCtrl.add(line);
        }
        stdoutCtrl.close();
        return ProcessStartResult(
          process: fake,
          stdout: stdoutCtrl.stream,
          stderr: const Stream.empty(),
        );
      }

      final candidate = OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: 'whisper-onnx-directml.exe',
        runner: _fastRunner(spyLauncher),
      );

      await candidate.run(_fakeCtx);

      expect(capturedArgs, isNotNull);
      // '--language' must be present and immediately followed by 'de'.
      final langIdx = capturedArgs!.indexOf('--language');
      expect(langIdx, isNot(-1), reason: '--language flag must be present');
      expect(capturedArgs![langIdx + 1], equals('de'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4 (887A0006 crash path): non-zero exit → Outcome.crashed
  // -------------------------------------------------------------------------

  group('OnnxDirectMlCandidate — 887A0006 crash (AC3, AC4)', () {
    test(
      '887A0006 exit code (-2005270522 signed) → Outcome.crashed with evidence',
      () async {
        // HRESULT 0x887A0006 as signed 32-bit integer.
        const exitCode887A0006 = -2005270522;

        final candidate = OnnxDirectMlCandidate(
          id: 'onnx-directml',
          binaryName: 'whisper-onnx-directml.exe',
          runner: _fastRunner(
            _fakeLauncher(
              exitCode: exitCode887A0006,
              stderrLines: [
                'DXGI_ERROR_DEVICE_HUNG (0x887A0006)',
                'DirectML execution failed.',
              ],
            ),
          ),
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.outcome, equals(Outcome.crashed));
        expect(result.exitCode, equals(exitCode887A0006));
        // stderr tail must be captured as evidence.
        expect(result.stderrTail, isNotNull);
        expect(result.stderrTail, contains('887A0006'));
        expect(result.backend, equals('directml'));
      },
    );

    test('arbitrary non-zero exit code → Outcome.crashed', () async {
      final candidate = OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: 'whisper-onnx-directml.exe',
        runner: _fastRunner(_fakeLauncher(exitCode: 1)),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.crashed));
      expect(result.exitCode, equals(1));
    });

    test('exit code and error detail are both present as evidence', () async {
      const exitCode887A0006 = -2005270522;

      final candidate = OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: 'whisper-onnx-directml.exe',
        runner: _fastRunner(
          _fakeLauncher(
            exitCode: exitCode887A0006,
            stderrLines: ['0x887A0006 DXGI_ERROR_DEVICE_HUNG'],
          ),
        ),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.exitCode, equals(exitCode887A0006));
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('$exitCode887A0006'));
      expect(result.stderrTail, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // Binary not found
  // -------------------------------------------------------------------------

  group('OnnxDirectMlCandidate — binary not found', () {
    test('launcher throws → Outcome.skipped with error detail', () async {
      final candidate = OnnxDirectMlCandidate(
        id: 'onnx-directml',
        binaryName: 'whisper-onnx-directml.exe',
        runner: _fastRunner(_missingBinaryLauncher()),
      );

      final result = await candidate.run(_fakeCtx);

      expect(result.outcome, equals(Outcome.skipped));
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('nicht gefunden'));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: Custom outputParser — reuse by Slice 15
  // -------------------------------------------------------------------------

  group('OnnxDirectMlCandidate — custom outputParser (AC5)', () {
    test(
      'custom parser is invoked and its output drives WER + outcome',
      () async {
        // Slice 15 might use a runner that emits JSON; a custom parser handles it.
        const customOutput = ['{"result": "Guten Tag, das ist ein Test."}'];

        String customParser(List<String> lines) {
          for (final line in lines) {
            if (line.contains('"result"')) {
              final match = RegExp(r'"result":\s*"([^"]+)"').firstMatch(line);
              if (match != null) return match.group(1)!;
            }
          }
          return '';
        }

        final candidate = OnnxDirectMlCandidate(
          id: 'onnx-directml-slice15',
          binaryName: 'whisper-onnx-directml.exe',
          runner: _fastRunner(
            _fakeLauncher(exitCode: 0, stdoutLines: customOutput),
          ),
          referenceTranscript: _expectedTranscript,
          outputParser: customParser,
        );

        final result = await candidate.run(_fakeCtx);

        expect(result.outcome, equals(Outcome.ok));
        expect(result.transcribedText, equals(_expectedTranscript));
        expect(result.wer, closeTo(0.0, 0.01));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Factory constructor
  // -------------------------------------------------------------------------

  group('onnxDirectMlCandidate factory', () {
    test('produces candidate with correct id and backend', () async {
      final candidate = onnxDirectMlCandidate(
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: _sampleOnnxOutput),
        ),
      );

      expect(candidate.id, equals('onnx-directml'));

      final result = await candidate.run(_fakeCtx);
      expect(result.backend, equals('directml'));
    });
  });

  // -------------------------------------------------------------------------
  // AC1: CandidateManifest — ONNX-DirectML entry present
  // -------------------------------------------------------------------------

  group('CandidateManifest — ONNX-DirectML entry (AC1)', () {
    test('defaults manifest includes onnx-directml entry', () {
      final manifest = CandidateManifest.defaults();
      final onnxEntries = manifest.entries
          .where((e) => e.candidate.id == 'onnx-directml')
          .toList();
      expect(
        onnxEntries,
        isNotEmpty,
        reason: 'manifest must contain an onnx-directml entry',
      );
    });

    test('ONNX-DirectML entry references ONNX ModelManifest', () {
      final manifest = CandidateManifest.defaults();
      final onnxEntry = manifest.entries.firstWhere(
        (e) => e.candidate.id == 'onnx-directml',
      );

      expect(onnxEntry.models, isA<ModelManifest>());
      expect(onnxEntry.models.entries, isNotEmpty);

      // Every declared model size must resolve in the ONNX manifest.
      for (final size in onnxEntry.modelSizes) {
        expect(
          onnxEntry.models.find(size),
          isNotNull,
          reason: 'ONNX size "$size" must resolve in the ONNX ModelManifest',
        );
      }
    });

    test('ONNX-DirectML entry covers small and medium model sizes', () {
      final manifest = CandidateManifest.defaults();
      final onnxEntry = manifest.entries.firstWhere(
        (e) => e.candidate.id == 'onnx-directml',
      );

      expect(onnxEntry.modelSizes, contains(onnxModelSizeSmall));
      expect(onnxEntry.modelSizes, contains(onnxModelSizeMedium));
    });

    test('existing candidates are unaffected by adding ONNX-DirectML', () {
      final manifest = CandidateManifest.defaults();
      final ids = manifest.entries.map((e) => e.candidate.id).toSet();

      expect(ids, contains('whisper-cpp-cpu'));
      expect(ids, contains('whisper-cpp-cuda12'));
      expect(ids, contains('whisper-cpp-vulkan'));
      expect(ids, contains('whisper-cpp-opencl'));
      expect(ids, contains('const-me-directcompute'));
    });

    test(
      'custom runner is forwarded to ONNX-DirectML subprocess candidate',
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
          for (final line in _sampleOnnxOutput) {
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

        // Run only the ONNX-DirectML entry.
        for (final entry in manifest.entries) {
          if (entry.candidate.id == 'onnx-directml') {
            await entry.candidate.run(_fakeCtx);
          }
        }

        expect(
          callCount,
          greaterThan(0),
          reason: 'ONNX-DirectML must invoke the launcher',
        );
      },
    );
  });
}
