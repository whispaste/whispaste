/// Parity guard for the global hotkey self-heal (macOS, Windows, Linux).
///
/// The heal triggers live in shared Dart code, so every platform gets them
/// alike. The only platform-specific input is the sleep/wake signal, which
/// each native runner must send as `didWake`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('all four heal triggers are wired in shared Dart code', () {
    expect(
      _read('lib/services/power_event_service.dart'),
      contains('HotkeyHealTrigger.wake'),
    );
    expect(
      _read('lib/services/stt/memory_pressure_monitor.dart'),
      contains('onUnloadedByPressure'),
    );
    expect(
      _read('lib/widgets/service_bootstrap.dart'),
      contains('HotkeyHealTrigger.uiStall'),
    );
    expect(
      _read('lib/services/hotkey_service.dart'),
      contains('HotkeyHealTrigger.timer'),
    );
  });

  test('every platform runner reports wake to Dart as didWake', () {
    expect(_read('windows/runner/power_event_host.cpp'), contains('didWake'));
    expect(_read('linux/runner/power_event_host.cc'), contains('didWake'));
    expect(_read('macos/Runner/AppDelegate.swift'), contains('didWake'));
  });

  test('the heal rules have no platform branch', () {
    expect(
      _read('lib/services/hotkey_self_heal.dart'),
      isNot(contains('Platform.is')),
    );
  });

  test('every quit path runs under the hard deadline', () {
    expect(
      _read('lib/services/tray_service.dart'),
      contains('shutdownWithHardDeadline('),
    );
    expect(_read('lib/main.dart'), contains('shutdownWithHardDeadline('));
    expect(
      _read('lib/core/platform/macos_lifecycle_channel.dart'),
      contains('shutdownWithHardDeadline('),
    );
    expect(_read('macos/Runner/AppDelegate.swift'), contains('_exit(0)'));
  });

  test('the heal is serialized through the global hotkey chain', () {
    expect(
      _read('lib/services/hotkey_service.dart'),
      contains('_serializeGlobal(() => _healGlobal(trigger))'),
    );
  });
}
