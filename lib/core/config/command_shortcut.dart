/// The platform "command" shortcut family (Cmd on macOS, Ctrl on Windows and
/// Linux): one place that decides the modifier for both the key binding and
/// the text that advertises it, so a tooltip or help row cannot name a key the
/// binding does not listen to (#726).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show SingleActivator;

import '../l10n/generated/app_localizations.dart' show L10n;

// defaultTargetPlatform is the platform seam (#198): the real OS in the app,
// pinnable per test via TargetPlatformVariant. The tests' modifier helper
// (primaryShortcutModifier) reads the same seam.
bool _mac(bool? isMacOS) =>
    isMacOS ?? defaultTargetPlatform == TargetPlatform.macOS;

/// Binding for Cmd+[key] on macOS, Ctrl+[key] elsewhere (plus Shift when
/// [shift]). [isMacOS] defaults to the running platform.
///
/// The same combination always yields the same instance: [SingleActivator]
/// compares by identity, and shortcut maps are looked up by key. The cache is
/// keyed by platform as well, so a binding never keeps the platform of
/// whoever asked first (a test pinned to macOS used to leave Cmd bindings
/// behind for the Linux tests after it).
SingleActivator commandActivator(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool? isMacOS,
}) {
  final mac = _mac(isMacOS);
  return _activators.putIfAbsent((
    key,
    shift,
    mac,
  ), () => SingleActivator(key, control: !mac, meta: mac, shift: shift));
}

final _activators = <(LogicalKeyboardKey, bool, bool), SingleActivator>{};

/// How [commandActivator] is spelled for the user: `⌘S` / `⇧⌘L` on macOS,
/// `Ctrl+S` / `Ctrl+Shift+L` elsewhere, with the words localized through [l10n]
/// ("Strg+Umschalt+L" in German, as in the rest of the app). [key] is the key
/// cap text ("S", or [enterKey] for Return). Return is the ↩ cap on macOS and
/// the localized word elsewhere ("Strg+Eingabe"), matching the key cap and the
/// other help rows that name the key by word.
String commandShortcutLabel(
  String key, {
  bool shift = false,
  bool? isMacOS,
  L10n? l10n,
}) {
  final mac = _mac(isMacOS);
  final cap = key == enterKey && !mac
      ? (l10n?.shortcutKeyEnter ?? 'Enter')
      : key;
  if (mac) return '${shift ? '⇧' : ''}⌘$cap';
  final ctrl = l10n?.modifierCtrl ?? 'Ctrl';
  final shiftWord = shift ? '${l10n?.modifierShift ?? 'Shift'}+' : '';
  return '$ctrl+$shiftWord$cap';
}

/// Key text for Return in [commandShortcutLabel].
const enterKey = '↩';
