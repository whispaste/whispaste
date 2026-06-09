/// Core diagnostics report building — pure-Dart, no Flutter.
///
/// Both the In-App-Diagnostik and the future WhisPaste-Diagnose CLI delegate
/// to the functions here. The In-App side additionally passes live Riverpod
/// state (sttServerState, sttErrorMessage) that the CLI obtains differently.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../probes/gpu_info.dart';
import '../probes/path_service.dart';

export '../probes/gpu_info.dart'
    show GpuInfo, GpuVendor, detectGpu, cachedGpuInfo;
export '../probes/path_service.dart'
    show appDataDir, sttDir, whisperServerPath, sttModelPath;

// ---------------------------------------------------------------------------
// ModelLoadProbeResult — inline definition for the core
//
// The full model-load probe (launching whisper-server) lives in the app layer
// (`lib/features/about/model_load_probe.dart`) because it depends on
// `ProcessRunner` (an app-level abstraction). The core accepts only the
// result value type, not the runner.
// ---------------------------------------------------------------------------

/// Outcome of a model-load probe. Passed into [formatDiagnosticsReport] so
/// the formatter stays pure and testable without spawning processes.
class ModelLoadProbeResult {
  const ModelLoadProbeResult({
    required this.ran,
    this.skipReason,
    this.loaded = false,
    this.exitCode,
    this.stderrTail = const <String>[],
  });

  /// Whether the probe actually launched the server.
  final bool ran;

  /// Why the probe was skipped (only set when [ran] is `false`).
  final String? skipReason;

  /// `true` when the server stayed up for the probe window.
  final bool loaded;

  /// Exit code when the server exited inside the window.
  final int? exitCode;

  /// Windows-style hex form of [exitCode] (e.g. `0xC0000135`), or null.
  String? get exitCodeHex {
    final code = exitCode;
    if (code == null) return null;
    final masked = code & 0xFFFFFFFF;
    return '0x${masked.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  /// Last few stderr lines from the server (most useful on a crash).
  final List<String> stderrTail;
}

// ---------------------------------------------------------------------------
// Formatter
// ---------------------------------------------------------------------------

/// Formats the diagnostics block. Pure and synchronous so it is unit-testable;
/// the async filesystem/GPU gathering lives in [gatherDiagnosticsReport].
///
/// [vcRuntimePresent] is `null` on non-Windows platforms (the concept and the
/// STATUS_DLL_NOT_FOUND failure mode it guards are Windows-only).
String formatDiagnosticsReport({
  required String version,
  required String variant,
  required String osVersion,
  required String dartVersion,
  required String locale,
  required String executablePath,
  required String serverPath,
  required bool serverExists,
  String? serverBackend,
  String? sttServerState,
  String? sttErrorMessage,
  required List<String> sttFiles,
  bool? vcRuntimePresent,
  ModelLoadProbeResult? modelLoadProbe,
  GpuInfo? gpu,
  required List<String> logTail,
}) {
  final b = StringBuffer()
    ..writeln('WhisPaste v$version ($variant)')
    ..writeln('OS: $osVersion')
    ..writeln('Dart: $dartVersion')
    ..writeln('Locale: $locale')
    ..writeln('Programm: $executablePath');

  if (gpu != null) {
    b.writeln(
      'GPU: ${gpu.name} (Hersteller ${gpu.vendor.name}, '
      'Backend ${gpu.optimalBackend}, CUDA ${gpu.cudaAvailable}, '
      'Vulkan ${gpu.vulkanAvailable})',
    );
  } else {
    b.writeln('GPU: (nicht ermittelt)');
  }

  b
    ..writeln('Sprachdienst: $serverPath')
    ..writeln(
      '  vorhanden: ${serverExists ? "ja" : "nein"}'
      '${serverBackend != null ? "  backend: $serverBackend" : ""}',
    );

  if (sttServerState != null) {
    b.writeln('  Status: $sttServerState');
  }
  if (sttErrorMessage != null && sttErrorMessage.isNotEmpty) {
    b.writeln('  letzter Fehler: $sttErrorMessage');
  }

  if (vcRuntimePresent != null) {
    b.writeln('  VC++-Runtime vorhanden: ${vcRuntimePresent ? "ja" : "nein"}');
  }

  b.writeln(
    '  Sprachdienst-Dateien: '
    '${sttFiles.isEmpty ? "(keine)" : sttFiles.join(", ")}',
  );

  if (modelLoadProbe != null) {
    final probe = modelLoadProbe;
    if (!probe.ran) {
      b.writeln('Modell-Ladetest: übersprungen (${probe.skipReason})');
    } else if (probe.loaded) {
      b.writeln('Modell-Ladetest: OK — Server lädt das Modell.');
    } else {
      final hex = probe.exitCodeHex;
      b.writeln(
        'Modell-Ladetest: FEHLER — Server beendet mit Code '
        '${probe.exitCode}${hex != null ? " ($hex)" : ""}.',
      );
      if (probe.stderrTail.isNotEmpty) {
        b.writeln('  stderr:');
        for (final line in probe.stderrTail) {
          b.writeln('    $line');
        }
      }
    }
  }

  if (logTail.isNotEmpty) {
    b
      ..writeln('--- letzte ${logTail.length} Logzeilen ---')
      ..writeAll(logTail, '\n');
  }

  return b.toString();
}

// ---------------------------------------------------------------------------
// Gatherer
// ---------------------------------------------------------------------------

/// Gathers live environment data and returns the formatted diagnostics block.
/// Best-effort: any single probe failing degrades that line rather than
/// throwing, so the caller always gets *something* useful.
///
/// [logFilePath] — when provided, overrides the default log file location.
/// [modelLoadProbe] — pre-computed probe result (the app layer runs the
///   actual subprocess and passes the result here).
Future<String> gatherDiagnosticsReport({
  int logTailLines = 40,
  String? sttServerState,
  String? sttErrorMessage,
  ModelLoadProbeResult? modelLoadProbe,
  String? logFilePath,
}) async {
  final sttDirPath = sttDir();

  GpuInfo? gpu;
  try {
    gpu = await detectGpu();
  } on Object {
    gpu = null;
  }

  final serverPath = whisperServerPath();
  final serverExists = File(serverPath).existsSync();

  String? backend;
  try {
    backend = readServerBinaryInfo(sttDirPath)?['backend'] as String?;
  } on Object {
    backend = null;
  }

  final sttFiles = listServerDirFiles(sttDirPath);
  final vcPresent = Platform.isWindows
      ? vcRuntimeDllsPresent(sttDirPath)
      : null;

  return formatDiagnosticsReport(
    version: _resolveVersion(),
    variant: installVariantLabel(),
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
    modelLoadProbe: modelLoadProbe,
    vcRuntimePresent: vcPresent,
    gpu: gpu,
    logTail: readLogTail(logTailLines, logFilePath: logFilePath),
  );
}

/// Finds the installed whisper model in [sttDir] — the largest `ggml-*.bin`
/// file, mirroring how the smoke harness picks the model. Returns null when no
/// model is present yet. Best-effort: any IO error degrades to null.
String? findInstalledModelPath(String sttDirArg) {
  try {
    final dir = Directory(sttDirArg);
    if (!dir.existsSync()) return null;
    final bins =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  p.basename(f.path).startsWith('ggml-') &&
                  f.path.toLowerCase().endsWith('.bin'),
            )
            .toList()
          ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    return bins.isEmpty ? null : bins.first.path;
  } on Object {
    return null;
  }
}

/// Human-readable install-variant label. Distinguishes the Microsoft Store
/// (MSIX) build from the standalone EXE installer build.
String installVariantLabel() {
  if (!Platform.isWindows) return Platform.operatingSystem;
  final exe = Platform.resolvedExecutable.toLowerCase();
  if (exe.contains(r'\windowsapps\') || exe.contains(r'\packages\')) {
    return 'Microsoft Store / MSIX';
  }
  return 'EXE-Installer';
}

/// Reads the last [n] lines of the log file.
///
/// [logFilePath] — explicit path; when null, falls back to the conventional
/// WhisPaste log location.
List<String> readLogTail(int n, {String? logFilePath}) {
  try {
    final path = logFilePath ?? p.join(appDataDir(), 'logs', 'whispaste.log');
    final f = File(path);
    if (!f.existsSync()) return const <String>[];
    final lines = f.readAsLinesSync();
    if (lines.length <= n) return lines;
    return lines.sublist(lines.length - n);
  } on Object {
    return const <String>[];
  }
}

// ---------------------------------------------------------------------------
// Version resolution
// ---------------------------------------------------------------------------

/// Optional app version override — set by the app layer after [PackageInfo]
/// resolves, so the diagnostics report shows the correct version without
/// pulling in `package_info_plus` into the pure-Dart core.
String? _appVersionOverride;

/// Sets the app version string used by [gatherDiagnosticsReport].
///
/// Call once at app startup after `initAppInfo()` resolves.
void setAppVersion(String version) => _appVersionOverride = version;

String _resolveVersion() => _appVersionOverride ?? 'unknown';
