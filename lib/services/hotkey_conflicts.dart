/// Platform-specific list of known system-reserved hotkeys.
///
/// These are combinations that the OS typically captures before any app can
/// intercept them. Registering them as global hotkeys will silently fail or
/// behave unexpectedly for the user.
///
/// The list is intentionally conservative — it covers only widely-known,
/// broadly-applicable system shortcuts. The goal is to warn users proactively,
/// not to enforce policy.
library;

import 'dart:io';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A known system-reserved hotkey combination.
class ConflictEntry {
  const ConflictEntry({
    required this.modifiers,
    required this.key,
    this.note = '',
  });

  /// Modifier set in storage format, e.g. `'meta'` or `'ctrl+alt'`.
  ///
  /// Empty string means the shortcut requires no modifier (rare — e.g. PrintScreen).
  final String modifiers;

  /// Non-modifier key label matching [HotkeyRecorderDialog.keyLabel] output,
  /// e.g. `'Space'`, `'Tab'`, `'F4'`, `'L'`.
  final String key;

  /// Human-readable note about which system function owns this combo.
  final String note;

  @override
  String toString() => 'ConflictEntry($modifiers + $key)';
}

// ---------------------------------------------------------------------------
// Platform-gated conflict lists
// ---------------------------------------------------------------------------

/// System hotkeys reserved on macOS.
const _macConflicts = <ConflictEntry>[
  ConflictEntry(modifiers: 'meta', key: 'Space', note: 'Spotlight'),
  ConflictEntry(modifiers: 'meta', key: 'Tab', note: 'App Switcher'),
  ConflictEntry(modifiers: 'meta', key: 'Q', note: 'Quit App'),
  ConflictEntry(modifiers: 'meta', key: 'W', note: 'Close Window'),
  ConflictEntry(modifiers: 'meta', key: 'H', note: 'Hide App'),
  ConflictEntry(modifiers: 'meta', key: 'M', note: 'Minimize Window'),
  ConflictEntry(modifiers: 'meta', key: '`', note: 'Cycle Windows'),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '3',
    note: 'Screenshot (full screen)',
  ),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '4',
    note: 'Screenshot (selection)',
  ),
  ConflictEntry(
    modifiers: 'meta+shift',
    key: '5',
    note: 'Screenshot/Screen Recording',
  ),
  ConflictEntry(
    modifiers: 'ctrl+meta',
    key: 'Space',
    note: 'Emoji & Symbols picker',
  ),
  ConflictEntry(
    modifiers: 'meta+option',
    key: 'Esc',
    note: 'Force Quit dialog',
  ),
];

/// System hotkeys reserved on Windows.
const _windowsConflicts = <ConflictEntry>[
  ConflictEntry(modifiers: 'meta', key: 'L', note: 'Lock workstation'),
  ConflictEntry(modifiers: 'meta', key: 'D', note: 'Show/Hide Desktop'),
  ConflictEntry(modifiers: 'meta', key: 'E', note: 'File Explorer'),
  ConflictEntry(modifiers: 'meta', key: 'R', note: 'Run dialog'),
  ConflictEntry(modifiers: 'meta', key: 'I', note: 'Settings'),
  ConflictEntry(modifiers: 'meta', key: 'S', note: 'Search'),
  ConflictEntry(modifiers: 'meta', key: 'Tab', note: 'Task View'),
  ConflictEntry(modifiers: 'meta', key: 'Space', note: 'Input language switch'),
  ConflictEntry(modifiers: 'meta', key: '↑', note: 'Maximize window'),
  ConflictEntry(modifiers: 'meta', key: '↓', note: 'Minimize window'),
  ConflictEntry(modifiers: 'meta', key: '←', note: 'Snap window left'),
  ConflictEntry(modifiers: 'meta', key: '→', note: 'Snap window right'),
  ConflictEntry(modifiers: 'alt', key: 'F4', note: 'Close window'),
  ConflictEntry(modifiers: 'alt', key: 'Tab', note: 'App Switcher'),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'Delete',
    note: 'Security options / Task Manager',
  ),
  ConflictEntry(modifiers: 'ctrl+shift', key: 'Esc', note: 'Task Manager'),
];

/// System hotkeys reserved on Linux (covers common GNOME & KDE defaults).
const _linuxConflicts = <ConflictEntry>[
  ConflictEntry(modifiers: 'meta', key: 'L', note: 'Lock screen (GNOME/KDE)'),
  ConflictEntry(modifiers: 'alt', key: 'F4', note: 'Close window'),
  ConflictEntry(modifiers: 'alt', key: 'Tab', note: 'App Switcher'),
  ConflictEntry(modifiers: 'alt', key: 'F2', note: 'Run dialog (KDE)'),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'Delete',
    note: 'System logout/shutdown dialog',
  ),
  ConflictEntry(
    modifiers: 'ctrl+alt',
    key: 'T',
    note: 'Open terminal (GNOME/KDE default)',
  ),
  ConflictEntry(modifiers: 'ctrl+alt', key: 'L', note: 'Lock screen (GNOME)'),
  ConflictEntry(
    modifiers: 'meta',
    key: 'Space',
    note: 'Activity overview (KDE)',
  ),
];

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns the conflict list applicable to the current OS.
///
/// Never throws; returns an empty list on unsupported platforms (mobile/web).
List<ConflictEntry> get platformConflicts {
  if (Platform.isMacOS) return _macConflicts;
  if (Platform.isWindows) return _windowsConflicts;
  if (Platform.isLinux) return _linuxConflicts;
  return const [];
}

/// Returns true when [modifiers] + [key] match a known system-reserved
/// shortcut on the current platform.
///
/// Comparison is case-insensitive and order-independent for modifier tokens.
///
/// [modifiers] — storage string such as `'ctrl+shift'` or `'meta'`.
/// [key] — non-modifier key label from [HotkeyRecorderDialog.keyLabel],
///          e.g. `'Space'`, `'F4'`, `'D'`.
bool isSystemConflict(String modifiers, String key) {
  return findConflict(modifiers, key, conflicts: platformConflicts) != null;
}

/// Returns the matching [ConflictEntry] or `null` if no conflict is found.
///
/// Accepts an optional [conflicts] list for testing purposes; defaults to
/// [platformConflicts].
ConflictEntry? findConflict(
  String modifiers,
  String key, {
  List<ConflictEntry>? conflicts,
}) {
  final list = conflicts ?? platformConflicts;

  // Normalise: lower-case, sort modifier tokens so order doesn't matter.
  final normMods = _normalise(modifiers);
  final normKey = key.trim();

  for (final entry in list) {
    if (_normalise(entry.modifiers) == normMods &&
        entry.key.trim() == normKey) {
      return entry;
    }
  }
  return null;
}

/// Normalises a modifier string: lower-case, tokens sorted alphabetically.
String _normalise(String modifiers) {
  if (modifiers.isEmpty) return '';
  final tokens = modifiers.toLowerCase().split('+')..sort();
  return tokens.join('+');
}
