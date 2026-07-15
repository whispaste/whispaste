/// In-App-Diagnostik report builder — delegates to the pure-Dart core.
///
/// This file is the app-layer adapter. The formatter ([formatDiagnosticsReport])
/// and its data types live in `package:whispaste_diagnostics`. This file
/// re-exports those symbols and adds the app-side gather orchestration:
/// live Riverpod/app state (sttServerState, sttErrorMessage).
library;

import 'dart:io';

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
  String? sttServerState,
  String? sttErrorMessage,

  /// The compute backend the engine actually loaded (Issue 04). Supplied by
  /// the caller (`about_page.dart`, which reads `whisperEngineProvider`) —
  /// never re-derived from the retired server-binary marker.
  String? backend,

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
  final vcPresent = Platform.isWindows
      ? hw.vcRuntimeDllsPresent(sttDirPath)
      : null;

  return core.formatDiagnosticsReport(
    version: appVersion,
    variant: core.installVariantLabel(),
    osVersion: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    dartVersion: Platform.version,
    locale: Platform.localeName,
    executablePath: Platform.resolvedExecutable,
    serverPath: serverPath,
    serverExists: serverExists,
    backend: backend,
    loadedModel: loadedModel,
    cpuFallbackActive: cpuFallbackActive,
    sttServerState: sttServerState,
    sttErrorMessage: sttErrorMessage,
    sttFiles: sttFiles,
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
