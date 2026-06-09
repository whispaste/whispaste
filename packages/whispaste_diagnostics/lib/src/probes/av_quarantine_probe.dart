/// AV / quarantine-status probe for the whisper-server binary.
///
/// Pure-Dart (no Flutter). Injectable seams allow tests to feed canned command
/// output without spawning real OS processes.
///
/// - macOS: checks Gatekeeper quarantine via `xattr -l`.
/// - Windows: checks Windows Defender reputation / quarantine via PowerShell
///   `MpCmdRun.exe -Scan` or `Get-MpThreatDetection`.
library;

import 'dart:io';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Quarantine / AV status of the whisper-server binary.
class AvQuarantineResult {
  const AvQuarantineResult({
    required this.binaryPath,
    required this.binaryExists,
    this.quarantined,
    this.avThreatDetected,
    this.detail,
  });

  /// Absolute path to the probed binary.
  final String binaryPath;

  /// Whether the binary file exists on disk.
  final bool binaryExists;

  /// macOS: `true` when the binary has a `com.apple.quarantine` xattr.
  /// `null` on non-macOS or when the check could not run.
  final bool? quarantined;

  /// Windows: `true` when Defender has a recorded threat for the path.
  /// `null` on non-Windows or when the check could not run.
  final bool? avThreatDetected;

  /// Human-readable detail string (e.g. quarantine URL or threat name).
  final String? detail;
}

// ---------------------------------------------------------------------------
// Injectable seam — command runner
// ---------------------------------------------------------------------------

/// Runs a command and returns its stdout, or null on failure.
typedef CommandRunner =
    Future<String?> Function(String executable, List<String> arguments);

Future<String?> _defaultCommandRunner(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
    ).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0 && result.stdout.toString().isEmpty) return null;
    return result.stdout.toString();
  } catch (_) {
    return null;
  }
}

CommandRunner _commandRunner = _defaultCommandRunner;

/// Overrides the command runner for tests.
@visibleForTesting
void setAvCommandRunnerForTesting(CommandRunner? runner) {
  _commandRunner = runner ?? _defaultCommandRunner;
}

// ---------------------------------------------------------------------------
// Parsing helpers (pure, exported for unit tests)
// ---------------------------------------------------------------------------

/// Parses `xattr -l <path>` stdout to determine if the file is quarantined.
///
/// Returns `true` when the output contains `com.apple.quarantine`.
@visibleForTesting
bool parseMacosQuarantined(String? output) {
  if (output == null || output.trim().isEmpty) return false;
  return output.contains('com.apple.quarantine');
}

/// Extracts the quarantine URL from `xattr -l` output, if present.
@visibleForTesting
String? parseMacosQuarantineDetail(String? output) {
  if (output == null) return null;
  final match = RegExp(r'com\.apple\.quarantine:\s*(.+)').firstMatch(output);
  return match?.group(1)?.trim();
}

/// Parses `Get-MpThreatDetection` PowerShell output to detect a threat
/// entry for the given [binaryPath].
///
/// Returns `(detected, threatName)` — `detected = true` when any threat entry
/// refers to [binaryPath].
@visibleForTesting
({bool detected, String? threatName}) parseWindowsThreat(
  String? output,
  String binaryPath,
) {
  if (output == null || output.trim().isEmpty) {
    return (detected: false, threatName: null);
  }
  final lower = output.toLowerCase();
  final binLower = binaryPath.toLowerCase();
  if (!lower.contains(binLower)) {
    return (detected: false, threatName: null);
  }
  // Try to extract a ThreatName field from the output.
  final nameMatch = RegExp(
    r'ThreatName\s*:\s*(.+)',
    caseSensitive: false,
  ).firstMatch(output);
  return (detected: true, threatName: nameMatch?.group(1)?.trim());
}

// ---------------------------------------------------------------------------
// Live probe
// ---------------------------------------------------------------------------

/// Probes the AV / quarantine status of [binaryPath].
///
/// - macOS: uses `xattr -l`.
/// - Windows: uses PowerShell `Get-MpThreatDetection`.
/// - Other platforms: returns a result with `quarantined = null`.
Future<AvQuarantineResult> gatherAvQuarantineProbe(String binaryPath) async {
  final exists = File(binaryPath).existsSync();

  if (!exists) {
    return AvQuarantineResult(binaryPath: binaryPath, binaryExists: false);
  }

  if (Platform.isMacOS) {
    final output = await _commandRunner('xattr', ['-l', binaryPath]);
    final quarantined = parseMacosQuarantined(output);
    final detail = quarantined ? parseMacosQuarantineDetail(output) : null;
    return AvQuarantineResult(
      binaryPath: binaryPath,
      binaryExists: true,
      quarantined: quarantined,
      detail: detail,
    );
  }

  if (Platform.isWindows) {
    final output = await _commandRunner('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Get-MpThreatDetection | Format-List',
    ]);
    final result = parseWindowsThreat(output, binaryPath);
    return AvQuarantineResult(
      binaryPath: binaryPath,
      binaryExists: true,
      avThreatDetected: result.detected,
      detail: result.threatName,
    );
  }

  // Linux or other — no AV/quarantine check implemented.
  return AvQuarantineResult(binaryPath: binaryPath, binaryExists: true);
}
