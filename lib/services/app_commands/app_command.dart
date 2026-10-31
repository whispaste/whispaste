/// The shared command model (MZ-01).
///
/// Every menu surface of the app (tray, macOS menu bar, title-bar menu) is
/// built from one command tree of [AppCommand]s. A surface is only an adapter
/// that turns the tree into its native menu; the tree itself knows nothing
/// about tray_manager, NSMenu or Flutter widgets.
///
/// Ids are stable and double as the menu keys of the tray, so an id is the
/// identity of a command on every surface (for example `lang:de`, `mic:<label>`,
/// `toggle_recording`).
library;

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/foundation.dart' show immutable;

/// One entry of a command tree: an action, a checkable entry, a submenu or a
/// separator.
@immutable
class AppCommand {
  /// An action or checkable entry. A non-null [checked] makes it a checkmark
  /// entry (radio behaviour is the caller's job, see the submenu builders).
  const AppCommand({
    required this.id,
    required this.labelKey,
    this.icon,
    this.enabled = true,
    this.checked,
    this.shortcut,
    this.children = const [],
  }) : isSeparator = false;

  /// A visual divider between entries.
  const AppCommand.separator()
    : id = '',
      labelKey = '',
      icon = null,
      enabled = true,
      checked = null,
      shortcut = null,
      children = const [],
      isSeparator = true;

  /// Stable identity, also the menu key on every surface.
  final String id;

  /// What the entry reads as. Either an ARB key of the app's localizations
  /// (resolved by the surface through its label table) or text that is already
  /// final, such as a device name or a language endonym. A key the table does
  /// not know is shown as it is.
  final String labelKey;

  /// Optional icon for surfaces that show one. Tray menus ignore it.
  final IconData? icon;

  /// `false` shows the entry greyed out (status lines, unavailable actions).
  final bool enabled;

  /// `null` for a plain entry; `true`/`false` for a checkmark entry.
  final bool? checked;

  /// Logical shortcut such as `mod+,`, where `mod` is Cmd on macOS and Ctrl
  /// elsewhere. Stored for the menu-bar adapter; the tray does not show it.
  final String? shortcut;

  /// Entries of a submenu. Non-empty makes this entry a submenu.
  final List<AppCommand> children;

  /// Whether this node is a separator.
  final bool isSeparator;

  /// Whether this node opens a submenu.
  bool get isSubmenu => children.isNotEmpty;

  /// Whether this node is a checkmark entry.
  bool get isCheckable => checked != null;
}

/// Every command of [commands] in depth-first order, separators and submenu
/// nodes included only through their children. Used by tests and by guards
/// that must see the whole tree.
Iterable<AppCommand> flattenAppCommands(List<AppCommand> commands) sync* {
  for (final command in commands) {
    if (command.isSeparator) continue;
    yield command;
    yield* flattenAppCommands(command.children);
  }
}
