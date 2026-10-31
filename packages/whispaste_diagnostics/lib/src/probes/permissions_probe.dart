/// Permissions probe — macOS Accessibility/AppleEvents/Mic-TCC, Windows Mic.
///
/// Pure-Dart (no Flutter). Uses injectable seams for command output and
/// registry reads so tests can exercise all paths without OS calls.
library;

import 'dart:io';

import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// Snapshot of the permissions relevant to WhisPaste.
class PermissionsProbeResult {
  const PermissionsProbeResult({
    required this.macosAccessibilityGranted,
    required this.macosAccessibilityStale,
    required this.macosAppleEventsGranted,
    required this.macosAppleEventsStale,
    required this.macosMicGranted,
    required this.windowsMicAllowed,
  });

  /// `true` when macOS Accessibility (AXIsProcessTrusted) is granted.
  /// `null` on non-macOS.
  final bool? macosAccessibilityGranted;

  /// `true` when the TCC entry is toggled ON but `AXIsProcessTrusted` is
  /// `false` — the stale-TCC / Sequoia-ad-hoc-signed bug (§3.5).
  /// `null` on non-macOS.
  final bool? macosAccessibilityStale;

  /// `true` when macOS AppleEvents permission is granted.
  /// `null` on non-macOS.
  final bool? macosAppleEventsGranted;

  /// Stale-TCC for AppleEvents (toggle ON but runtime check fails).
  /// `null` on non-macOS.
  final bool? macosAppleEventsStale;

  /// `true` when macOS Microphone TCC is granted.
  /// `null` on non-macOS.
  final bool? macosMicGranted;

  /// `true` when Windows microphone privacy allows this app.
  /// `null` on non-Windows.
  final bool? windowsMicAllowed;
}

// ---------------------------------------------------------------------------
// macOS TCC database queries (injectable seam for tests)
// ---------------------------------------------------------------------------

/// Function that executes a sqlite3 query against a TCC database and returns
/// the raw stdout string, or throws on failure.
///
/// Signature mirrors `Process.run` stdout extraction, not full [ProcessResult].
typedef TccQueryRunner = Future<String?> Function(String dbPath, String sql);

/// Default production TCC query runner — uses `sqlite3` CLI.
Future<String?> _defaultTccRunner(String dbPath, String sql) async {
  try {
    final result = await Process.run('sqlite3', [
      dbPath,
      sql,
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return null;
    return result.stdout.toString();
  } catch (_) {
    return null;
  }
}

TccQueryRunner _tccRunner = _defaultTccRunner;

/// Overrides the TCC query runner for tests.
@visibleForTesting
void setTccRunnerForTesting(TccQueryRunner? runner) {
  _tccRunner = runner ?? _defaultTccRunner;
}

// ---------------------------------------------------------------------------
// macOS AXIsProcessTrusted check (injectable seam)
// ---------------------------------------------------------------------------

/// Returns `true` when `AXIsProcessTrusted` (checking without prompt) is
/// `true` for the current process.
///
/// Tested via `osascript` so the probe can run without importing any
/// macOS-specific native framework.
typedef AXTrustedChecker = Future<bool?> Function();

Future<bool?> _defaultAXTrustedChecker() async {
  try {
    final result = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to return '
          '(accessibility enabled)',
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim().toLowerCase() == 'true';
  } catch (_) {
    return null;
  }
}

AXTrustedChecker _axTrustedChecker = _defaultAXTrustedChecker;

/// Overrides the AX-trusted checker for tests.
@visibleForTesting
void setAXTrustedCheckerForTesting(AXTrustedChecker? checker) {
  _axTrustedChecker = checker ?? _defaultAXTrustedChecker;
}

// ---------------------------------------------------------------------------
// Windows registry reader (injectable seam)
// ---------------------------------------------------------------------------

/// Reads a Windows registry value and returns the raw string output, or null.
typedef RegistryReader = Future<String?> Function(String keyPath, String value);

Future<String?> _defaultRegistryReader(String keyPath, String value) async {
  try {
    final result = await Process.run('reg', [
      'query',
      keyPath,
      '/v',
      value,
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return null;
    return result.stdout.toString();
  } catch (_) {
    return null;
  }
}

RegistryReader _registryReader = _defaultRegistryReader;

/// Overrides the registry reader for tests.
@visibleForTesting
void setRegistryReaderForTesting(RegistryReader? reader) {
  _registryReader = reader ?? _defaultRegistryReader;
}

// ---------------------------------------------------------------------------
// Pure parsing helpers (exported for unit tests)
// ---------------------------------------------------------------------------

/// Path to the user TCC database on macOS.
@visibleForTesting
const String kUserTccDbPath =
    'Library/Application Support/com.apple.TCC/TCC.db';

/// TCC SQL query to check if a service has `auth_value = 2` (allowed).
@visibleForTesting
String tccAllowedQuery(String service) =>
    "SELECT auth_value FROM access WHERE service='$service' AND "
    "client='com.silvio.whispaste' LIMIT 1;";

/// Parses the raw sqlite3 stdout to determine if the TCC entry is `allowed`
/// (auth_value = 2).
///
/// Returns `null` when the output is empty or unparseable.
@visibleForTesting
bool? parseTccAllowed(String? output) {
  if (output == null) return null;
  final trimmed = output.trim();
  if (trimmed.isEmpty) return null;
  // sqlite3 prints the value on a line; auth_value 2 = allowed.
  return trimmed == '2';
}

/// Parses the raw `reg query` output for the Windows microphone privacy key.
///
/// The `Allow` DWORD value = 1 means the device-level mic is enabled.
@visibleForTesting
bool? parseWindowsMicAllowed(String? output) {
  if (output == null) return null;
  // `reg query` output: "    Allow    REG_DWORD    0x1"
  final match = RegExp(
    r'Allow\s+REG_DWORD\s+(0x[0-9a-fA-F]+|\d+)',
    caseSensitive: false,
  ).firstMatch(output);
  if (match == null) return null;
  final raw = match.group(1) ?? '';
  final value = raw.startsWith('0x')
      ? int.tryParse(raw.substring(2), radix: 16)
      : int.tryParse(raw);
  if (value == null) return null;
  return value == 1;
}

// ---------------------------------------------------------------------------
// Live probe
// ---------------------------------------------------------------------------

/// Gathers permission state from the running OS.
///
/// Injectable seams ([setTccRunnerForTesting], [setAXTrustedCheckerForTesting],
/// [setRegistryReaderForTesting]) are used in tests.
Future<PermissionsProbeResult> gatherPermissionsProbe() async {
  bool? macosAccessibilityGranted;
  bool? macosAccessibilityStale;
  bool? macosAppleEventsGranted;
  bool? macosAppleEventsStale;
  bool? macosMicGranted;
  bool? windowsMicAllowed;

  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? '';
    final tccDb = '$home/$kUserTccDbPath';

    // Accessibility TCC entry
    final axTccRaw = await _tccRunner(
      tccDb,
      tccAllowedQuery('kTCCServiceAccessibility'),
    );
    final axTccAllowed = parseTccAllowed(axTccRaw);

    // AXIsProcessTrusted runtime check
    final axTrusted = await _axTrustedChecker();

    macosAccessibilityGranted = axTrusted;
    // Stale = TCC says allowed but runtime says no.
    macosAccessibilityStale = axTccAllowed == true && axTrusted == false;

    // AppleEvents TCC entry
    final aeTccRaw = await _tccRunner(
      tccDb,
      tccAllowedQuery('kTCCServiceAppleEvents'),
    );
    macosAppleEventsGranted = parseTccAllowed(aeTccRaw);
    // No reliable runtime check for AppleEvents outside of actually sending
    // an event — we treat stale as "TCC says allowed but AX is stale".
    // (They share the same stale-TCC root cause per §3.5.)
    macosAppleEventsStale = axTccAllowed == true && axTrusted == false;

    // Microphone TCC entry
    final micTccRaw = await _tccRunner(
      tccDb,
      tccAllowedQuery('kTCCServiceMicrophone'),
    );
    macosMicGranted = parseTccAllowed(micTccRaw);
  } else if (Platform.isWindows) {
    const micKey =
        r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone';
    final raw = await _registryReader(micKey, 'Allow');
    windowsMicAllowed = parseWindowsMicAllowed(raw);
  }

  return PermissionsProbeResult(
    macosAccessibilityGranted: macosAccessibilityGranted,
    macosAccessibilityStale: macosAccessibilityStale,
    macosAppleEventsGranted: macosAppleEventsGranted,
    macosAppleEventsStale: macosAppleEventsStale,
    macosMicGranted: macosMicGranted,
    windowsMicAllowed: windowsMicAllowed,
  );
}
