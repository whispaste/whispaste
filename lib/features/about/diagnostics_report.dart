/// Builds the in-app diagnostics block that the About page copies to the
/// clipboard. This is the lightweight, no-download counterpart to the
/// standalone `tools/whispaste-diagnose.ps1` tool: it surfaces the same
/// essentials (variant, GPU, Sprachdienst binary state, bundled DLL files,
/// VC++ runtime presence, recent log tail) so a user can paste them straight
/// into a bug report.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/app_info.dart';
import '../../core/logging/app_logger.dart';
import '../../services/hardware_info_service.dart' as hw;
import '../../services/path_service.dart' as paths;
import 'model_load_probe.dart';

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
  hw.GpuInfo? gpu,
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

  ModelLoadProbeResult? probe;
  if (runModelProbe) {
    try {
      probe = await runModelLoadProbe(
        serverPath: serverPath,
        modelPath: findInstalledModelPath(sttDirPath),
      );
    } on Object catch (e) {
      probe = ModelLoadProbeResult(
        ran: false,
        skipReason: 'Ladetest fehlgeschlagen: $e',
      );
    }
  }

  return formatDiagnosticsReport(
    version: appVersion,
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
    modelLoadProbe: probe,
    vcRuntimePresent: vcPresent,
    gpu: gpu,
    logTail: readLogTail(logTailLines),
  );
}

/// Finds the installed whisper model in [sttDir] — the largest `ggml-*.bin`
/// file, mirroring how the smoke harness picks the model. Returns null when no
/// model is present yet. Best-effort: any IO error degrades to null.
String? findInstalledModelPath(String sttDir) {
  try {
    final dir = Directory(sttDir);
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
/// (MSIX) build — which runs from `WindowsApps\Packages\…` — from the
/// standalone EXE installer build.
String installVariantLabel() {
  if (!Platform.isWindows) return Platform.operatingSystem;
  final exe = Platform.resolvedExecutable.toLowerCase();
  if (exe.contains(r'\windowsapps\') || exe.contains(r'\packages\')) {
    return 'Microsoft Store / MSIX';
  }
  return 'EXE-Installer';
}

/// Reads the last [n] lines of the current log file, or an empty list when it
/// is unavailable. Falls back to the conventional path when the logger has not
/// published one yet.
List<String> readLogTail(int n) {
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
