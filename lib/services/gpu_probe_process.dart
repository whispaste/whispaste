/// Process side of the GPU probe (`stt/whisper/gpu_probe.dart`): spawns the
/// probe child and provides the process-wide probe service.
///
/// This lives outside `lib/services/stt/` on purpose. The MAS build may not
/// contain process spawns on the on-device STT path, and
/// `test/services/stt/mas_symbol_scan_test.dart` enforces that on the STT
/// sources. The probe never runs on macOS (`kGpuProbeSkippedOs`), so the
/// spawn here is only reachable on Windows and Linux.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import 'path_service.dart';
import 'stt/whisper/gpu_probe.dart';

/// Runs the real probe child (headless transcription of the probe WAV with
/// the GPU forced on, JSON report written to a file), killed after [timeout].
/// Never throws: a child that cannot be started is [GpuProbeStatus.unavailable].
Future<GpuProbeOutcome> runGpuProbeChild({
  required String modelId,
  required Duration timeout,
  String? executable,
  String? workDir,
}) async {
  final exe = executable ?? Platform.resolvedExecutable;
  final dir = Directory(workDir ?? p.join(appDataDir(), 'gpu-probe'));
  final wav = File(p.join(dir.path, 'probe-tone.wav'));
  final report = File(p.join(dir.path, 'probe-report.json'));
  try {
    dir.createSync(recursive: true);
    wav.writeAsBytesSync(gpuProbeWav());
    if (report.existsSync()) report.deleteSync();
  } on FileSystemException catch (e) {
    return GpuProbeOutcome.unavailable('probe files: $e');
  }

  final Process process;
  try {
    process = await Process.start(
      exe,
      [
        '--transcribe-file',
        wav.path,
        '--gpu',
        'enabled',
        '--model',
        modelId,
        '--json',
        '--out',
        report.path,
      ],
      environment: {...Platform.environment, kGpuProbeChildEnv: '1'},
    );
  } on Object catch (e) {
    return GpuProbeOutcome.unavailable('cannot start probe child: $e');
  }
  // Read stdout for the start line; drain stderr so a chatty child cannot
  // block on a full pipe.
  var reachedApp = false;
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.trim() == kGpuProbeStartedLine) reachedApp = true;
      }, onError: (Object _) {})
      .asFuture<void>();
  unawaited(process.stderr.drain<void>());

  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  // The pipe closes with the child; a late reader must not hang the probe.
  await stdoutDone.timeout(const Duration(seconds: 5), onTimeout: () {});
  String? backend;
  if (!timedOut && exitCode == 0 && report.existsSync()) {
    try {
      final json = jsonDecode(report.readAsStringSync());
      if (json is Map && json['backend'] is String) {
        backend = json['backend'] as String;
      }
    } on Object {
      backend = null;
    }
  }
  return classifyProbeRun(
    exitCode: timedOut ? null : exitCode,
    timedOut: timedOut,
    engineBackend: backend,
    reachedApp: reachedApp,
  );
}

/// The process-wide probe. Disabled in the probe child and under tests, so
/// neither spawns a child.
final gpuProbeServiceProvider = Provider<GpuProbeService>(
  (ref) => GpuProbeService(
    store: GpuProbeStore(File(p.join(appDataDir(), 'gpu_probe.json'))),
    run: runGpuProbeChild,
    appVersion: appVersion,
    osVersion: Platform.operatingSystemVersion,
    operatingSystem: Platform.operatingSystem,
    enabled:
        Platform.environment[kGpuProbeChildEnv] != '1' &&
        !Platform.environment.containsKey('FLUTTER_TEST'),
  ),
);
