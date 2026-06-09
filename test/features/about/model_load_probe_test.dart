/// Unit tests for the in-app whisper-server model-load probe.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/about/model_load_probe.dart';
import 'package:whispaste/services/process_runner.dart';

class _FakeProcess implements Process {
  _FakeProcess({List<String> stderr = const [], int? exitWith}) {
    // Pre-buffer stderr + exit. A single-subscription StreamController buffers
    // events added before listen(), so the probe still receives them.
    scheduleMicrotask(() async {
      for (final line in stderr) {
        _stderrCtrl.add(utf8.encode('$line\n'));
      }
      await _stderrCtrl.close();
      if (exitWith != null && !_exit.isCompleted) _exit.complete(exitWith);
    });
  }

  final _stderrCtrl = StreamController<List<int>>();
  final _exit = Completer<int>();

  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-1);
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();
}

class _FakeRunner extends ProcessRunner {
  _FakeRunner(this.process);
  final _FakeProcess process;
  String? workingDirectory;
  List<String>? arguments;

  @override
  Future<Process> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    this.workingDirectory = workingDirectory;
    arguments = args;
    return process;
  }
}

void main() {
  late Directory tmp;
  late String serverPath;
  late String modelPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('probe_test');
    serverPath = '${tmp.path}/whisper-server';
    modelPath = '${tmp.path}/ggml-base.bin';
    File(serverPath).writeAsStringSync('binary');
    File(modelPath).writeAsStringSync('model');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('runModelLoadProbe', () {
    test('skips when the binary is missing', () async {
      final res = await runModelLoadProbe(
        serverPath: '${tmp.path}/does-not-exist',
        modelPath: modelPath,
      );
      expect(res.ran, isFalse);
      expect(res.skipReason, contains('Binary'));
    });

    test('skips when the model is missing', () async {
      final res = await runModelLoadProbe(
        serverPath: serverPath,
        modelPath: null,
      );
      expect(res.ran, isFalse);
      expect(res.skipReason, contains('Sprachmodell'));
    });

    test('reports a crash with its exit code, hex and stderr tail', () async {
      // 0xC0000135 = STATUS_DLL_NOT_FOUND (unsigned 3221225781).
      final proc = _FakeProcess(
        stderr: const ["whisper_init_from_file: failed to open 'model'"],
        exitWith: 3221225781,
      );
      final runner = _FakeRunner(proc);

      final res = await runModelLoadProbe(
        serverPath: serverPath,
        modelPath: modelPath,
        runner: runner,
        resolvePort: () async => 51234,
      );

      expect(res.ran, isTrue);
      expect(res.loaded, isFalse);
      expect(res.exitCode, 3221225781);
      expect(res.exitCodeHex, '0xC0000135');
      expect(res.stderrTail.last, contains('failed to open'));
      // Launches in the binary's own directory (the A0 fix).
      expect(runner.workingDirectory, tmp.path);
      expect(runner.arguments, contains('--no-gpu'));
    });

    test('reports loaded when the server stays up past the window', () async {
      final proc = _FakeProcess(); // never exits on its own
      final runner = _FakeRunner(proc);

      final res = await runModelLoadProbe(
        serverPath: serverPath,
        modelPath: modelPath,
        runner: runner,
        resolvePort: () async => 51235,
        window: const Duration(milliseconds: 50),
      );

      expect(res.ran, isTrue);
      expect(res.loaded, isTrue);
      expect(res.exitCode, isNull);
      expect(res.exitCodeHex, isNull);
    });
  });
}
