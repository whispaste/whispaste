/// Tests for [FasterWhisperCandidate] — transcript parser, output-file vs
/// stdout reading, the CLI flags, and the subprocess pipeline (ok / crash /
/// missing-model / missing-binary).
///
/// All tests use fake [ProcessLauncher] seams — no real engine is ever spawned.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors sherpa_onnx_candidate_test.dart)
// ---------------------------------------------------------------------------

class _FakeProcess implements Process {
  _FakeProcess();
  final _exitCompleter = Completer<int>();
  void complete(int code) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(code);
  }

  @override
  Future<int> get exitCode => _exitCompleter.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
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

ProcessLauncher _fakeLauncher({
  required int exitCode,
  List<String> stdoutLines = const [],
  List<String> stderrLines = const [],
  void Function(List<String> args)? onArgs,
}) {
  return (executable, arguments, workingDirectory) async {
    onArgs?.call(List.unmodifiable(arguments));
    final fake = _FakeProcess();
    scheduleMicrotask(() => fake.complete(exitCode));
    final stdoutCtrl = StreamController<String>();
    for (final line in stdoutLines) {
      stdoutCtrl.add(line);
    }
    stdoutCtrl.close();
    final stderrCtrl = StreamController<String>();
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

ProcessLauncher _missingBinaryLauncher() =>
    (executable, arguments, workingDirectory) async =>
        throw Exception('No such file or directory: $executable');

ProbeRunner _fastRunner(ProcessLauncher launcher) => ProbeRunner(
  launcher: launcher,
  startupDeadline: const Duration(seconds: 10),
  heartbeatTimeout: const Duration(seconds: 10),
);

const _segmentLine = '[00:00.000 --> 00:02.020]  Guten Tag, das ist ein Test.';
const _expectedTranscript = 'Guten Tag, das ist ein Test.';

/// A throwaway CT2 bundle directory named `faster-whisper-small` (the basename
/// is the model-name lookup key the candidate derives), inside a temp parent.
/// Returns the bundle dir; its parent is `dir.parent`.
Directory _modelDir() {
  final parent = Directory.systemTemp.createTempSync('ct2-parent-');
  final dir = Directory(p.join(parent.path, 'faster-whisper-small'))
    ..createSync();
  File(p.join(dir.path, 'model.bin')).writeAsStringSync('x');
  File(p.join(dir.path, 'config.json')).writeAsStringSync('{}');
  return dir;
}

ProbeContext _ctx(String modelDir, String workDir) => ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: modelDir,
  workDir: workDir,
  language: 'de',
  timeout: const Duration(seconds: 30),
);

void main() {
  // -------------------------------------------------------------------------
  // Parser
  // -------------------------------------------------------------------------
  group('parseFasterWhisperTranscript', () {
    test('strips the timestamp block from a segment line', () {
      expect(
        parseFasterWhisperTranscript([_segmentLine]),
        equals(_expectedTranscript),
      );
    });

    test('joins multiple segments with a space', () {
      expect(
        parseFasterWhisperTranscript([
          '[00:00.000 --> 00:01.000]  Erster Teil.',
          '[00:01.000 --> 00:02.000]  Zweiter Teil.',
        ]),
        equals('Erster Teil. Zweiter Teil.'),
      );
    });

    test('takes plain (timestamp-less) lines verbatim', () {
      expect(
        parseFasterWhisperTranscript(['Nur Text ohne Zeit.']),
        equals('Nur Text ohne Zeit.'),
      );
    });

    test('ignores blank lines → empty string', () {
      expect(parseFasterWhisperTranscript(['', '  ']), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Subprocess pipeline
  // -------------------------------------------------------------------------
  group('FasterWhisperCandidate', () {
    test('reads the output .txt written into the work dir', () async {
      final model = _modelDir();
      final work = Directory.systemTemp.createTempSync('ct2-work-');
      addTearDown(() => model.parent.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));
      // whisper-faster writes <stem>.txt; the launcher itself emits nothing.
      File(p.join(work.path, 'ref.txt')).writeAsStringSync(_segmentLine);

      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(_fakeLauncher(exitCode: 0)),
        referenceTranscript: _expectedTranscript,
      );
      final result = await candidate.run(_ctx(model.path, work.path));
      expect(result.outcome, Outcome.ok);
      expect(result.transcribedText, _expectedTranscript);
      expect(result.wer, closeTo(0.0, 0.01));
      expect(result.backend, 'ct2-cpu');
      // Output file is consumed (deleted) after reading.
      expect(File(p.join(work.path, 'ref.txt')).existsSync(), isFalse);
    });

    test('falls back to stdout when no output file exists', () async {
      final model = _modelDir();
      final work = Directory.systemTemp.createTempSync('ct2-work-');
      addTearDown(() => model.parent.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));

      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, stdoutLines: [_segmentLine]),
        ),
      );
      final result = await candidate.run(_ctx(model.path, work.path));
      expect(result.outcome, Outcome.ok);
      expect(result.transcribedText, _expectedTranscript);
    });

    test('passes the CLI flags and the model directory', () async {
      final model = _modelDir();
      final work = Directory.systemTemp.createTempSync('ct2-work-');
      addTearDown(() => model.parent.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));
      File(p.join(work.path, 'ref.txt')).writeAsStringSync(_segmentLine);

      List<String>? args;
      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, onArgs: (a) => args = a),
        ),
      );
      await candidate.run(_ctx(model.path, work.path));
      expect(args, isNotNull);
      // wav is the first positional argument.
      expect(args!.first, '/fake/ref.wav');
      // model NAME (basename with the faster-whisper- prefix stripped) +
      // the parent dir as --model_dir.
      expect(args, containsAllInOrder(['--model', 'small']));
      expect(args, containsAllInOrder(['--model_dir', model.parent.path]));
      expect(args, containsAllInOrder(['--language', 'de']));
      expect(args, containsAllInOrder(['--device', 'cpu']));
      expect(args, containsAllInOrder(['--compute_type', 'int8']));
      expect(args, containsAllInOrder(['--output_format', 'txt']));
      expect(args, containsAllInOrder(['--output_dir', work.path]));
      expect(args, contains('--beep_off'));
    });

    test('cuda variant passes --device cuda', () async {
      final model = _modelDir();
      final work = Directory.systemTemp.createTempSync('ct2-work-');
      addTearDown(() => model.parent.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));

      List<String>? args;
      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cuda',
        binaryName: 'whisper-faster',
        backend: 'ct2-cuda',
        device: 'cuda',
        computeType: 'int8_float16',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 0, onArgs: (a) => args = a),
        ),
      );
      await candidate.run(_ctx(model.path, work.path));
      expect(args, containsAllInOrder(['--device', 'cuda']));
      expect(args, containsAllInOrder(['--compute_type', 'int8_float16']));
    });

    test('missing model directory → Outcome.skipped', () async {
      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(_fakeLauncher(exitCode: 0)),
      );
      final result = await candidate.run(
        _ctx('/definitely/missing', Directory.systemTemp.path),
      );
      expect(result.outcome, Outcome.skipped);
      expect(result.errorDetail, contains('Modellverzeichnis'));
    });

    test('missing binary → Outcome.skipped', () async {
      final model = _modelDir();
      addTearDown(() => model.parent.deleteSync(recursive: true));
      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(_missingBinaryLauncher()),
      );
      final result = await candidate.run(
        _ctx(model.path, Directory.systemTemp.path),
      );
      expect(result.outcome, Outcome.skipped);
      expect(result.errorDetail, contains('nicht gefunden'));
    });

    test('non-zero exit → Outcome.crashed with exit code', () async {
      final model = _modelDir();
      final work = Directory.systemTemp.createTempSync('ct2-work-');
      addTearDown(() => model.parent.deleteSync(recursive: true));
      addTearDown(() => work.deleteSync(recursive: true));
      final candidate = FasterWhisperCandidate(
        id: 'faster-whisper-cpu',
        binaryName: 'whisper-faster',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 2, stderrLines: ['fatal: bad model']),
        ),
      );
      final result = await candidate.run(_ctx(model.path, work.path));
      expect(result.outcome, Outcome.crashed);
      expect(result.exitCode, 2);
      expect(result.stderrTail, contains('bad model'));
    });
  });
}
