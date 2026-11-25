/// PII sanitization helpers — path/username/AppData placeholders and
/// secret/API-key drop patterns.
///
/// This is the single canonical source of sanitization logic used by both
/// the In-App-Diagnostik and the future standalone WhisPaste-Diagnose CLI.
library;

import 'dart:io';

// ---------------------------------------------------------------------------
// Sensitive data patterns — drop events that contain secrets or API keys
// ---------------------------------------------------------------------------

final List<RegExp> sensitivePatterns = [
  RegExp(
    r'''["']?(api[_-]?key|token|password|authorization)["']?\s*[:=]\s*['"]?[^\s'",}]+''',
    caseSensitive: false,
  ),
  RegExp(r'\bbearer\s+\S+', caseSensitive: false),
  RegExp(r'\bsk-[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  RegExp(r'\bgsk_[A-Za-z0-9][A-Za-z0-9_]{5,}\b'),
  RegExp(r'\bsk-ant-[A-Za-z0-9_]{8,}\b'),
  RegExp(r'\bAIza[0-9A-Za-z_]{10,}\b'),
];

/// Returns `true` when [s] contains a sensitive pattern (API key, token, …).
bool containsSensitiveData(String s) =>
    sensitivePatterns.any((p) => p.hasMatch(s));

/// Replaces sensitive substrings (API keys, tokens, passwords, …) in [s]
/// with `<redacted>`, keeping the surrounding message intact.
///
/// Unlike [containsSensitiveData] (used to drop whole lines when reading
/// existing logs), this is meant for use at write time so secrets never
/// reach disk in the first place.
String redactSensitive(String s) {
  var result = s;
  for (final pattern in sensitivePatterns) {
    result = result.replaceAll(pattern, '<redacted>');
  }
  return result;
}

/// Replaces user-specific path segments with placeholders.
///
/// Substitutions (applied in this order):
/// - `%USERPROFILE%` / `$HOME` → `<home>`
/// - `%APPDATA%` → `<appdata>`
/// - `%USERNAME%` / `$USER` → `<user>`
/// - Microsoft Store package folders → `<msix-package>`
String sanitizePaths(String s) {
  var result = s;
  final userProfile =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (userProfile != null && userProfile.isNotEmpty) {
    result = result.replaceAll(userProfile, '<home>');
  }
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    result = result.replaceAll(appData, '<appdata>');
  }
  final user = Platform.environment['USERNAME'] ?? Platform.environment['USER'];
  if (user != null && user.isNotEmpty) {
    result = result.replaceAll(user, '<user>');
  }
  return sanitizeMsixPackageNames(result);
}

/// `…\WindowsApps\<package full name>` (the installed Store app).
final _msixInstallDir = RegExp(
  r'([\\/]WindowsApps[\\/])[^\\/\s]+',
  caseSensitive: false,
);

/// `…\Packages\<package family name>` (the app's virtualized data folder):
/// a name, `_`, and the 13-character publisher id.
final _msixDataDir = RegExp(
  r'([\\/]Packages[\\/])[^\\/\s]+_[a-z0-9]{13}(?=[\\/\s]|$)',
  caseSensitive: false,
);

/// Replaces Microsoft Store package folder names with `<msix-package>`.
/// Their package identity starts with the publisher's account name
/// (`12345Publisher.App_1.2.3.0_x64__<publisher id>`), which a report sent with
/// feedback must not carry. The report names the install variant and version
/// separately, so nothing needed for support is lost.
String sanitizeMsixPackageNames(String s) => s
    .replaceAllMapped(_msixInstallDir, (m) => '${m[1]}<msix-package>')
    .replaceAllMapped(_msixDataDir, (m) => '${m[1]}<msix-package>');
