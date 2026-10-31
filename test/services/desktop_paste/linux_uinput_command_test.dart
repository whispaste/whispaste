import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';

void main() {
  test('the copied command installs the rule shipped in packaging/linux', () {
    final rule = File('packaging/linux/71-whispaste-uinput.rules')
        .readAsLinesSync()
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));

    expect(
      kLinuxUinputUdevCommand,
      contains(rule),
      reason: 'the one-time command must write the same rule the packages ship',
    );
    expect(kLinuxUinputUdevCommand, contains('udevadm control --reload-rules'));
  });

  test('a snap is told to connect the uinput interface, not the udev rule', () {
    // Snap confinement ignores the host udev rule; snapd needs the
    // interface connected once (packaging/snap/README.md).
    expect(
      linuxUinputCopyCommand(LinuxPackageFormat.snap),
      'sudo snap connect whispaste:uinput',
    );
  });

  test('the other formats copy the udev command', () {
    for (final format in [
      LinuxPackageFormat.native,
      LinuxPackageFormat.flatpak,
      LinuxPackageFormat.appimage,
    ]) {
      expect(
        linuxUinputCopyCommand(format),
        kLinuxUinputUdevCommand,
        reason: '$format',
      );
    }
  });

  // XP-6-04: a bare `udevadm trigger` re-triggers every device on the
  // machine; the rule only concerns /dev/uinput.
  const filteredTrigger =
      'udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  test('the copied command only re-triggers the uinput device', () {
    expect(kLinuxUinputUdevCommand, endsWith('sudo $filteredTrigger'));
  });

  test('no app text tells the user to run an unfiltered udevadm trigger', () {
    for (final locale in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, Object?>;
      for (final MapEntry(:key, :value) in arb.entries) {
        if (value is! String || !value.contains('udevadm trigger')) continue;
        expect(
          value.split('udevadm trigger').length - 1,
          value.split(filteredTrigger).length - 1,
          reason: '$locale/$key',
        );
      }
    }
  });
}
