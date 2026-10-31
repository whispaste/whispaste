/// R-02: the .deb grants /dev/uinput only after consent, through pkexec and
/// the root helper the package ships. The app never runs sudo itself.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/linux_uinput_access.dart';

void main() {
  final calls = <List<String>>[];

  LinuxUinputAccess access({
    int exitCode = 0,
    bool throws = false,
    Set<String> present = const {
      LinuxUinputAccess.helperPath,
      LinuxUinputAccess.pkexecPath,
    },
  }) {
    calls.clear();
    return LinuxUinputAccess(
      run: (exe, args) async {
        calls.add([exe, ...args]);
        if (throws) throw const ProcessException('pkexec', [], 'gone', 2);
        return ProcessResult(0, exitCode, '', '');
      },
      exists: present.contains,
    );
  }

  test('manages the grant only where the package ships helper and pkexec', () {
    expect(access().canManage, isTrue);
    expect(
      access(present: const {LinuxUinputAccess.pkexecPath}).canManage,
      isFalse,
      reason: 'Flatpak, AppImage and the tarball have no helper',
    );
    expect(
      access(present: const {LinuxUinputAccess.helperPath}).canManage,
      isFalse,
    );
  });

  test('enable runs exactly the helper through pkexec', () async {
    final a = access();

    expect(await a.enable(), UinputAccessChange.done);
    expect(calls.single, [
      '/usr/bin/pkexec',
      '/usr/libexec/whispaste/uinput-access',
      'enable',
    ]);
  });

  test('disable runs exactly the helper through pkexec', () async {
    final a = access();

    expect(await a.disable(), UinputAccessChange.done);
    expect(calls.single.last, 'disable');
  });

  test('a dismissed password dialog is a cancel, not an error', () async {
    expect(await access(exitCode: 126).enable(), UinputAccessChange.cancelled);
    expect(await access(exitCode: 127).enable(), UinputAccessChange.cancelled);
  });

  test('other failures and a missing pkexec report failed', () async {
    expect(await access(exitCode: 1).enable(), UinputAccessChange.failed);
    expect(await access(throws: true).disable(), UinputAccessChange.failed);
  });

  test('without the helper nothing runs', () async {
    final a = access(present: const {});

    expect(await a.enable(), UinputAccessChange.unavailable);
    expect(await a.isGranted(), isFalse);
    expect(calls, isEmpty);
  });

  test('isGranted asks the helper status without pkexec', () async {
    expect(await access().isGranted(), isTrue);
    expect(calls.single, ['/usr/libexec/whispaste/uinput-access', 'status']);
    expect(await access(exitCode: 1).isGranted(), isFalse);
    expect(await access(throws: true).isGranted(), isFalse);
  });
}
