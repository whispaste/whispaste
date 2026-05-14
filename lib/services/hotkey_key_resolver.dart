/// Key resolver helpers — single source of truth for hotkey label ↔
/// [LogicalKeyboardKey] and modifier conversions.
///
/// Extracted from [HotkeyService] so both the service and the recorder widget
/// share the same mapping table. Prevents silent fallback bugs caused by
/// diverging look-up tables.
library;

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

// ---------------------------------------------------------------------------
// Key resolution
// ---------------------------------------------------------------------------

/// Maps a stored key label (e.g. `'D'`, `'F1'`, `'←'`) to a
/// [LogicalKeyboardKey].
///
/// Accepted inputs (case-insensitive unless indicated):
/// - Single letter: `'A'`–`'Z'`
/// - Function keys: `'F1'`–`'F12'`
/// - Arrow keys: `'←'`/`'ARROWLEFT'`/`'LEFT'`,
///   `'↑'`/`'ARROWUP'`/`'UP'`,
///   `'↓'`/`'ARROWDOWN'`/`'DOWN'`,
///   `'→'`/`'ARROWRIGHT'`/`'RIGHT'`
/// - Named keys: `'SPACE'`, `'ENTER'`, `'TAB'`, `'ESCAPE'`/`'ESC'`,
///   `'BACKSPACE'`, `'DELETE'`, `'INSERT'`, `'HOME'`, `'END'`,
///   `'PAGEUP'`, `'PAGEDOWN'`
///
/// Throws [ArgumentError] if [label] is not a recognised key.
LogicalKeyboardKey resolveKey(String label) {
  final upper = label.toUpperCase().trim();

  // Arrow keys (symbol and word forms)
  switch (upper) {
    case '←':
    case 'ARROWLEFT':
    case 'LEFT':
      return LogicalKeyboardKey.arrowLeft;
    case '↑':
    case 'ARROWUP':
    case 'UP':
      return LogicalKeyboardKey.arrowUp;
    case '↓':
    case 'ARROWDOWN':
    case 'DOWN':
      return LogicalKeyboardKey.arrowDown;
    case '→':
    case 'ARROWRIGHT':
    case 'RIGHT':
      return LogicalKeyboardKey.arrowRight;
  }

  // Single letter A–Z
  if (upper.length == 1 &&
      upper.codeUnitAt(0) >= 65 &&
      upper.codeUnitAt(0) <= 90) {
    final offset = upper.codeUnitAt(0) - 65;
    return LogicalKeyboardKey(0x00000000061 + offset); // keyA = 0x61
  }

  // Function keys F1–F12
  final fnMatch = RegExp(r'^F(\d+)$').firstMatch(upper);
  if (fnMatch != null) {
    final n = int.parse(fnMatch.group(1)!);
    if (n >= 1 && n <= 12) {
      return LogicalKeyboardKey(0x00100000070 + n - 1); // f1..f12
    }
  }

  // Named keys
  final named = switch (upper) {
    'SPACE' => LogicalKeyboardKey.space,
    'ENTER' => LogicalKeyboardKey.enter,
    'TAB' => LogicalKeyboardKey.tab,
    'ESCAPE' || 'ESC' => LogicalKeyboardKey.escape,
    'BACKSPACE' => LogicalKeyboardKey.backspace,
    'DELETE' => LogicalKeyboardKey.delete,
    'INSERT' => LogicalKeyboardKey.insert,
    'HOME' => LogicalKeyboardKey.home,
    'END' => LogicalKeyboardKey.end,
    'PAGEUP' => LogicalKeyboardKey.pageUp,
    'PAGEDOWN' => LogicalKeyboardKey.pageDown,
    _ => null,
  };
  if (named != null) return named;

  throw ArgumentError.value(label, 'label', 'Unknown key label');
}

// ---------------------------------------------------------------------------
// Reverse mapping
// ---------------------------------------------------------------------------

/// Returns the storage/display label for a [LogicalKeyboardKey].
///
/// Arrow keys are returned as Unicode symbols (`'←'`, `'↑'`, `'↓'`, `'→'`)
/// to match the display format used by the hotkey recorder dialog.
///
/// Returns `null` for keys that have no known label in the resolver's table
/// (e.g. media keys, numpad keys).
String? labelForKey(LogicalKeyboardKey key) {
  // Arrow keys
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.arrowRight) return '→';

  // Named keys
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.insert) return 'Insert';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';

  // Function keys
  for (var n = 1; n <= 12; n++) {
    if (key == LogicalKeyboardKey(0x00100000070 + n - 1)) return 'F$n';
  }

  // Single letter A–Z
  final keyId = key.keyId;
  if (keyId >= 0x61 && keyId <= 0x7a) {
    return String.fromCharCode(keyId - 0x61 + 65); // A–Z upper
  }

  return null;
}

// ---------------------------------------------------------------------------
// Modifier serialization (storage format)
// ---------------------------------------------------------------------------

/// Serializes a set of held modifier keys to the canonical storage string.
///
/// Returns tokens in a deterministic order (`ctrl → shift → alt → meta`) so
/// roundtrips with [resolveModifiers] are stable. Left/Right variants are
/// treated as equivalent.
///
/// This is the **single source of truth** for the modifier storage format —
/// the recorder writes via this function and the registrar reads via
/// [resolveModifiers]. The two share their token vocabulary so display labels
/// (e.g. macOS `Option`, German `Strg`) never leak into persisted settings.
String serializeModifiers(Set<LogicalKeyboardKey> heldModifiers) {
  final parts = <String>[];
  if (heldModifiers.contains(LogicalKeyboardKey.controlLeft) ||
      heldModifiers.contains(LogicalKeyboardKey.controlRight)) {
    parts.add('ctrl');
  }
  if (heldModifiers.contains(LogicalKeyboardKey.shiftLeft) ||
      heldModifiers.contains(LogicalKeyboardKey.shiftRight)) {
    parts.add('shift');
  }
  if (heldModifiers.contains(LogicalKeyboardKey.altLeft) ||
      heldModifiers.contains(LogicalKeyboardKey.altRight)) {
    parts.add('alt');
  }
  if (heldModifiers.contains(LogicalKeyboardKey.metaLeft) ||
      heldModifiers.contains(LogicalKeyboardKey.metaRight)) {
    parts.add('meta');
  }
  return parts.join('+');
}

// ---------------------------------------------------------------------------
// Modifier resolution
// ---------------------------------------------------------------------------

/// Maps a stored modifier string (e.g. `'ctrl+shift'`) to a list of
/// [HotKeyModifier] values.
///
/// Unrecognised parts are silently skipped (e.g. the empty string `''` when
/// the user has no modifier set).
List<HotKeyModifier> resolveModifiers(String modifiers) {
  final parts = modifiers.toLowerCase().split('+');
  final result = <HotKeyModifier>[];
  for (final part in parts) {
    switch (part.trim()) {
      case 'ctrl' || 'control':
        result.add(HotKeyModifier.control);
      case 'shift':
        result.add(HotKeyModifier.shift);
      case 'alt':
        result.add(HotKeyModifier.alt);
      case 'meta' || 'win' || 'super' || 'cmd':
        result.add(HotKeyModifier.meta);
    }
  }
  return result;
}
