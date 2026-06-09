/// A real, cross-platform whisper-server model-load smoke test for the in-app
/// diagnostics dump. Unlike listing metadata, this actually launches the
/// bundled server against the installed model with `--no-gpu` and observes
/// whether it loads or crashes — the only thing that reliably surfaces the
/// STATUS_DLL_NOT_FOUND (0xC0000135) start-blocker (FLUTTER_WHISPASTE-A0).
///
/// It mirrors what the app does at runtime: it launches with the server
/// binary's own directory as the working directory, so the probe validates the
/// *fixed* launch path rather than the old broken one.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/process_runner.dart';

/// Outcome of [runModelLoadProbe].
class ModelLoadProbeResult {
  const ModelLoadProbeResult({
    required this.ran,
    this.skipReason,
    this.loaded = false,
    this.exitCode,
    this.stderrTail = const <String>[],
  });

  /// Whether the probe actually launched the server. `false` means the binary
  /// or model could not be located; [skipReason] then explains why.
  final bool ran;

  /// Why the probe was skipped (only set when [ran] is `false`).
  final String? skipReason;

  /// `true` when the server started and stayed up for the probe window — i.e.
  /// it loaded the model without crashing.
  final bool loaded;

  /// Exit code when the server exited inside the window (null if it stayed up
  /// or the probe was skipped).
  final int? exitCode;

  /// Windows-style hex form of [exitCode] (e.g. `0xC0000135`), or null when
  /// there is no exit code. Masked to 32 bits so a signed crash code prints
  /// the same hex Windows reports.
  String? get exitCodeHex {
    final code = exitCode;
    if (code == null) return null;
    final masked = code & 0xFFFFFFFF;
    return '0x${masked.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  /// Last few stderr lines from the server (most useful on a crash).
  final List<String> stderrTail;
}

/// Launches [serverPath] against [modelPath] with `--no-gpu` and watches it for
/// [window]. If the process is still alive when the window elapses it is killed
/// and reported as [ModelLoadProbeResult.loaded]; if it exits earlier the exit
/// code and a stderr tail are captured.
///
/// [runner] is injectable for tests. [resolvePort] supplies the loopback port
/// (defaults to a real free-port lookup); tests pass a fixed value to stay off
/// the network.
Future<ModelLoadProbeResult> runModelLoadProbe({
  required String serverPath,
  required String? modelPath,
  ProcessRunner runner = const SystemProcessRunner(),
  Duration window = const Duration(seconds: 8),
  Future<int> Function()? resolvePort,
  int stderrTailLimit = 12,
}) async {
  if (!File(serverPath).existsSync()) {
    return const ModelLoadProbeResult(
      ran: false,
      skipReason: 'whisper-server-Binary nicht gefunden',
    );
  }
  if (modelPath == null || !File(modelPath).existsSync()) {
    return const ModelLoadProbeResult(
      ran: false,
      skipReason: 'kein installiertes Sprachmodell gefunden',
    );
  }

  final serverDir = File(serverPath).parent.path;
  final port = await (resolvePort ?? _findFreePort)();
  final args = <String>[
    '--model',
    modelPath,
    '--host',
    '127.0.0.1',
    '--port',
    '$port',
    '--threads',
    '4',
    '--no-timestamps',
    '--no-gpu',
  ];

  final Process proc;
  try {
    proc = await runner.start(serverPath, args, workingDirectory: serverDir);
  } on Object catch (e) {
    return ModelLoadProbeResult(
      ran: true,
      stderrTail: ['Start fehlgeschlagen: $e'],
    );
  }

  final stderrTail = <String>[];
  final stderrSub = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stderrTail.add(line);
        if (stderrTail.length > stderrTailLimit) stderrTail.removeAt(0);
      });

  int? exitCode;
  try {
    exitCode = await proc.exitCode.timeout(window);
  } on TimeoutException {
    // Still alive after the window → the model loaded. Tear it back down.
    proc.kill();
    exitCode = null;
  } finally {
    await stderrSub.cancel();
  }

  return ModelLoadProbeResult(
    ran: true,
    loaded: exitCode == null,
    exitCode: exitCode,
    stderrTail: List<String>.of(stderrTail),
  );
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
