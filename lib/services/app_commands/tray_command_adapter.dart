/// Tray surface adapter for the shared command tree (MZ-01).
///
/// Turns [AppCommand]s into tray_manager menu items. It only maps structure:
/// ids become keys, labels are resolved through [labelOf], checkmarks and
/// enabled state carry over. It holds no command logic.
library;

import 'package:tray_manager/tray_manager.dart';

import 'app_command.dart';

/// Resolves a [AppCommand.labelKey] to the text shown on this surface.
typedef AppCommandLabelOf = String Function(String labelKey);

/// The shortcut text shown beside a tray entry, or null for none (#139).
///
/// A logical `mod+x` shortcut renders as `⌘X` on macOS. Elsewhere it is not
/// shown: the app binds those keys only in the macOS menu bar, so a hint
/// would promise a key that does nothing. Any other [shortcut] is already a
/// display text (the user's recording hotkey, e.g. `Ctrl+Shift+D`) and is
/// shown as is on every platform.
String? trayShortcutText(String? shortcut, {required bool isMacOS}) {
  if (shortcut == null || shortcut.isEmpty) return null;
  const modPrefix = 'mod+';
  if (!shortcut.startsWith(modPrefix)) return shortcut;
  if (!isMacOS) return null;
  return '⌘${shortcut.substring(modPrefix.length).toUpperCase()}';
}

/// The label with its shortcut: tab separated on Windows, where the menu
/// right-aligns it, else after a gap.
String trayLabelWithShortcut(
  String label,
  String? shortcutText, {
  required bool isWindows,
}) {
  if (shortcutText == null) return label;
  return isWindows ? '$label\t$shortcutText' : '$label    $shortcutText';
}

/// The tray menu items for [commands], in the same order and nesting.
List<MenuItem> trayMenuItems(
  List<AppCommand> commands, {
  required AppCommandLabelOf labelOf,
  bool isMacOS = false,
  bool isWindows = false,
}) {
  String labelFor(AppCommand command) => trayLabelWithShortcut(
    labelOf(command.labelKey),
    trayShortcutText(command.shortcut, isMacOS: isMacOS),
    isWindows: isWindows,
  );
  return [
    for (final command in commands)
      if (command.isSeparator)
        MenuItem.separator()
      else if (command.isSubmenu)
        MenuItem.submenu(
          key: command.id,
          label: labelFor(command),
          disabled: !command.enabled,
          submenu: Menu(
            items: trayMenuItems(
              command.children,
              labelOf: labelOf,
              isMacOS: isMacOS,
              isWindows: isWindows,
            ),
          ),
        )
      else if (command.isCheckable)
        MenuItem.checkbox(
          key: command.id,
          label: labelFor(command),
          checked: command.checked,
          disabled: !command.enabled,
        )
      else
        MenuItem(
          key: command.id,
          label: labelFor(command),
          disabled: !command.enabled,
        ),
  ];
}
