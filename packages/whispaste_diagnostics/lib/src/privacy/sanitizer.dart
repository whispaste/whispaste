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

/// Replaces user-specific path segments with placeholders.
///
/// Substitutions (applied in this order):
/// - `%USERPROFILE%` / `$HOME` → `<home>`
/// - `%APPDATA%` → `<appdata>`
/// - `%USERNAME%` / `$USER` → `<user>`
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
  return result;
}
