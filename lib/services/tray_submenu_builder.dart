/// Reusable builders for radio-style submenus of the command tree.
///
/// A submenu is a list of checkmark entries where exactly one is checked,
/// optionally followed by trailing entries (e.g. "More…"). Feature menus build
/// on [buildRadioCommands] and [buildSubmenuCommand]; the microphone submenu
/// in `tray_mic_menu.dart` follows the same key scheme.
library;

import 'app_commands/app_command.dart';

/// One selectable entry of a radio-style submenu.
class TrayRadioOption {
  const TrayRadioOption({required this.value, required this.labelKey});

  /// Identifies the option. Encoded into the command id, so it may contain
  /// any characters.
  final String value;

  /// Label key or final text, see [AppCommand.labelKey].
  final String labelKey;
}

/// Builds the checkmark entries for [options], with ids `<keyPrefix><value>`.
/// Exactly the entry whose value equals [selected] is checked. When [trailing]
/// is not empty it follows a separator.
List<AppCommand> buildRadioCommands({
  required String keyPrefix,
  required List<TrayRadioOption> options,
  required String? selected,
  List<AppCommand> trailing = const [],
}) {
  return [
    for (final option in options)
      AppCommand(
        id: '$keyPrefix${option.value}',
        labelKey: option.labelKey,
        checked: option.value == selected,
      ),
    if (options.isNotEmpty && trailing.isNotEmpty) const AppCommand.separator(),
    ...trailing,
  ];
}

/// The option value encoded in [id] under [keyPrefix], or null when the id is
/// outside that namespace.
String? trayRadioValueFromKey(String keyPrefix, String id) =>
    id.startsWith(keyPrefix) ? id.substring(keyPrefix.length) : null;

/// A command that opens a submenu holding [children].
AppCommand buildSubmenuCommand({
  required String id,
  required String labelKey,
  required List<AppCommand> children,
  bool enabled = true,
}) => AppCommand(
  id: id,
  labelKey: labelKey,
  enabled: enabled,
  children: children,
);
