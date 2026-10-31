// Parity guard for the low-power source (see lib/services/low_power_state.dart).
//
// Automatic re-warm after wake and after a pressure reload must stop in
// low-power mode on every desktop platform. Each platform needs its own source;
// a missing branch would quietly report "off" there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _source = 'lib/services/low_power_state.dart';

void main() {
  final source = File(_source).readAsStringSync();

  test('macOS reads isLowPowerModeEnabled through the Objective-C runtime', () {
    expect(source, contains('Platform.isMacOS'));
    expect(source, contains("'isLowPowerModeEnabled'"));
    expect(source, contains("'NSProcessInfo'"));
  });

  test('Windows reads SYSTEM_POWER_STATUS through GetSystemPowerStatus', () {
    expect(source, contains('Platform.isWindows'));
    expect(source, contains("'GetSystemPowerStatus'"));
  });

  test('Linux asks power-profiles-daemon over D-Bus', () {
    expect(source, contains('Platform.isLinux'));
    expect(source, contains('net.hadess.PowerProfiles'));
    expect(source, contains('ActiveProfile'));
  });

  test('the wake re-warm and the pressure reload consult the source', () {
    final wake = File(
      'lib/services/power_event_service.dart',
    ).readAsStringSync();
    final monitor = File(
      'lib/services/stt/memory_pressure_monitor.dart',
    ).readAsStringSync();
    expect(wake, contains('readLowPowerState()'));
    expect(monitor, contains('readLowPowerState()'));
  });
}
