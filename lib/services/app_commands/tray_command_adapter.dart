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

/// The tray menu items for [commands], in the same order and nesting.
List<MenuItem> trayMenuItems(
  List<AppCommand> commands, {
  required AppCommandLabelOf labelOf,
}) => [
  for (final command in commands)
    if (command.isSeparator)
      MenuItem.separator()
    else if (command.isSubmenu)
      MenuItem.submenu(
        key: command.id,
        label: labelOf(command.labelKey),
        disabled: !command.enabled,
        submenu: Menu(items: trayMenuItems(command.children, labelOf: labelOf)),
      )
    else if (command.isCheckable)
      MenuItem.checkbox(
        key: command.id,
        label: labelOf(command.labelKey),
        checked: command.checked,
        disabled: !command.enabled,
      )
    else
      MenuItem(
        key: command.id,
        label: labelOf(command.labelKey),
        disabled: !command.enabled,
      ),
];
