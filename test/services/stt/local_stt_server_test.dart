/// Unit tests for LocalSttServer.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/process_runner.dart';
import 'package:whispaste/services/stt/local_stt_server.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeProcess implements Process {
  final _stdoutCtrl = StreamController<List<int>>();
  final _stderrCtrl = StreamController<List<int>>();
  final _exitCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;
  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
  @override
  Future<int> get exitCode => _exitCompleter.future;
  @override
  int get pid => 11111;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();

  Future<void> dispose() async {
    await _stdoutCtrl.close();
    await _stderrCtrl.close();
  }
}

class _FakeProcessRunner extends ProcessRunner {
  final _FakeProcess process;
  String? lastExecutable;
  List<String>? lastArguments;
  int callCount = 0;

  _FakeProcessRunner(this.process);

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    callCount++;
    lastExecutable = executable;
    lastArguments = arguments;
    return process;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LocalSttServer', () {
    test('isRunning is false before start()', () {
      final runner = _FakeProcessRunner(_FakeProcess());
      final server = LocalSttServer(processRunner: runner);
      expect(server.isRunning, isFalse);
      expect(server.port, isNull);
      expect(server.process, isNull);
    });

    test('start() calls ProcessRunner and sets isRunning = true', () async {
      final fakeProcess = _FakeProcess();
      addTearDown(() => fakeProcess.kill());
      final runner = _FakeProcessRunner(fakeProcess);
      final server = LocalSttServer(processRunner: runner);

      await server.start(
        executablePath: '/fake/whisper-server',
        modelPath: '/fake/model.bin',
        port: 9876,
      );

      expect(server.isRunning, isTrue);
      expect(server.port, 9876);
      expect(server.process, same(fakeProcess));
      expect(runner.callCount, 1);
      expect(runner.lastExecutable, '/fake/whisper-server');
    });

    test('start() passes --model and --port to ProcessRunner', () async {
      final fakeProcess = _FakeProcess();
      addTearDown(() => fakeProcess.kill());
      final runner = _FakeProcessRunner(fakeProcess);
      final server = LocalSttServer(processRunner: runner);

      await server.start(
        executablePath: '/fake/whisper-server',
        modelPath: '/models/tiny.bin',
        port: 7777,
      );

      final args = runner.lastArguments ?? [];
      expect(args, containsAll(['--model', '/models/tiny.bin']));
      expect(args, containsAll(['--port', '7777']));
    });

    test('start() adds --no-gpu when useGpu is false', () async {
      final fakeProcess = _FakeProcess();
      addTearDown(() => fakeProcess.kill());
      final runner = _FakeProcessRunner(fakeProcess);
      final server = LocalSttServer(processRunner: runner);

      await server.start(
        executablePath: '/fake/whisper-server',
        modelPath: '/models/tiny.bin',
        port: 7777,
        useGpu: false,
      );

      expect(runner.lastArguments, contains('--no-gpu'));
    });

    test('stop() clears isRunning and port', () async {
      final fakeProcess = _FakeProcess();
      final runner = _FakeProcessRunner(fakeProcess);
      final server = LocalSttServer(processRunner: runner);

      await server.start(
        executablePath: '/fake/whisper-server',
        modelPath: '/models/tiny.bin',
        port: 7777,
      );
      expect(server.isRunning, isTrue);

      await server.stop();

      expect(server.isRunning, isFalse);
      expect(server.port, isNull);
      expect(server.process, isNull);
    });

    test('clearProcess() clears without waiting for exit', () async {
      final fakeProcess = _FakeProcess();
      addTearDown(() => fakeProcess.kill());
      final runner = _FakeProcessRunner(fakeProcess);
      final server = LocalSttServer(processRunner: runner);

      await server.start(
        executablePath: '/fake/whisper-server',
        modelPath: '/models/tiny.bin',
        port: 7777,
      );

      server.clearProcess();

      expect(server.isRunning, isFalse);
      expect(server.port, isNull);
    });
  });
}
