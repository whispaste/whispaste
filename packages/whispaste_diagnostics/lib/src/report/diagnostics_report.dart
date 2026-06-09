/// Core diagnostics report building — pure-Dart, no Flutter.
///
/// Both the In-App-Diagnostik and the future WhisPaste-Diagnose CLI delegate
/// to the functions here. The In-App side additionally passes live Riverpod
/// state (sttServerState, sttErrorMessage) that the CLI obtains differently.
library;

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../analysis/dll_analysis.dart';
import '../analysis/verdict.dart';
import '../privacy/sanitizer.dart';
import '../probes/av_quarantine_probe.dart';
import '../probes/device_id_probe.dart';
import '../probes/gpu_info.dart';
import '../probes/hardware_probe.dart';
import '../probes/log_reader.dart';
import '../probes/path_service.dart';
import '../probes/permissions_probe.dart';
import '../probes/settings_probe.dart';

export '../probes/gpu_info.dart'
    show GpuInfo, GpuVendor, detectGpu, cachedGpuInfo;
export '../probes/path_service.dart'
    show
        appDataDir,
        sttDir,
        whisperServerPath,
        sttModelPath,
        resolveMsixFallbackDataRoot,
        resolveAllDataRoots,
        DataRootEntry,
        collectAllDataRoots;

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
///
/// [installRoots] — when non-empty, a multi-root summary section is rendered
/// after the header line listing every discovered data root with its variant
/// label. When empty or null, this section is omitted (single-root behaviour).
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
  bool fullLogs = false,
  String? deviceId,
  HardwareProbeResult? hardware,
  PermissionsProbeResult? permissions,
  AvQuarantineResult? avQuarantine,
  SettingsSnapshotResult? settings,
  bool settingsUnavailable = false,
  VerdictResult? verdict,
  List<DataRootEntry>? installRoots,
}) {
  final b = StringBuffer()
    ..writeln('WhisPaste v$version ($variant)')
    ..writeln('OS: $osVersion')
    ..writeln('Dart: $dartVersion')
    ..writeln('Locale: $locale')
    ..writeln('Programm: $executablePath');

  if (installRoots != null && installRoots.isNotEmpty) {
    b.writeln('Installations-Roots (${installRoots.length}):');
    for (final entry in installRoots) {
      b.writeln('  [${entry.label}]  ${entry.root}');
    }
  }

  if (deviceId != null) {
    b.writeln('Geräte-ID (Sentry): $deviceId');
  }

  if (gpu != null) {
    b.writeln(
      'GPU: ${gpu.name} (Hersteller ${gpu.vendor.name}, '
      'Backend ${gpu.optimalBackend}, CUDA ${gpu.cudaAvailable}, '
      'Vulkan ${gpu.vulkanAvailable})',
    );
  } else {
    b.writeln('GPU: (nicht ermittelt)');
  }

  if (hardware != null) {
    final hw = hardware;
    final ramTotal = hw.ramTotalMb;
    final ramFree = hw.ramFreeMb;
    final ramLine = StringBuffer('RAM: ');
    ramLine.write(ramTotal != null ? '$ramTotal MB gesamt' : '? MB gesamt');
    if (ramFree != null) ramLine.write(', $ramFree MB frei');
    if (hw.ramScarce) ramLine.write('  ⚠ knapp (< 7500 MB, §6.6)');
    b.writeln(ramLine.toString());

    if (hw.cpuModel != null) {
      final cores = hw.cpuCores;
      b.writeln('CPU: ${hw.cpuModel}${cores != null ? " ($cores Kerne)" : ""}');
    }
    if (hw.gpuVramMb != null) {
      b.writeln('GPU-VRAM: ${hw.gpuVramMb} MB');
    }
    if (hw.diskFreeMb != null) {
      b.writeln('Freier Speicher: ${hw.diskFreeMb} MB');
    }
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

  if (permissions != null) {
    final pm = permissions;
    b.writeln('Berechtigungen:');
    final anyKnown =
        pm.macosAccessibilityGranted != null ||
        pm.macosAppleEventsGranted != null ||
        pm.macosMicGranted != null ||
        pm.windowsMicAllowed != null;
    if (!anyKnown) {
      b.writeln(
        '  (nicht ermittelbar — der Standalone-Binary hat keinen Zugriff '
        'auf die TCC-Datenbank; in der App prüfbar)',
      );
    }
    if (pm.macosAccessibilityGranted != null) {
      final granted = pm.macosAccessibilityGranted! ? 'ja' : 'nein';
      final stale = pm.macosAccessibilityStale == true
          ? ' (⚠ stale TCC — §3.5: Toggle AN, aber AXIsProcessTrusted=false)'
          : '';
      b.writeln('  Accessibility: $granted$stale');
    }
    if (pm.macosAppleEventsGranted != null) {
      b.writeln(
        '  AppleEvents (Auto-Paste): '
        '${pm.macosAppleEventsGranted! ? "ja" : "nein"}',
      );
    }
    if (pm.macosMicGranted != null) {
      b.writeln('  Mikrofon (TCC): ${pm.macosMicGranted! ? "ja" : "nein"}');
    }
    if (pm.windowsMicAllowed != null) {
      b.writeln(
        '  Mikrofon (Windows-Datenschutz): '
        '${pm.windowsMicAllowed! ? "erlaubt" : "blockiert"}',
      );
    }
  }

  if (avQuarantine != null) {
    final av = avQuarantine;
    final flagged = av.quarantined == true || av.avThreatDetected == true;
    b.writeln('AV/Quarantäne: ${flagged ? "⚠ markiert" : "unauffällig"}');
    if (av.detail != null && av.detail!.isNotEmpty) {
      b.writeln('  Detail: ${av.detail}');
    }
  }

  if (settings != null) {
    final s = settings;
    b
      ..writeln('Einstellungen:')
      ..writeln('  Provider: ${s.sttProvider ?? "?"}')
      ..writeln('  Modell: ${s.sttModel ?? "?"}')
      ..writeln('  Backend: ${s.sttBackend ?? "?"}')
      ..writeln('  Hotkey: ${s.hotkey ?? "?"}')
      ..writeln('  After-Action: ${s.afterAction ?? "?"}')
      ..writeln('  API-Key: ${s.apiKeyRedacted ? "<redacted>" : "(keiner)"}');
  } else if (settingsUnavailable) {
    b.writeln(
      'Einstellungen: nicht im Standalone-Modus verfügbar '
      '(die In-App-Diagnostik liefert sie).',
    );
  }

  if (verdict != null) {
    final v = verdict;
    if (v.healthy) {
      b.writeln('Bewertung: keine Auffälligkeiten gefunden.');
    } else {
      b.writeln(
        'Bewertung: ${v.suspicions.length} Auffälligkeit(en) — '
        'primärer Fingerprint: ${v.primaryFingerprint}',
      );
      for (final s in v.suspicions) {
        b.writeln('  • [${s.fingerprint}] ${s.detail}');
      }
    }
  }

  if (logTail.isNotEmpty) {
    final header = fullLogs
        ? '--- Logzeilen (${logTail.length}) ---'
        : '--- letzte ${logTail.length} Logzeilen ---';
    b
      ..writeln(header)
      ..writeAll(logTail, '\n');
  }

  // §6.5 hard guardrail: the privacy sanitizer runs over the ENTIRE report
  // (path/username/AppData placeholders), not just per-probe fields — for both
  // the standalone WhisPaste-Diagnose CLI and the In-App-Diagnostik.
  return sanitizePaths(b.toString());
}

// ---------------------------------------------------------------------------
// Gatherer
// ---------------------------------------------------------------------------

/// Test seam: forces the platform branch of [gatherDiagnosticsReport]. The
/// MSIX-fallback logic is Windows-only in production, but the branch must be
/// exercisable cross-platform (the CI host is macOS/Linux). When non-null this
/// overrides [Platform.isWindows] inside the gatherer. Production leaves it null.
@visibleForTesting
bool? gatherIsWindowsOverride;

/// Test seam: injects the MSIX fallback resolver used by
/// [gatherDiagnosticsReport]. Production uses [resolveMsixFallbackDataRoot]
/// (which performs real disk I/O); tests pass a stub returning a fixed root or
/// null so the AC1/AC2/AC4 wiring is driven without touching the file system.
///
/// Slice 1 legacy seam — kept for backward compatibility. Slice 2 tests should
/// use [gatherAllDataRootsResolverOverride] instead.
@visibleForTesting
String? Function()? gatherMsixDataRootResolverOverride;

/// Test seam: injects the multi-root resolver used by [gatherDiagnosticsReport]
/// for Slice 2 (multi-root listing). When non-null, this takes precedence over
/// [gatherMsixDataRootResolverOverride]. Production uses [resolveAllDataRoots]
/// (real disk I/O). Tests pass a stub returning a deterministic list.
@visibleForTesting
List<DataRootEntry> Function()? gatherAllDataRootsResolverOverride;

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
  // On Windows, discover all WhisPaste data roots (EXE + every MSIX version).
  // The "primary" root is used for STT-file listing, server path and log path;
  // all roots are surfaced in the report via the installRoots section (Slice 2).
  final isWindows = gatherIsWindowsOverride ?? Platform.isWindows;

  // allRoots: all roots whose models/stt dir is present (EXE first, then MSIX).
  List<DataRootEntry> allRoots = const [];
  String? primaryMsixDataRoot; // first MSIX root (or null) — drives STT dir
  String? effectiveSttDirPath;

  if (isWindows) {
    // Resolve all roots via the appropriate seam.
    if (gatherAllDataRootsResolverOverride != null) {
      allRoots = gatherAllDataRootsResolverOverride!();
    } else if (gatherMsixDataRootResolverOverride != null) {
      // Slice 1 legacy seam: single-root resolver.  Wrap it as a list.
      // Only used when no explicit EXE STT dir exists (same logic as Slice 1).
      final regularSttDir = sttDir();
      final regularExists = Directory(regularSttDir).existsSync();
      if (!regularExists) {
        final single = gatherMsixDataRootResolverOverride!();
        if (single != null) {
          allRoots = [
            DataRootEntry(root: single, label: 'Microsoft Store / MSIX'),
          ];
        }
      }
    } else {
      // Production: use the real multi-root resolver.
      allRoots = resolveAllDataRoots();
    }

    // The primary root for STT-detail probes is the first MSIX root
    // (EXE root is already covered by the default sttDir path).
    // If the EXE root is present in allRoots we keep sttDir() as-is;
    // if not, we fall back to the first MSIX root.
    final exePresent = allRoots.any((e) => e.label == 'EXE-Installer');
    if (!exePresent) {
      final firstMsix = allRoots
          .where((e) => e.label == 'Microsoft Store / MSIX')
          .firstOrNull;
      if (firstMsix != null) {
        primaryMsixDataRoot = firstMsix.root;
        effectiveSttDirPath = p.join(primaryMsixDataRoot, 'models', 'stt');
      }
    }
  }

  final sttDirPath = effectiveSttDirPath ?? sttDir();

  GpuInfo? gpu;
  try {
    gpu = await detectGpu();
  } on Object {
    gpu = null;
  }

  // When the effective STT dir was overridden (MSIX fallback), compute the
  // server path from the effective dir directly instead of the global helper
  // (which would use the nominal, potentially empty, appDataDir).
  final serverPath = effectiveSttDirPath != null
      ? p.join(
          effectiveSttDirPath,
          Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
        )
      : whisperServerPath();
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

  // New probes (slices 2+3). Each is best-effort: a failure degrades that
  // section to null rather than aborting the whole report.
  HardwareProbeResult? hardware;
  try {
    hardware = await gatherHardwareProbe(gpuInfo: gpu);
  } on Object {
    hardware = null;
  }

  PermissionsProbeResult? permissions;
  try {
    permissions = await gatherPermissionsProbe();
  } on Object {
    permissions = null;
  }

  AvQuarantineResult? avQuarantine;
  try {
    avQuarantine = await gatherAvQuarantineProbe(serverPath);
  } on Object {
    avQuarantine = null;
  }

  String? device;
  try {
    device = deviceId();
  } on Object {
    device = null;
  }

  // When an MSIX data root was found, read the log from its logs/ sub-dir
  // unless the caller has already supplied an explicit path.
  final effectiveLogFilePath =
      logFilePath ??
      (primaryMsixDataRoot != null
          ? p.join(primaryMsixDataRoot, 'logs', 'whispaste.log')
          : null);

  List<String> logLines;
  try {
    logLines = readFullLog(logFilePath: effectiveLogFilePath).lines;
  } on Object {
    logLines = const <String>[];
  }

  // Derive the verdict from the gathered signals + DLL analysis.
  VerdictResult? verdict;
  try {
    final dllAnalysis = analyzeDllDeps(
      presentDlls: buildDllPresenceSet(sttFiles),
      backend: backend,
      windowsContext: Platform.isWindows,
    );
    verdict = buildVerdict(
      dllAnalysis: dllAnalysis,
      ramScarce: hardware?.ramScarce ?? false,
      avQuarantined:
          avQuarantine?.quarantined == true ||
          avQuarantine?.avThreatDetected == true,
      staleTcc: permissions?.macosAccessibilityStale == true,
      modelAbiMismatch: false,
      serverExitCode: modelLoadProbe?.exitCode,
      stderrSnippet: modelLoadProbe?.stderrTail.join('\n'),
    );
  } on Object {
    verdict = null;
  }

  // Determine the install-variant label for the header line.
  // - Any MSIX root found (no EXE root) → 'Microsoft Store / MSIX'
  // - Only EXE root → 'EXE-Installer'
  // - Both or neither → installVariantLabel() (host-executable detection)
  // installVariantLabel() detects MSIX by checking whether the current
  // executable lives inside WindowsApps — works for the packaged app but the
  // standalone Diagnose EXE is never in WindowsApps.
  final String variant;
  if (allRoots.isNotEmpty) {
    final hasExe = allRoots.any((e) => e.label == 'EXE-Installer');
    final hasMsix = allRoots.any((e) => e.label == 'Microsoft Store / MSIX');
    if (hasMsix && !hasExe) {
      variant = 'Microsoft Store / MSIX';
    } else if (hasExe && !hasMsix) {
      variant = 'EXE-Installer';
    } else {
      // Both present or unusual combination — fall back to host-label.
      variant = installVariantLabel();
    }
  } else {
    variant = installVariantLabel();
  }

  // Only pass installRoots when there are multiple roots (or at least one found
  // root that enriches the report with a Installations-Roots section).
  final installRootsForReport = allRoots.length > 1 ? allRoots : null;

  return formatDiagnosticsReport(
    version: _resolveVersion(),
    variant: variant,
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
    logTail: logLines,
    fullLogs: true,
    deviceId: device,
    hardware: hardware,
    permissions: permissions,
    avQuarantine: avQuarantine,
    // Standalone CLI has no access to the app's SharedPreferences; the
    // In-App-Diagnostik supplies the settings snapshot instead.
    settingsUnavailable: true,
    verdict: verdict,
    installRoots: installRootsForReport,
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
