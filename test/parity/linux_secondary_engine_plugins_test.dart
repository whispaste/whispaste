import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Linux secondary-engine plugin registration (issue #154).
///
/// tray_manager 0.5.3, local_notifier 0.1.6 and hotkey_manager_linux 0.2.0
/// keep a process-global native instance that every
/// `*_plugin_register_with_registrar` call overwrites. If a secondary Flutter
/// engine registers them, tray menu clicks (Quit!) are routed to that engine,
/// which has no TrayService. So the secondary windows must register only the
/// plugins they need, through `fl_register_secondary_plugins()`, and never the
/// process-global ones. The main engine keeps the full generated registrant.
void main() {
  const runnerDir = 'linux/runner';

  const secondaryWindowSources = <String>[
    '$runnerDir/floating_button_window.cc',
    '$runnerDir/floating_overlay_window.cc',
    '$runnerDir/side_panel_window.cc',
    '$runnerDir/snippet_picker_window.cc',
  ];

  // Plugins whose native state is process-global (see the doc comment above).
  const globalPluginSymbols = <String>[
    'tray_manager',
    'TrayManagerPlugin',
    'local_notifier',
    'LocalNotifierPlugin',
    'hotkey_manager_linux',
    'HotkeyManagerLinuxPlugin',
  ];

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    return file.readAsStringSync();
  }

  test('no secondary Flutter window registers the full generated registrant', () {
    for (final path in secondaryWindowSources) {
      final source = read(path);
      expect(
        source.contains('fl_register_plugins('),
        isFalse,
        reason:
            '$path must not call fl_register_plugins(): that registers '
            'tray_manager/local_notifier/hotkey_manager_linux and steals their '
            'process-global owner from the main engine (issue #154).',
      );
      expect(
        source.contains('fl_register_secondary_plugins('),
        isTrue,
        reason: '$path must register through fl_register_secondary_plugins().',
      );
      expect(
        source.contains('"secondary_plugin_registrant.h"'),
        isTrue,
        reason: '$path must include secondary_plugin_registrant.h.',
      );
    }
  });

  test('the secondary registrant never registers process-global plugins', () {
    final source = read('$runnerDir/secondary_plugin_registrant.cc');
    for (final symbol in globalPluginSymbols) {
      expect(
        source.contains(symbol),
        isFalse,
        reason:
            'secondary_plugin_registrant.cc must not mention "$symbol": it '
            'overwrites a process-global native instance (issue #154).',
      );
    }
    expect(
      source.contains('generated_plugin_registrant.h'),
      isFalse,
      reason:
          'the secondary registrant must not reuse the generated registrant.',
    );
  });

  test('the main engine still registers the full generated registrant', () {
    final source = read('$runnerDir/my_application.cc');
    expect(
      source.contains('fl_register_plugins(FL_PLUGIN_REGISTRY(view))'),
      isTrue,
      reason:
          'my_application.cc must keep the main engine registrant (owner of the tray).',
    );
  });

  test('the secondary registrant is part of the runner build', () {
    final cmake = read('$runnerDir/CMakeLists.txt');
    expect(
      cmake.contains('"secondary_plugin_registrant.cc"'),
      isTrue,
      reason:
          'runner/CMakeLists.txt must compile secondary_plugin_registrant.cc.',
    );
  });
}
