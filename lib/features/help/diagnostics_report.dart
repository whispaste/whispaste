/// In-App-Diagnostik report builder — delegates to the pure-Dart core.
///
/// This file is the app-layer adapter. The formatter ([formatDiagnosticsReport])
/// and its data types live in `package:whispaste_diagnostics`. This file
/// re-exports those symbols and adds the app-side gather orchestration:
/// live Riverpod/app state (sttServerState, sttErrorMessage).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as core;

import '../../core/app_info.dart';
import '../../core/logging/app_logger.dart';
import '../../services/hardware_info_service.dart' as hw;
import '../../services/path_service.dart' as paths;

// ---------------------------------------------------------------------------
// Re-exports — keep all existing callers unchanged
// ---------------------------------------------------------------------------

export 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show
        GpuInfo,
        GpuVendor,
        formatDiagnosticsReport,
        findInstalledModelPath,
        installVariantLabel,
        readLogTail,
        ModelLoadProbeResult;

// ---------------------------------------------------------------------------
// App-side gather (with live state + model-load probe)
// ---------------------------------------------------------------------------

/// Gathers live environment data and returns the formatted diagnostics block.
/// Best-effort: any single probe failing degrades that line rather than
/// throwing, so the button always produces *something* useful to paste.
Future<String> gatherDiagnosticsReport({
  int logTailLines = 40,

  /// The active on-device STT engine (`whisper` or `parakeet`). Supplied by
  /// the caller (`about_page.dart`, which reads `settings.onDeviceEngine`).
  String? engine,
  String? sttServerState,
  String? sttErrorMessage,

  /// The compute backend the engine actually loaded (Issue 04). Supplied by
  /// the caller (`about_page.dart`, which reads `whisperEngineProvider`) —
  /// never re-derived from the retired server-binary marker.
  String? backend,

  /// ISA features of the CPU backend variant the engine loaded
  /// (`WhisperEngineStatus.cpuFeatures`), supplied by the caller.
  String? cpuFeatures,

  /// The model currently loaded in the engine (`SttStatus.modelId`).
  String? loadedModel,

  /// Whether the engine degraded to CPU after a GPU crash this session
  /// (`SttStatus.cpuFallbackActive`, Issue 05's resilience chain).
  bool? cpuFallbackActive,
}) async {
  final sttDirPath = paths.sttDir();

  hw.GpuInfo? gpu;
  try {
    gpu = await hw.detectGpu();
  } on Object {
    gpu = null;
  }

  final serverPath = paths.whisperServerPath();
  final serverExists = File(serverPath).existsSync();

  final sttFiles = hw.listServerDirFiles(sttDirPath);
  final log = readAppLog();
  final vcPresent = defaultTargetPlatform == TargetPlatform.windows
      ? hw.vcRuntimeDllsPresent(sttDirPath)
      : null;

  return core.formatDiagnosticsReport(
    version: appVersion,
    variant: core.installVariantLabel(),
    osVersion: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    dartVersion: Platform.version,
    locale: Platform.localeName,
    executablePath: Platform.resolvedExecutable,
    engine: engine,
    serverPath: serverPath,
    serverExists: serverExists,
    backend: backend,
    cpuFeatures: cpuFeatures,
    loadedModel: loadedModel,
    cpuFallbackActive: cpuFallbackActive,
    sttServerState: sttServerState,
    sttErrorMessage: sttErrorMessage,
    sttFiles: sttFiles,
    vcRuntimePresent: vcPresent,
    gpu: gpu,
    logTail: log.sublist(math.max(0, log.length - logTailLines)),
    recordingWarnings: recordingWarningLines(log, skipLast: logTailLines),
  );
}

// ---------------------------------------------------------------------------
// Log-tail helper
// ---------------------------------------------------------------------------

/// Reads the last [n] lines of the current log file, sanitized like the CLI
/// log reader (sensitive lines dropped, paths shortened).
///
/// Uses the live log-file path from [AppLogger] when available, falling back
/// to the conventional path in AppData.
List<String> readAppLogTail(int n, {String? pathOverride}) {
  final lines = readAppLog(pathOverride: pathOverride);
  if (lines.length <= n) return lines;
  return lines.sublist(lines.length - n);
}

/// All lines of the current log file, sanitized like [readAppLogTail];
/// empty when the file cannot be read.
List<String> readAppLog({String? pathOverride}) {
  try {
    final path =
        pathOverride ??
        logFilePath ??
        p.join(paths.appDataDir(), 'logs', 'whispaste.log');
    return core.readFullLog(logFilePath: path, maxRotations: 0).lines;
  } on Object {
    return const <String>[];
  }
}

/// Warnings about the microphone that ended or rescued a recording: the
/// dead-mic guard and the silent reopen of a stalled stream (#1784).
final _recordingWarning = RegExp(
  r'\[(WARNING|SEVERE)\].*(dead[- ]mic|mic stalled|mic reopen|'
  r'recorder stopped unexpectedly)',
  caseSensitive: false,
);

/// Recording warnings of the running app session (since the last
/// `Log session started` line) that lie before the last [skipLast] lines,
/// which the report shows anyway (#1784). At most the newest [max]. The lines
/// are already sanitized and hold no dictated text: these log lines carry
/// only states, timings, levels and device names.
List<String> recordingWarningLines(
  List<String> lines, {
  int skipLast = 0,
  int max = 30,
}) {
  var from = 0;
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].contains('--- Log session started')) {
      from = i + 1;
      break;
    }
  }
  final to = math.max(from, lines.length - skipLast);
  final hits = [
    for (var i = from; i < to; i++)
      if (_recordingWarning.hasMatch(lines[i])) lines[i],
  ];
  return hits.length <= max ? hits : hits.sublist(hits.length - max);
}
