/// Manages the whisper-server subprocess lifecycle.
library;

import 'dart:async';
import 'dart:io';

import '../process_runner.dart';

/// Manages the whisper-server subprocess via an injectable [ProcessRunner].
///
/// Responsibilities:
/// - Start/stop the subprocess.
/// - Track whether the process is currently running.
///
/// Health-polling and idle-timer concerns live in separate modules.
class LocalSttServer {
  LocalSttServer({required this._processRunner});

  final ProcessRunner _processRunner;
  Process? _process;
  int? _port;

  /// Whether the server subprocess is currently running.
  bool get isRunning => _process != null;

  /// The port the server is listening on (null if not running).
  int? get port => _port;

  /// The process object (null if not running). Exposed for exit-code monitoring.
  Process? get process => _process;

  /// Starts the whisper-server subprocess.
  ///
  /// [modelPath] — absolute path to the GGML model file.
  /// [port]      — the TCP port the server should bind.
  /// [language]  — optional language hint (e.g. `'de'`).
  /// [useGpu]    — whether to enable GPU acceleration.
  ///
  /// Throws [ProcessException] if the executable cannot be started.
  Future<void> start({
    required String executablePath,
    required String modelPath,
    required int port,
    String? language,
    bool useGpu = true,
  }) async {
    final threads = _threadCount(useGpu);
    final args = _buildArgs(
      modelPath: modelPath,
      port: port,
      threads: threads,
      useGpu: useGpu,
      language: language,
    );

    // On macOS strip the quarantine extended attribute so the binary runs.
    if (Platform.isMacOS) {
      await Process.run('xattr', [
        '-d',
        'com.apple.quarantine',
        executablePath,
      ]);
    }

    // Working directory = the binary's own folder so the variants that ship
    // sibling ggml/BLAS DLLs resolve them at runtime. NOTE: this is not the
    // FLUTTER_WHISPASTE-A0 fix — that STATUS_DLL_NOT_FOUND is a missing *system*
    // loader (vulkan-1.dll) for the GPU build, handled by the pre-launch
    // dependency gate in SttServerStateNotifier._start.
    _process = await _processRunner.start(
      executablePath,
      args,
      workingDirectory: File(executablePath).parent.path,
    );
    _port = port;
  }

  /// Kills the subprocess (if running) and clears the process reference.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    _port = null;

    if (proc != null) {
      try {
        proc.kill();
        await proc.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => -1,
        );
      } on ProcessException {
        // Already exited — fine.
      }
    }
  }

  /// Clears the process reference without waiting for exit.
  ///
  /// Use this when the exit has already been detected via [process.exitCode].
  void clearProcess() {
    _process = null;
    _port = null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<String> _buildArgs({
    required String modelPath,
    required int port,
    required int threads,
    required bool useGpu,
    String? language,
  }) {
    final args = <String>[
      '--model',
      modelPath,
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '--threads',
      '$threads',
      '--no-timestamps',
      '--entropy-thold',
      '2.6',
      '--logprob-thold',
      '-1.0',
    ];

    if (!useGpu) {
      args.add('--no-gpu');
    }

    if (language != null && language.isNotEmpty && language != 'auto') {
      args.addAll(['--language', language]);
    }

    return args;
  }

  int _threadCount(bool useGpu) {
    final cores = Platform.numberOfProcessors;
    if (useGpu) {
      final n = (cores * 3) ~/ 4;
      return n.clamp(2, 8);
    }
    return (cores - 1).clamp(2, 12);
  }
}
