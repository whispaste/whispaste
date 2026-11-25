import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';
import 'package:whispaste/services/desktop_paste/linux_uinput_access.dart';

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

  group('taking the access back (R-02)', () {
    test('the remove command undoes everything the grant set up', () {
      final rulePath = RegExp(
        r'/etc/udev/rules\.d/\S+',
      ).stringMatch(kLinuxUinputUdevCommand)!;
      expect(rulePath, LinuxUinputAccess.rulePath);
      expect(kLinuxUinputRemoveCommand, contains('rm -f $rulePath'));
      // Without this the session keeps its ACL until the next login.
      expect(kLinuxUinputRemoveCommand, contains('setfacl -x'));
      expect(kLinuxUinputRemoveCommand, contains('/dev/uinput'));
    });

    test('udevadm and setfacl cannot fail the command, like the script', () {
      final script = File(
        'packaging/linux/uninstall-uinput-rule.sh',
      ).readAsStringSync();
      expect(script, contains('udevadm control --reload-rules || true'));
      for (final step in [
        'sudo udevadm control --reload-rules',
        'sudo udevadm trigger',
        'sudo setfacl -x',
      ]) {
        final i = kLinuxUinputRemoveCommand.indexOf(step);
        expect(i, greaterThan(-1), reason: step);
        final end = kLinuxUinputRemoveCommand.indexOf('}', i);
        expect(
          kLinuxUinputRemoveCommand.substring(i, end),
          endsWith('|| true; '),
          reason: '$step must not abort the revoke',
        );
      }
      // rm -f cannot fail on missing files, so the chain always reaches here.
      expect(kLinuxUinputRemoveCommand, startsWith('sudo rm -f '));
    });

    test('native and AppImage offer it only while the rule exists', () {
      for (final format in [
        LinuxPackageFormat.native,
        LinuxPackageFormat.appimage,
      ]) {
        expect(
          linuxUinputRemoveCommand(format, hostRule: true),
          kLinuxUinputRemoveCommand,
        );
        expect(linuxUinputRemoveCommand(format, hostRule: false), isNull);
      }
    });

    test('a snap disconnects the interface', () {
      expect(
        linuxUinputRemoveCommand(LinuxPackageFormat.snap, hostRule: false),
        'sudo snap disconnect whispaste:uinput',
      );
    });

    test('a Flatpak offers it although the sandbox cannot see the rule', () {
      expect(
        linuxUinputRemoveCommand(LinuxPackageFormat.flatpak, hostRule: false),
        kLinuxUinputRemoveCommand,
      );
    });
  });

  // XP-6-04: a bare `udevadm trigger` re-triggers every device on the
  // machine; the rule only concerns /dev/uinput.
  const filteredTrigger =
      'udevadm trigger --subsystem-match=misc --sysname-match=uinput';

  test('the copied command only re-triggers the uinput device', () {
    expect(kLinuxUinputUdevCommand, endsWith('sudo $filteredTrigger'));
  });

  test('no app text tells the user to run an unfiltered udevadm trigger', () {
    for (final locale in [
      'de',
      'en',
      'es',
      'pt',
      'ru',
      'he',
      'fr',
      'it',
      'zh',
    ]) {
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
