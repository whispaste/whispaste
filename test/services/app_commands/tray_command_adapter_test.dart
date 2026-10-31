import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_adapter.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/tray_language_menu.dart';
import 'package:whispaste/services/tray_mic_menu.dart';

/// Flattens tray items depth-first, the same walk [flattenAppCommands] makes.
Iterable<MenuItem> _flattenMenu(List<MenuItem> items) sync* {
  for (final item in items) {
    if (item.type == 'separator') continue;
    yield item;
    final submenu = item.submenu;
    if (submenu != null) yield* _flattenMenu(submenu.items ?? const []);
  }
}

const _labels = <String, String>{
  'trayStartRecording': 'Start recording',
  'trayStopRecording': 'Stop recording',
  'trayStatusRecording': 'Recording',
  'trayStatusReady': 'Ready',
  'trayTranscribeFile': 'Transcribe file…',
  'trayMicrophone': 'Microphone',
  'trayLanguage': 'Language',
  'trayLanguageMore': 'More…',
  'settingsLanguageAutoDetect': 'Auto-detect',
  'settingsMicSystemDefault': 'System default',
  'trayOpenSidePanel': 'Open quick-paste panel',
  'trayOpenApp': 'Open WhisPaste',
  'traySettings': 'Settings',
  'trayQuit': 'Quit',
};

String _label(String key) => _labels[key] ?? key;

List<AppCommand> _languages() => buildLanguageCommands(
  activeCode: 'ru',
  favoriteCodes: const ['de', 'en'],
  autoLabelKey: 'settingsLanguageAutoDetect',
  moreLabelKey: 'trayLanguageMore',
);

void main() {
  final state = TrayMenuState(
    isRecording: false,
    micDeviceLabels: [micDefaultLabel, 'USB Mic'],
    selectedMic: 'USB Mic',
    languageCommands: _languages(),
    actionNeeded: (id: 'paste_action_needed', label: 'Auto-Paste blocked'),
    sidePanelAvailable: true,
  );

  test('the tray adapter keeps the ids, labels and checkmarks of the tree', () {
    final commands = buildTrayCommands(state, _labels);
    final tree = [
      for (final c in flattenAppCommands(commands))
        (id: c.id, label: _label(c.labelKey), checked: c.checked),
    ];
    final menu = [
      for (final m in _flattenMenu(trayMenuItems(commands, labelOf: _label)))
        (id: m.key ?? '', label: m.label ?? '', checked: m.checked),
    ];
    expect(menu, isNotEmpty);
    expect(menu.map((e) => e.id), tree.map((e) => e.id));
    expect(menu.map((e) => e.label), tree.map((e) => e.label));
    expect(menu.map((e) => e.checked), tree.map((e) => e.checked));
  });

  test('the tray menu keeps its order and separators', () {
    final items = trayMenuItems(
      buildTrayCommands(state, _labels),
      labelOf: _label,
    );
    final top = [
      for (final item in items)
        item.type == 'separator' ? '---' : (item.key ?? item.label),
    ];
    expect(top, [
      'paste_action_needed',
      '---',
      'status',
      '---',
      'toggle_recording',
      'transcribe_file',
      'lang-submenu',
      'mic-submenu',
      '---',
      'side_panel',
      'show',
      'settings',
      'feedback',
      '---',
      'quit',
    ]);
  });

  test('a recording flips the toggle label and the status line', () {
    final items = trayMenuItems(
      buildTrayCommands(
        const TrayMenuState(
          isRecording: true,
          micDeviceLabels: [micDefaultLabel],
          selectedMic: micDefaultLabel,
        ),
        _labels,
      ),
      labelOf: _label,
    );
    final byKey = {for (final i in items) ?i.key: i};
    expect(byKey[TrayCommandIds.toggleRecording]!.label, 'Stop recording');
    expect(byKey[TrayCommandIds.status]!.label, '🔴 Recording');
    expect(byKey[TrayCommandIds.status]!.disabled, isTrue);
  });

  test('hides the microphone and language submenus when they are not '
      'offered', () {
    final commands = buildTrayCommands(
      const TrayMenuState(
        isRecording: false,
        micDeviceLabels: [micDefaultLabel],
        selectedMic: micDefaultLabel,
      ),
      _labels,
    );
    final ids = [for (final c in commands) c.id];
    expect(ids, isNot(contains(TrayCommandIds.microphone)));
    expect(ids, isNot(contains(TrayCommandIds.language)));
  });

  test('a labelKey the table does not know is shown as it is', () {
    final items = trayMenuItems(const [
      AppCommand(id: 'x', labelKey: 'Literal text'),
    ], labelOf: (key) => _labels[key] ?? key);
    expect(items.single.label, 'Literal text');
  });
}
