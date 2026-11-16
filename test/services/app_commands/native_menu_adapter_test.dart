/// #393: the wire format the native context menus (floating button, overlay)
/// are built from — structure, checkmarks, shortcuts and appearance.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/native_menu_adapter.dart';

void main() {
  test('commands map to entries with resolved labels and nesting', () {
    final items = nativeMenuItems(
      const [
        AppCommand(id: 'status', labelKey: 'ready', enabled: false),
        AppCommand(id: 'toggle', labelKey: 'start', shortcut: 'Ctrl+Space'),
        AppCommand.separator(),
        AppCommand(
          id: 'mic-submenu',
          labelKey: 'mic',
          children: [
            AppCommand(id: 'mic:a', labelKey: 'USB', checked: true),
            AppCommand(id: 'mic:b', labelKey: 'Built-in', checked: false),
          ],
        ),
      ],
      labelOf: (key) => const {'ready': 'Ready', 'start': 'Start'}[key] ?? key,
    );

    expect(items[0], {'id': 'status', 'label': 'Ready', 'enabled': false});
    expect(items[1], {
      'id': 'toggle',
      'label': 'Start',
      'enabled': true,
      'shortcut': 'Ctrl+Space',
    });
    expect(items[2], {'type': kNativeMenuSeparator});
    final children = items[3]['children']! as List<Map<String, Object?>>;
    expect(children.map((c) => c['checked']), [true, false]);
    expect(items[3].containsKey('checked'), isFalse);
  });

  test('navy and dark force a dark menu, system follows the OS', () {
    expect(nativeMenuAppearance(AppearanceMode.navy), 'dark');
    expect(nativeMenuAppearance(AppearanceMode.dark), 'dark');
    expect(nativeMenuAppearance(AppearanceMode.light), 'light');
    expect(nativeMenuAppearance(AppearanceMode.system), 'system');
  });
}
