import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';

/// The recent-recordings submenu of the tray: ids and labels only, and a
/// locked history offers the unlock entry alone.
TrayMenuState _state({
  List<({String id, String label})> recent = const [],
  bool locked = false,
}) => TrayMenuState(
  isRecording: false,
  micDeviceLabels: const ['default'],
  selectedMic: 'default',
  recentRecordings: recent,
  historyLocked: locked,
);

AppCommand? _submenu(List<AppCommand> commands) =>
    commands.where((c) => c.id == TrayCommandIds.recentRecordings).firstOrNull;

void main() {
  test('lists recent recordings by id with their date and word count', () {
    final commands = buildTrayCommands(
      _state(
        recent: const [
          (id: 'a', label: '10:04 · 3 words'),
          (id: 'b', label: '09:58 · 1 word'),
        ],
      ),
      const {},
    );

    final submenu = _submenu(commands)!;
    expect(submenu.children.map((c) => c.id), [
      trayRecentKey('a'),
      trayRecentKey('b'),
    ]);
    expect(submenu.children.map((c) => c.labelKey), [
      '10:04 · 3 words',
      '09:58 · 1 word',
    ]);
  });

  test('a locked history shows only the unlock entry, never a recording', () {
    final commands = buildTrayCommands(
      _state(recent: const [(id: 'a', label: '10:04 · 3 words')], locked: true),
      const {},
    );

    final submenu = _submenu(commands)!;
    expect(submenu.children.map((c) => c.id), [TrayCommandIds.unlockHistory]);
  });

  test('no recordings and no lock: no submenu', () {
    final commands = buildTrayCommands(_state(), const {});

    expect(_submenu(commands), isNull);
  });

  test('recent item ids round-trip and other ids are not recordings', () {
    expect(trayRecentIdFromKey(trayRecentKey('abc')), 'abc');
    expect(trayRecentIdFromKey(TrayCommandIds.quit), isNull);
  });
}
