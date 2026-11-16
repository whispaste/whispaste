import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform;

/// Per-application exclusion for the clipboard history: content copied in a
/// listed app normally does not enter the history (already stored entries stay).
///
/// The identifier of the source app is platform specific and reported by the
/// native monitor as `sourceApp`:
///  * macOS: bundle identifier of the frontmost app when the change was noticed
///    (poll interval 0.3 s, so a very quick app switch can mislabel a copy)
///    (`com.1password.1password`).
///  * Windows: executable name of the clipboard owner process
///    (`1password.exe`).
///  * Linux: not reported. X11/Wayland expose no reliable copy source, so
///    there only the privacy markers (`x-kde-passwordManagerHint`) apply and
///    the list stays inert (see [clipboardSourceAppDetectable]).
///
/// Matching is case-insensitive on the whole identifier.

/// Whether [platform] can tell which app a copy came from.
bool clipboardSourceAppDetectable(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.windows;

const List<String> _macDefaults = [
  'com.1password.1password',
  'com.agilebits.onepassword7',
  'com.bitwarden.desktop',
  'org.keepassxc.keepassxc',
  'com.lastpass.lastpass',
  'com.dashlane.dashlanephonefinal',
  'com.apple.keychainaccess',
  'com.apple.passwords',
  'com.proton.pass.desktop',
  'com.enpass.enpass-mac',
];

const List<String> _windowsDefaults = [
  '1password.exe',
  'bitwarden.exe',
  'keepassxc.exe',
  'keepass.exe',
  'lastpass.exe',
  'dashlane.exe',
  'enpass.exe',
  'proton pass.exe',
  'nordpass.exe',
];

/// Pre-filled list for a fresh install: common password managers. Banking
/// apps are not listed by name (they run in the browser or under bank
/// specific names), the user adds them in the settings.
List<String> defaultClipboardExcludedApps(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.macOS => _macDefaults,
      TargetPlatform.windows => _windowsDefaults,
      _ => const [],
    };

String _normalize(String id) => id.trim().toLowerCase();

/// Parses the stored value. `null` (never edited) means the platform
/// defaults; anything unreadable falls back to them as well.
List<String> parseClipboardExcludedApps(String? raw, TargetPlatform platform) {
  if (raw == null) return defaultClipboardExcludedApps(platform);
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return defaultClipboardExcludedApps(platform);
  }
  if (decoded is! List) return defaultClipboardExcludedApps(platform);
  return normalizeClipboardExcludedApps(decoded.whereType<String>());
}

String encodeClipboardExcludedApps(List<String> apps) => jsonEncode(apps);

/// Trimmed, case-insensitively de-duplicated, empties dropped.
List<String> normalizeClipboardExcludedApps(Iterable<String> apps) {
  final seen = <String>{};
  final out = <String>[];
  for (final app in apps) {
    final trimmed = app.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(_normalize(trimmed))) out.add(trimmed);
  }
  return out;
}

/// True when content from [sourceApp] must not enter the history.
/// Unknown source (`null`/empty) is never excluded here; the privacy markers
/// are checked separately by `shouldExcludeForPrivacy`.
bool isClipboardSourceExcluded(String? sourceApp, List<String> excluded) {
  if (sourceApp == null) return false;
  final id = _normalize(sourceApp);
  if (id.isEmpty) return false;
  return excluded.any((e) => _normalize(e) == id);
}
