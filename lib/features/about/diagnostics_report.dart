/// In-App-Diagnostik report builder — delegates to the pure-Dart core.
///
/// This file is the app-layer adapter. The formatter ([formatDiagnosticsReport])
/// and its data types live in `package:whispaste_diagnostics`. This file
/// re-exports those symbols and adds the app-side gather orchestration:
/// live Riverpod/app state (sttServerState, sttErrorMessage) and the
/// model-load probe (which spawns a subprocess and stays app-side).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as core;

import '../../core/app_info.dart';
import '../../core/logging/app_logger.dart';
import '../../services/hardware_info_service.dart' as hw;
import '../../services/path_service.dart' as paths;
import 'model_load_probe.dart';

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
  String? sttServerState,
  String? sttErrorMessage,
  bool runModelProbe = true,
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

  String? backend;
  try {
    backend = hw.readServerBinaryInfo(sttDirPath)?['backend'] as String?;
  } on Object {
    backend = null;
  }

  final sttFiles = hw.listServerDirFiles(sttDirPath);
  final vcPresent = Platform.isWindows
      ? hw.vcRuntimeDllsPresent(sttDirPath)
      : null;

  // ModelLoadProbeResult is now from the core (re-exported through
  // model_load_probe.dart), so no type conversion is needed.
  ModelLoadProbeResult? probe;
  if (runModelProbe) {
    try {
      probe = await runModelLoadProbe(
        serverPath: serverPath,
        modelPath: core.findInstalledModelPath(sttDirPath),
      );
    } on Object catch (e) {
      probe = ModelLoadProbeResult(
        ran: false,
        skipReason: 'Ladetest fehlgeschlagen: $e',
      );
    }
  }

  return core.formatDiagnosticsReport(
    version: appVersion,
    variant: core.installVariantLabel(),
    osVersion: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    dartVersion: Platform.version,
    locale: Platform.localeName,
    executablePath: Platform.resolvedExecutable,
    serverPath: serverPath,
    serverExists: serverExists,
    serverBackend: backend,
    sttServerState: sttServerState,
    sttErrorMessage: sttErrorMessage,
    sttFiles: sttFiles,
    modelLoadProbe: probe,
    vcRuntimePresent: vcPresent,
    gpu: gpu,
    logTail: _readAppLogTail(logTailLines),
  );
}

// ---------------------------------------------------------------------------
// Log-tail helper
// ---------------------------------------------------------------------------

/// Reads the last [n] lines of the current log file.
///
/// Uses the live log-file path from [AppLogger] when available, falling back
/// to the conventional path in AppData.
List<String> _readAppLogTail(int n) {
  try {
    final path =
        logFilePath ?? p.join(paths.appDataDir(), 'logs', 'whispaste.log');
    final f = File(path);
    if (!f.existsSync()) return const <String>[];
    final lines = f.readAsLinesSync();
    if (lines.length <= n) return lines;
    return lines.sublist(lines.length - n);
  } on Object {
    return const <String>[];
  }
}
