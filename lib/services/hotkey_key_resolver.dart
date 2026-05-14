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
/// - Digit (top row, not numpad): `'0'`–`'9'`
/// - Function keys: `'F1'`–`'F12'`
/// - Arrow keys: `'←'`/`'ARROWLEFT'`/`'LEFT'`,
///   `'↑'`/`'ARROWUP'`/`'UP'`,
///   `'↓'`/`'ARROWDOWN'`/`'DOWN'`,
///   `'→'`/`'ARROWRIGHT'`/`'RIGHT'`
/// - Named keys: `'SPACE'`, `'ENTER'`, `'TAB'`, `'ESCAPE'`/`'ESC'`,
///   `'BACKSPACE'`, `'DELETE'`, `'INSERT'`, `'HOME'`, `'END'`,
///   `'PAGEUP'`, `'PAGEDOWN'`
/// - Punctuation keys (US-layout canonical token; physical position is
///   independent of the user's keyboard layout): `';'`, `"'"`, `` '`' ``,
///   `','`, `'-'`, `'.'`, `'/'`, `'='`, `'['`, `']'`, `'\\'`. These are the
///   storage tokens written by the recorder for keys whose `LogicalKeyboardKey`
///   has no canonical Flutter identifier (e.g. `Ö`, `Ä`, `Ü` on a DE layout —
///   physically the `;`, `'`, `[` positions). The display label may differ
///   from the storage token; see `HotkeySettings.hotkeyKeyDisplay`.
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

  // Single digit 0–9 (top row — deterministic KeyCodes cross-platform).
  // Numpad keys are intentionally out of scope (separate KeyCode space and
  // layout-collision concerns on some platforms).
  if (upper.length == 1 &&
      upper.codeUnitAt(0) >= 0x30 &&
      upper.codeUnitAt(0) <= 0x39) {
    final offset = upper.codeUnitAt(0) - 0x30;
    return LogicalKeyboardKey(0x00000000030 + offset); // digit0 = 0x30
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

  // Punctuation tokens (US-layout canonical). The `uni_platform` keymap that
  // hotkey_manager uses to translate Logical→Physical includes exactly these.
  // For non-Latin layouts the recorder stores the canonical token here while
  // displaying the user-visible character separately.
  final punctuation = _punctuationToken(label.trim());
  if (punctuation != null) return punctuation;

  throw ArgumentError.value(label, 'label', 'Unknown key label');
}

/// Storage tokens for the punctuation keys present in `uni_platform`'s
/// Logical↔Physical keymap. Index = display character (US-layout) stored in
/// settings; value = canonical [LogicalKeyboardKey].
const Map<String, LogicalKeyboardKey> _punctuationKeys = {
  ';': LogicalKeyboardKey.semicolon,
  "'": LogicalKeyboardKey.quote,
  '`': LogicalKeyboardKey.backquote,
  ',': LogicalKeyboardKey.comma,
  '-': LogicalKeyboardKey.minus,
  '.': LogicalKeyboardKey.period,
  '/': LogicalKeyboardKey.slash,
  '=': LogicalKeyboardKey.equal,
  '[': LogicalKeyboardKey.bracketLeft,
  ']': LogicalKeyboardKey.bracketRight,
  '\\': LogicalKeyboardKey.backslash,
};

LogicalKeyboardKey? _punctuationToken(String token) => _punctuationKeys[token];

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

  // Digit 0–9 (top row — keyId range 0x30..0x39).
  if (keyId >= 0x30 && keyId <= 0x39) {
    return String.fromCharCode(keyId);
  }

  // Punctuation keys whose physical position is in uni_platform's keymap.
  for (final entry in _punctuationKeys.entries) {
    if (entry.value == key) return entry.key;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Recordable-key validation
// ---------------------------------------------------------------------------

/// Whether [key] is a non-modifier key that the recorder may persist as a
/// hotkey binding.
///
/// Returns `true` for keys the [resolveKey] reader can later parse back from
/// storage, **plus** the small set of keys accepted without a modifier
/// (function keys, selected media keys) that don't appear in
/// [labelForKey]'s table.
///
/// This is the **single source of truth** that guards the recorder's
/// write path. If [isRecordableKey] returns `false`, the recorder must not
/// update its state — preventing the user from saving a key that the global
/// hotkey registrar would later reject with [ArgumentError]. The asymmetric
/// write/read pair prevents the bug class where the UI accepts a key
/// (e.g. `Ö`, `Ä`, `;`, `+`) that the resolver later cannot register.
bool isRecordableKey(LogicalKeyboardKey key) {
  // Anything labelForKey produces a string for is round-trippable through
  // resolveKey — letters, digits, F-keys, arrow keys, named keys, punctuation.
  if (labelForKey(key) != null) return true;

  // No-modifier whitelist members that don't have a labelForKey entry,
  // notably media keys. These are safe to bind without a modifier and
  // hotkey_manager knows how to register them.
  return _recordableNoLabelKeys.contains(key);
}

/// Maps a [KeyEvent] to the canonical [LogicalKeyboardKey] that should be
/// persisted as the storage key, or `null` if no recordable key can be
/// derived.
///
/// First tries [event.logicalKey] directly — fast path for the canonical
/// keys (A–Z, 0–9, F1–F12, arrows, named, punctuation on a US layout).
///
/// If the logical key is non-canonical (e.g. `Ö` = `LogicalKeyboardKey(0xF6)`
/// on a DE layout), falls back to the **physical position**: the same key
/// on a US layout would produce `LogicalKeyboardKey.semicolon`, which IS
/// recordable. This lets users bind layout-dependent keys (umlauts, accented
/// chars, layout-specific punctuation) — the registrar wires them to the
/// stable physical position, so the binding survives layout changes.
LogicalKeyboardKey? canonicalRecordableKey(KeyEvent event) {
  if (isRecordableKey(event.logicalKey)) {
    return event.logicalKey;
  }
  final mapped = _physicalToLogical[event.physicalKey];
  if (mapped != null && isRecordableKey(mapped)) {
    return mapped;
  }
  return null;
}

/// PhysicalKeyboardKey → canonical LogicalKeyboardKey for keys whose logical
/// representation may differ across keyboard layouts but whose physical
/// position is stable. Keys here must be recordable per [isRecordableKey] —
/// covers the punctuation keys plus the always-recordable Latin letter and
/// digit positions (used when a non-Latin layout reports a non-ASCII
/// logical key for the same physical position).
final Map<PhysicalKeyboardKey, LogicalKeyboardKey> _physicalToLogical = {
  PhysicalKeyboardKey.semicolon: LogicalKeyboardKey.semicolon,
  PhysicalKeyboardKey.quote: LogicalKeyboardKey.quote,
  PhysicalKeyboardKey.backquote: LogicalKeyboardKey.backquote,
  PhysicalKeyboardKey.comma: LogicalKeyboardKey.comma,
  PhysicalKeyboardKey.minus: LogicalKeyboardKey.minus,
  PhysicalKeyboardKey.period: LogicalKeyboardKey.period,
  PhysicalKeyboardKey.slash: LogicalKeyboardKey.slash,
  PhysicalKeyboardKey.equal: LogicalKeyboardKey.equal,
  PhysicalKeyboardKey.bracketLeft: LogicalKeyboardKey.bracketLeft,
  PhysicalKeyboardKey.bracketRight: LogicalKeyboardKey.bracketRight,
  PhysicalKeyboardKey.backslash: LogicalKeyboardKey.backslash,
  PhysicalKeyboardKey.keyA: LogicalKeyboardKey.keyA,
  PhysicalKeyboardKey.keyB: LogicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyC: LogicalKeyboardKey.keyC,
  PhysicalKeyboardKey.keyD: LogicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE: LogicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF: LogicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG: LogicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH: LogicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyI: LogicalKeyboardKey.keyI,
  PhysicalKeyboardKey.keyJ: LogicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK: LogicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL: LogicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyM: LogicalKeyboardKey.keyM,
  PhysicalKeyboardKey.keyN: LogicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyO: LogicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP: LogicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyQ: LogicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyR: LogicalKeyboardKey.keyR,
  PhysicalKeyboardKey.keyS: LogicalKeyboardKey.keyS,
  PhysicalKeyboardKey.keyT: LogicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU: LogicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV: LogicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW: LogicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyX: LogicalKeyboardKey.keyX,
  PhysicalKeyboardKey.keyY: LogicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ: LogicalKeyboardKey.keyZ,
  PhysicalKeyboardKey.digit0: LogicalKeyboardKey.digit0,
  PhysicalKeyboardKey.digit1: LogicalKeyboardKey.digit1,
  PhysicalKeyboardKey.digit2: LogicalKeyboardKey.digit2,
  PhysicalKeyboardKey.digit3: LogicalKeyboardKey.digit3,
  PhysicalKeyboardKey.digit4: LogicalKeyboardKey.digit4,
  PhysicalKeyboardKey.digit5: LogicalKeyboardKey.digit5,
  PhysicalKeyboardKey.digit6: LogicalKeyboardKey.digit6,
  PhysicalKeyboardKey.digit7: LogicalKeyboardKey.digit7,
  PhysicalKeyboardKey.digit8: LogicalKeyboardKey.digit8,
  PhysicalKeyboardKey.digit9: LogicalKeyboardKey.digit9,
};

/// Keys that are recordable but whose canonical [LogicalKeyboardKey] instance
/// does not match the F-key keyId table used inside [resolveKey]/[labelForKey]
/// (Flutter assigns F1=0x00100000801 etc., while the resolver currently
/// indexes F-keys via a different magic offset — see [resolveKey]). These
/// canonical instances must still pass the recordability gate so the
/// recorder accepts F1–F12 and the media keys it whitelists as no-modifier
/// keys.
final Set<LogicalKeyboardKey> _recordableNoLabelKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaStop,
  LogicalKeyboardKey.audioVolumeMute,
};

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
      // Canonical storage tokens produced by serializeModifiers.
      case 'ctrl' || 'control':
        result.add(HotKeyModifier.control);
      case 'shift':
        result.add(HotKeyModifier.shift);
      case 'alt':
        result.add(HotKeyModifier.alt);
      case 'meta' || 'win' || 'super' || 'cmd':
        result.add(HotKeyModifier.meta);
      // Self-healing aliases for DBs corrupted by the pre-fix recorder, which
      // persisted localized display labels (Option/Strg/Umschalt/Befehl) as
      // storage strings. Accept them once so existing users don't have to
      // rebind; the next save writes the canonical token back.
      case 'option' || 'wahltaste':
        result.add(HotKeyModifier.alt);
      case 'strg':
        result.add(HotKeyModifier.control);
      case 'umschalt':
        result.add(HotKeyModifier.shift);
      case 'befehl':
        result.add(HotKeyModifier.meta);
    }
  }
  return result;
}
