/// Native context-menu surface adapter for the shared command tree (#393).
///
/// The floating button and the floating overlay show a native menu (Win32
/// popup menu, GtkMenu, NSMenu) that their hosts build from plain maps. This
/// adapter turns [AppCommand]s into that wire format, so the button's menu
/// has the same groups, names, checkmarks and shortcuts as the tray. It holds
/// no command logic.
library;

import '../../core/config/settings_enums.dart' show AppearanceMode;
import 'app_command.dart';
import 'tray_command_adapter.dart' show AppCommandLabelOf;

/// Wire value of a separator entry (`type`).
const kNativeMenuSeparator = 'separator';

/// The native menu entries for [commands], in the same order and nesting.
///
/// Each entry is a map with `id`, `label` and `enabled`; a checkmark entry
/// adds `checked`, an entry with a shortcut adds `shortcut` (display text,
/// right-aligned by the host), a submenu adds `children`. A separator is
/// `{type: separator}`. Hosts escape mnemonic characters themselves.
List<Map<String, Object?>> nativeMenuItems(
  List<AppCommand> commands, {
  required AppCommandLabelOf labelOf,
}) => [
  for (final command in commands)
    if (command.isSeparator)
      const {'type': kNativeMenuSeparator}
    else
      {
        'id': command.id,
        'label': labelOf(command.labelKey),
        'enabled': command.enabled,
        if (command.checked != null) 'checked': command.checked,
        if (command.shortcut != null) 'shortcut': command.shortcut,
        if (command.isSubmenu)
          'children': nativeMenuItems(command.children, labelOf: labelOf),
      },
];

/// How a native menu follows the app's appearance: `system` follows the OS,
/// `light`/`dark` force it. Navy is a dark appearance.
String nativeMenuAppearance(AppearanceMode mode) => switch (mode) {
  AppearanceMode.system => 'system',
  AppearanceMode.light => 'light',
  AppearanceMode.dark || AppearanceMode.navy => 'dark',
};
