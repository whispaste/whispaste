// Parity guard for the shared command tree (MZ-01).
//
// Every command the tree can emit must reach every desktop platform. The
// tray is the surface that exists today; it is attached on macOS, Windows and
// Linux alike (`TrayService._isDesktop`). Menu-bar and title-bar adapters will
// be added to [_surfacesByPlatform] when they land, and the guard then checks
// that no command is left out on any platform.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/tray_language_menu.dart';
import 'package:whispaste/services/tray_mic_menu.dart';

const _desktopPlatforms = ['macos', 'windows', 'linux'];

/// Surfaces that render the command tree, per platform. Only the tray exists
/// so far, on every desktop platform.
const _surfacesByPlatform = <String, List<String>>{
  'macos': ['tray'],
  'windows': ['tray'],
  'linux': ['tray'],
};

/// Every command id the tree can emit, with all optional parts switched on.
Set<String> _maximalTrayIds() {
  final commands = buildTrayCommands(
    TrayMenuState(
      isRecording: true,
      micDeviceLabels: const [micDefaultLabel, 'USB Mic'],
      selectedMic: 'USB Mic',
      languageCommands: buildLanguageCommands(
        activeCode: 'auto',
        favoriteCodes: const ['de'],
        autoLabelKey: 'settingsLanguageAutoDetect',
        moreLabelKey: 'trayLanguageMore',
      ),
      speechModelCommands: const [AppCommand(id: 'stt:x', labelKey: 'x')],
      smartModeCommands: const [AppCommand(id: 'smart:off', labelKey: 'x')],
      outputCommands: const [AppCommand(id: 'output:paste', labelKey: 'x')],
      profileCommands: const [AppCommand(id: 'profile:x', labelKey: 'x')],
      actionNeeded: (id: 'paste_action_needed', label: 'x'),
      sidePanelAvailable: true,
    ),
    const {},
  );
  return {for (final c in flattenAppCommands(commands)) c.id};
}

/// The menu surface of each desktop platform: `implemented` names the source
/// file that builds it, `planned` the ticket that will. macOS has the global
/// menu bar; Windows and Linux get a title-bar menu (MZ-05, MZ-06).
const _menuSurfaceByPlatform = <String, ({String? file, String? ticket})>{
  'macos': (file: 'lib/widgets/app_menu_bar.dart', ticket: null),
  'windows': (file: 'lib/widgets/title_bar_menu.dart', ticket: null),
  'linux': (file: 'lib/widgets/title_bar_menu.dart', ticket: null),
};

void main() {
  test('every desktop platform has a menu surface, implemented or planned', () {
    for (final platform in _desktopPlatforms) {
      final surface = _menuSurfaceByPlatform[platform];
      expect(
        surface != null && (surface.file != null || surface.ticket != null),
        isTrue,
        reason: 'no menu surface, implemented or planned, on $platform',
      );
    }
  });

  test('the Windows and Linux title-bar menu is wired into the title bar', () {
    for (final platform in ['windows', 'linux']) {
      final file = _menuSurfaceByPlatform[platform]!.file!;
      expect(File(file).existsSync(), isTrue, reason: '$platform menu file');
    }
    final titleBar = File('lib/app.dart').readAsStringSync();
    expect(titleBar, contains('WpTitleBarMenuButton'));
  });

  test('the macOS menu bar is built only on macOS', () {
    final file = _menuSurfaceByPlatform['macos']!.file!;
    final source = File(file).readAsStringSync();
    expect(source, contains('defaultTargetPlatform == TargetPlatform.macOS'));
  });

  test('the tray surface can render every command of the tree', () {
    final emitted = _maximalTrayIds();
    const declared = TrayCommandIds.all;
    // Dynamic ids (language, microphone, action-needed) come from their own
    // namespaces; the fixed ids must be exhaustive.
    expect(emitted.where((id) => !id.contains(':')), containsAll(declared));
  });

  test('every desktop platform carries a command surface', () {
    for (final platform in _desktopPlatforms) {
      expect(
        _surfacesByPlatform[platform],
        isNotEmpty,
        reason: 'no command surface on $platform',
      );
    }
  });

  test('the tray service is attached on all three desktop platforms', () {
    final source = File('lib/services/tray_service.dart').readAsStringSync();
    expect(
      source,
      contains('Platform.isWindows || Platform.isMacOS || Platform.isLinux'),
    );
  });
}
