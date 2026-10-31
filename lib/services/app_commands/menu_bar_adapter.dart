/// Menu bar surface adapter for the shared command tree (MZ-01, macOS).
///
/// Turns [AppCommand]s into plain [MenuBarNode]s: ids, final labels,
/// checkmarks, locks and separators. The Flutter platform menu types are built
/// from these nodes in `lib/widgets/app_menu_bar.dart`, so the mapping is
/// testable without a running macOS menu bar.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'app_command.dart';
import 'tray_command_adapter.dart' show AppCommandLabelOf;

/// Glyph in front of a checked entry. Flutter's platform menus have no native
/// checkmark, so a checked entry carries this prefix in its label.
const kMenuBarCheckMark = '✓ ';

/// A logical shortcut the menu bar can bind, such as `mod+,` (Cmd on macOS).
final _boundShortcut = RegExp(r'^mod\+(.)$');

/// One entry of a menu bar menu, already resolved to its final text.
@immutable
class MenuBarNode {
  const MenuBarNode({
    required this.id,
    required this.label,
    this.enabled = true,
    this.checked,
    this.keyEquivalent,
    this.children = const [],
  }) : isSeparator = false;

  /// A divider between entries.
  const MenuBarNode.separator()
    : id = '',
      label = '',
      enabled = true,
      checked = null,
      keyEquivalent = null,
      children = const [],
      isSeparator = true;

  /// Stable identity, the same id the tray uses.
  final String id;

  /// The text shown. Checked entries start with [kMenuBarCheckMark]; a
  /// shortcut that is only displayed (not bound) is appended in brackets.
  final String label;

  /// `false` shows the entry greyed out.
  final bool enabled;

  /// `null` for a plain entry; `true`/`false` for a checkmark entry.
  final bool? checked;

  /// A logical shortcut the menu binds, such as `mod+,`. Null when the
  /// shortcut is only shown as text.
  final String? keyEquivalent;

  /// Entries of a submenu; empty for an action.
  final List<MenuBarNode> children;

  /// Whether this node is a divider.
  final bool isSeparator;

  /// Whether this node opens a submenu.
  bool get isSubmenu => children.isNotEmpty;
}

/// The menu bar nodes for [commands], in the same order and nesting as the
/// tray adapter renders them.
List<MenuBarNode> menuBarNodes(
  List<AppCommand> commands, {
  required AppCommandLabelOf labelOf,
}) => [
  for (final command in commands)
    if (command.isSeparator)
      const MenuBarNode.separator()
    else
      MenuBarNode(
        id: command.id,
        label: _labelOf(command, labelOf(command.labelKey)),
        enabled: command.enabled,
        checked: command.checked,
        keyEquivalent: _keyEquivalentOf(command.shortcut),
        children: menuBarNodes(command.children, labelOf: labelOf),
      ),
];

String _labelOf(AppCommand command, String text) {
  final prefixed = command.checked == true ? '$kMenuBarCheckMark$text' : text;
  final shortcut = command.shortcut;
  if (shortcut == null || _keyEquivalentOf(shortcut) != null) return prefixed;
  return '$prefixed ($shortcut)';
}

String? _keyEquivalentOf(String? shortcut) =>
    shortcut != null && _boundShortcut.hasMatch(shortcut) ? shortcut : null;
