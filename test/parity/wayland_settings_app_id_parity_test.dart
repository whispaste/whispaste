// Parity guard for the Wayland hotkey's settings page (#44).
//
// On a Wayland desktop the shortcut belongs to the desktop, so the app opens
// the desktop's page for WhisPaste instead of recording a new one. The Linux
// runner reports which desktop ID that page has, read from the installed
// entry; the Dart monitor reads the same key. A renamed key on either side
// would silently drop the button.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final monitor = File(
    'lib/services/keyboard_up_monitor.dart',
  ).readAsStringSync();
  final host = File('linux/runner/keyboard_monitor_host.cc').readAsStringSync();
  final installer = File(
    'linux/runner/desktop_entry_installer.cc',
  ).readAsStringSync();
  final cmake = File('linux/runner/CMakeLists.txt').readAsStringSync();

  test('runner and monitor share the capability key', () {
    expect(host, contains('"settingsAppId"'));
    expect(monitor, contains("'settingsAppId'"));
  });

  test('the ID comes from the installed, visible desktop entry', () {
    expect(host, contains('SettingsDesktopId(APPLICATION_ID)'));
    expect(installer, contains('g_desktop_app_info_new'));
    expect(installer, contains('g_app_info_should_show'));
    expect(cmake, contains('PkgConfig::GIO_UNIX'));
  });
}
