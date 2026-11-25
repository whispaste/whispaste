/// App-wide shortcuts that open the Help hub (ticket): F1 and Cmd/Ctrl+?, the
/// two keys people reach for when they look for help. Cmd/Ctrl+? is bound
/// three ways because the key behind "?" differs by platform and layout.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Logical key of the ß key on German layouts (Unicode code point of ß).
const LogicalKeyboardKey _germanSharpS = LogicalKeyboardKey(0xdf);

/// Bindings for [CallbackShortcuts] that call [openHelp].
Map<ShortcutActivator, VoidCallback> helpShortcuts(VoidCallback openHelp) {
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  return <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.f1): openHelp,
    // US layout on macOS and Windows: Shift+/ arrives as logical slash.
    SingleActivator(
      LogicalKeyboardKey.slash,
      shift: true,
      control: !isMac,
      meta: isMac,
    ): openHelp,
    // Linux reports the shifted key as logical question, so the slash
    // binding never matched there (#1845).
    SingleActivator(
      LogicalKeyboardKey.question,
      shift: true,
      control: !isMac,
      meta: isMac,
    ): openHelp,
    // Layouts where "?" is not on the slash key (German: Shift+ß) match on
    // the typed character instead.
    CharacterActivator('?', control: !isMac, meta: isMac): openHelp,
    // Windows sends no character while Ctrl is held, so on the German layout
    // only the key itself is left: the logical key of the ß key is "ß" (#1845).
    SingleActivator(_germanSharpS, shift: true, control: !isMac, meta: isMac):
        openHelp,
    // Windows itself reports that key as logical bracketLeft on the physical
    // minus position, still with no character (logged on hardware, #1931).
    if (!isMac) const _WindowsGermanQuestionKey(): openHelp,
  };
}

/// Ctrl+Shift on the German ß key as Windows reports it: logical
/// bracketLeft, physical Minus. Both must match, so US Ctrl+Shift+[ (logical
/// bracketLeft on the physical BracketLeft key) does not open Help.
class _WindowsGermanQuestionKey extends ShortcutActivator {
  const _WindowsGermanQuestionKey();

  @override
  Iterable<LogicalKeyboardKey>? get triggers => const [
    LogicalKeyboardKey.bracketLeft,
  ];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.bracketLeft &&
      event.physicalKey == PhysicalKeyboardKey.minus &&
      state.isControlPressed &&
      state.isShiftPressed &&
      !state.isAltPressed &&
      !state.isMetaPressed;

  @override
  String debugDescribeKeys() => 'Ctrl+Shift+ß (Windows, German layout)';
}

/// Bindings for a plain "?" (no Cmd/Ctrl) that opens a view's shortcut
/// overview, such as the recording detail. The key behind "?" differs by
/// layout: Shift+/ on US layouts, logical question on Linux, Shift+ß on
/// German layouts, where only the typed character is reliable (#1845).
Map<ShortcutActivator, VoidCallback> shortcutOverviewKeys(
  VoidCallback openOverview,
) => {
  const SingleActivator(LogicalKeyboardKey.slash, shift: true): openOverview,
  const SingleActivator(LogicalKeyboardKey.question, shift: true): openOverview,
  const CharacterActivator('?'): openOverview,
};
