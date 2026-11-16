// Adapter test for the menu bar surface (MZ-01): the same command tree gives
// the same ids, labels and checked states on the menu bar as in the tray.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/menu_bar_adapter.dart';

void main() {
  String labelOf(String key) => 'L:$key';

  test('keeps ids, nesting and separators in tree order', () {
    final nodes = menuBarNodes(const [
      AppCommand(id: 'a', labelKey: 'first'),
      AppCommand.separator(),
      AppCommand(
        id: 'sub',
        labelKey: 'sub',
        children: [AppCommand(id: 'sub:x', labelKey: 'x')],
      ),
    ], labelOf: labelOf);

    expect(
      [for (final n in nodes) n.isSeparator ? '---' : n.id],
      ['a', '---', 'sub'],
    );
    expect(nodes[2].isSubmenu, isTrue);
    expect(nodes[2].children.single.id, 'sub:x');
    expect(nodes[2].children.single.label, 'L:x');
  });

  test('checked entries carry the check mark, unchecked ones do not', () {
    final nodes = menuBarNodes(const [
      AppCommand(id: 'on', labelKey: 'a', checked: true),
      AppCommand(id: 'off', labelKey: 'b', checked: false),
      AppCommand(id: 'plain', labelKey: 'c'),
    ], labelOf: labelOf);

    expect(nodes[0].label, '${kMenuBarCheckMark}L:a');
    expect(nodes[0].checked, isTrue);
    expect(nodes[1].label, 'L:b');
    expect(nodes[1].checked, isFalse);
    expect(nodes[2].checked, isNull);
  });

  test('disabled commands stay disabled', () {
    final nodes = menuBarNodes(const [
      AppCommand(id: 'locked', labelKey: 'l', enabled: false),
    ], labelOf: labelOf);

    expect(nodes.single.enabled, isFalse);
  });

  test('a logical mod shortcut is bound, a display shortcut is shown', () {
    final nodes = menuBarNodes(const [
      AppCommand(id: 'settings', labelKey: 's', shortcut: 'mod+,'),
      AppCommand(id: 'toggle', labelKey: 't', shortcut: 'Ctrl+Shift+D'),
    ], labelOf: labelOf);

    expect(nodes[0].keyEquivalent, 'mod+,');
    expect(nodes[0].label, 'L:s');
    expect(nodes[1].keyEquivalent, isNull);
    expect(nodes[1].label, 'L:t (Ctrl+Shift+D)');
  });

  test('the same tree gives identical ids, labels and checks as the tray', () {
    const tree = [
      AppCommand(id: 'lang:de', labelKey: 'Deutsch', checked: true),
      AppCommand(id: 'lang:en', labelKey: 'English', checked: false),
      AppCommand(id: 'stt-locked', labelKey: 'Locked', enabled: false),
    ];
    final menu = menuBarNodes(tree, labelOf: labelOf);

    expect([for (final n in menu) n.id], [for (final c in tree) c.id]);
    expect(
      [for (final n in menu) n.enabled],
      [for (final c in tree) c.enabled],
    );
    expect(
      [for (final n in menu) n.checked],
      [for (final c in tree) c.checked],
    );
  });
}
