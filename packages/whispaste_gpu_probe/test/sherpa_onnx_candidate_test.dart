/// Tests for [SherpaOnnxCandidate] — JSON parser, bundle-file resolution, and
/// the subprocess pipeline (ok / crash / missing-files / missing-binary).
///
/// All tests use fake [ProcessLauncher] seams — no real engine is ever spawned.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Fake Process infrastructure (mirrors onnx_direct_ml_candidate_test.dart)
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

/// Real recognition-result line as emitted by `sherpa-onnx-offline`.
const _resultJson =
    '{"text":" Guten Tag, das ist ein Test.","timestamps":[],"tokens":[" Guten"," Tag"]}';
const _expectedTranscript = 'Guten Tag, das ist ein Test.';

/// Creates a bundle directory with dummy encoder/decoder/tokens files.
Directory _bundleDir({bool int8 = true}) {
  final dir = Directory.systemTemp.createTempSync('sherpa-bundle-');
  final suffix = int8 ? '.int8.onnx' : '.onnx';
  File(p.join(dir.path, 'base-encoder$suffix')).writeAsStringSync('enc');
  File(p.join(dir.path, 'base-decoder$suffix')).writeAsStringSync('dec');
  File(p.join(dir.path, 'base-tokens.txt')).writeAsStringSync('<blank> 0');
  return dir;
}

ProbeContext _ctx(String modelDir) => ProbeContext(
  referenceWavPath: '/fake/ref.wav',
  modelPath: modelDir,
  workDir: Directory.systemTemp.path,
  language: 'de',
  timeout: const Duration(seconds: 30),
);

void main() {
  // -------------------------------------------------------------------------
  // Parser
  // -------------------------------------------------------------------------
  group('parseSherpaOnnxTranscript', () {
    test('extracts the "text" field from the JSON result line', () {
      final out = ['/tmp/live-0.wav', _resultJson, '----', 'num threads: 4'];
      expect(parseSherpaOnnxTranscript(out), equals(_expectedTranscript));
    });

    test('ignores non-JSON log lines', () {
      expect(parseSherpaOnnxTranscript(['Started', 'Done!']), isEmpty);
    });

    test('empty stdout → empty string', () {
      expect(parseSherpaOnnxTranscript(const []), isEmpty);
    });

    test('picks the last JSON result when several are present', () {
      final out = [
        '{"text":" Erster Clip.","tokens":[]}',
        '{"text":" Zweiter Clip.","tokens":[]}',
      ];
      expect(parseSherpaOnnxTranscript(out), equals('Zweiter Clip.'));
    });
  });

  // -------------------------------------------------------------------------
  // Bundle-file resolution
  // -------------------------------------------------------------------------
  group('resolveSherpaModelFiles', () {
    test('resolves encoder/decoder/tokens inside a bundle directory', () {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = resolveSherpaModelFiles(dir.path);
      expect(files, isNotNull);
      expect(p.basename(files!.encoder), 'base-encoder.int8.onnx');
      expect(p.basename(files.decoder), 'base-decoder.int8.onnx');
      expect(p.basename(files.tokens), 'base-tokens.txt');
    });

    test('prefers the int8 variant over full precision', () {
      final dir = Directory.systemTemp.createTempSync('sherpa-mix-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'base-encoder.onnx')).writeAsStringSync('full');
      File(
        p.join(dir.path, 'base-encoder.int8.onnx'),
      ).writeAsStringSync('int8');
      File(p.join(dir.path, 'base-decoder.int8.onnx')).writeAsStringSync('dec');
      File(p.join(dir.path, 'base-tokens.txt')).writeAsStringSync('t');
      final files = resolveSherpaModelFiles(dir.path);
      expect(p.basename(files!.encoder), 'base-encoder.int8.onnx');
    });

    test('missing directory → null', () {
      expect(resolveSherpaModelFiles('/definitely/missing'), isNull);
    });

    test('incomplete bundle (no tokens) → null', () {
      final dir = Directory.systemTemp.createTempSync('sherpa-partial-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'base-encoder.int8.onnx')).writeAsStringSync('e');
      File(p.join(dir.path, 'base-decoder.int8.onnx')).writeAsStringSync('d');
      expect(resolveSherpaModelFiles(dir.path), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Subprocess pipeline
  // -------------------------------------------------------------------------
  group('SherpaOnnxCandidate', () {
    test('exit 0 + JSON result → Outcome.ok with transcript + WER', () async {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: 'sherpa-onnx-offline',
        runner: _fastRunner(
          _fakeLauncher(
            exitCode: 0,
            stdoutLines: ['/tmp/ref.wav', _resultJson],
          ),
        ),
        referenceTranscript: _expectedTranscript,
      );
      final result = await candidate.run(_ctx(dir.path));
      expect(result.outcome, Outcome.ok);
      expect(result.transcribedText, _expectedTranscript);
      expect(result.wer, closeTo(0.0, 0.01));
      expect(result.backend, 'onnx-cpu');
    });

    test('passes whisper flags with = and the model files', () async {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      List<String>? args;
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: 'sherpa-onnx-offline',
        runner: _fastRunner(
          _fakeLauncher(
            exitCode: 0,
            stdoutLines: [_resultJson],
            onArgs: (a) => args = a,
          ),
        ),
      );
      await candidate.run(_ctx(dir.path));
      expect(args, isNotNull);
      expect(args, contains('--whisper-language=de'));
      expect(args, contains('--whisper-task=transcribe'));
      expect(args, contains('--provider=cpu'));
      expect(
        args!.any(
          (a) => a.startsWith('--whisper-encoder=') && a.contains('encoder'),
        ),
        isTrue,
      );
      expect(
        args!.any((a) => a.startsWith('--tokens=') && a.contains('tokens')),
        isTrue,
      );
      // The wav path is the last positional argument.
      expect(args!.last, '/fake/ref.wav');
    });

    test('cuda provider is passed via --provider=cuda', () async {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      List<String>? args;
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cuda',
        binaryName: 'sherpa-onnx-offline',
        backend: 'cuda',
        provider: 'cuda',
        runner: _fastRunner(
          _fakeLauncher(
            exitCode: 0,
            stdoutLines: [_resultJson],
            onArgs: (a) => args = a,
          ),
        ),
      );
      await candidate.run(_ctx(dir.path));
      expect(args, contains('--provider=cuda'));
    });

    test('missing model files → Outcome.skipped', () async {
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: 'sherpa-onnx-offline',
        runner: _fastRunner(_fakeLauncher(exitCode: 0)),
      );
      final result = await candidate.run(_ctx('/definitely/missing'));
      expect(result.outcome, Outcome.skipped);
      expect(result.errorDetail, contains('Modelldateien'));
    });

    test('missing binary → Outcome.skipped', () async {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: 'sherpa-onnx-offline',
        runner: _fastRunner(_missingBinaryLauncher()),
      );
      final result = await candidate.run(_ctx(dir.path));
      expect(result.outcome, Outcome.skipped);
      expect(result.errorDetail, contains('nicht gefunden'));
    });

    test('non-zero exit → Outcome.crashed with exit code', () async {
      final dir = _bundleDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final candidate = SherpaOnnxCandidate(
        id: 'sherpa-onnx-cpu',
        binaryName: 'sherpa-onnx-offline',
        runner: _fastRunner(
          _fakeLauncher(exitCode: 1, stderrLines: ['fatal: bad model']),
        ),
      );
      final result = await candidate.run(_ctx(dir.path));
      expect(result.outcome, Outcome.crashed);
      expect(result.exitCode, 1);
      expect(result.stderrTail, contains('bad model'));
    });
  });
}
