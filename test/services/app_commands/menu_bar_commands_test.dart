import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/menu_bar_adapter.dart';
import 'package:whispaste/services/app_commands/menu_bar_commands.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';

AppCommand _submenu(String id) => AppCommand(
  id: id,
  labelKey: id,
  children: const [AppCommand(id: 'x', labelKey: 'x')],
);

void main() {
  test('the Aufnahme menu lists the toggle first, then the submenus', () {
    final tray = [
      const AppCommand(id: TrayCommandIds.status, labelKey: 'status'),
      const AppCommand.separator(),
      const AppCommand(id: TrayCommandIds.toggleRecording, labelKey: 'start'),
      const AppCommand(id: TrayCommandIds.transcribeFile, labelKey: 'file'),
      _submenu(TrayCommandIds.profile),
      _submenu(TrayCommandIds.microphone),
      _submenu(TrayCommandIds.output),
      _submenu(TrayCommandIds.smartMode),
      _submenu(TrayCommandIds.speechModel),
      _submenu(TrayCommandIds.language),
    ];

    final ids = recordingMenuCommands(tray).map((c) => c.id).toList();

    expect(ids, [
      TrayCommandIds.toggleRecording,
      '',
      TrayCommandIds.language,
      TrayCommandIds.speechModel,
      TrayCommandIds.smartMode,
      TrayCommandIds.output,
      TrayCommandIds.microphone,
      TrayCommandIds.profile,
    ]);
  });

  test('missing submenus are left out without a stray separator', () {
    final nodes = menuBarNodes(
      recordingMenuCommands([
        const AppCommand(id: TrayCommandIds.toggleRecording, labelKey: 'start'),
        const AppCommand(id: TrayCommandIds.transcribeFile, labelKey: 'file'),
      ]),
      labelOf: (key) => key,
    );

    expect(nodes.map((n) => n.id), [TrayCommandIds.toggleRecording]);
  });

  test('the dictation hotkey is shown next to the toggle entry', () {
    final nodes = menuBarNodes(
      recordingMenuCommands([
        const AppCommand(
          id: TrayCommandIds.toggleRecording,
          labelKey: 'start',
          shortcut: '⌃⌥D',
        ),
      ]),
      labelOf: (key) => key,
    );

    expect(nodes.single.label, 'start (⌃⌥D)');
    expect(nodes.single.keyEquivalent, isNull);
  });
}
