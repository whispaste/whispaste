/// The entries of the menu bar's Aufnahme menu (MZ-02), taken from the tray
/// command tree so both surfaces show the same state and locks.
library;

import 'app_command.dart';
import 'tray_command_catalog.dart';

/// The Aufnahme menu entries for [tray]: the start/stop entry, then the
/// Sprache, Sprachmodell, Smart Mode, Nach der Transkription, Mikrofon and
/// Profil submenus. Submenus missing from [tray] are left out.
List<AppCommand> recordingMenuCommands(List<AppCommand> tray) {
  const submenuIds = [
    TrayCommandIds.language,
    TrayCommandIds.speechModel,
    TrayCommandIds.smartMode,
    TrayCommandIds.output,
    TrayCommandIds.microphone,
    TrayCommandIds.profile,
  ];
  final toggle = _byId(tray, TrayCommandIds.toggleRecording);
  final submenus = [for (final id in submenuIds) ?_byId(tray, id)];
  return [
    ?toggle,
    if (toggle != null && submenus.isNotEmpty) const AppCommand.separator(),
    ...submenus,
  ];
}

AppCommand? _byId(List<AppCommand> commands, String id) {
  for (final command in commands) {
    if (command.id == id) return command;
  }
  return null;
}
