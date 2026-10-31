// Parity guard W-E1 (secure input before a paste).
//
// - macOS asks the system whether secure input is on (IsSecureEventInputEnabled)
//   before any synthetic paste, and the Dart paster then skips the attempt.
// - Windows and Linux have no such system flag. Their controllers get
//   MissingPluginException, report SecureInputState.unsupported, and the paste
//   runs as before. That gap is documented in platform_channel_parity_test.dart
//   and CONTEXT.md §2.7, never a silent no-op.
//
// Static check: it proves the paths exist in the source, not that a secure
// field blocks a real paste (runtime: the manual check on a password field).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS answers the secure input probe from the system flag', () {
    final host = File('macos/Runner/DesktopPasteHost.swift').readAsStringSync();
    expect(host, contains('case "secureInputState":'));
    expect(host, contains('IsSecureEventInputEnabled()'));
  });

  test('the Dart controller asks the same channel method and maps a missing '
      'handler to unsupported', () {
    final controller = File(
      'lib/services/desktop_paste/channel_desktop_paste_controller.dart',
    ).readAsStringSync();
    expect(controller, contains("invokeMethod<String>('secureInputState')"));
    expect(controller, contains('on MissingPluginException {'));
    expect(controller, contains('return SecureInputState.unsupported;'));
  });

  test('macOS names the secure input holder from the session dictionary, '
      'without a shell-out', () {
    final host = File('macos/Runner/DesktopPasteHost.swift').readAsStringSync();
    expect(host, contains('case "secureInputHolder":'));
    expect(host, contains('CGSessionCopyCurrentDictionary()'));
    expect(host, contains('kCGSSessionSecureInputPID'));
    expect(host, contains('NSRunningApplication(processIdentifier:'));
    expect(host.toLowerCase(), isNot(contains('ioreg')));
  });

  test('the Dart controller asks the holder method and maps a missing '
      'handler (Windows, Linux) to no holder', () {
    final controller = File(
      'lib/services/desktop_paste/channel_desktop_paste_controller.dart',
    ).readAsStringSync();
    expect(controller, contains('invokeMapMethod<String, Object?>('));
    expect(controller, contains("'secureInputHolder',"));
  });

  test('the paster checks secure input before any paste attempt', () {
    final paster = File(
      'lib/services/paste/desktop_paster.dart',
    ).readAsStringSync();
    final check = paster.indexOf('await _secureInputActive()');
    final armed = paster.indexOf('_armReceipt(text)');
    final pasteCall = paster.indexOf('_controller.pasteClipboard(');
    expect(check, isNonNegative);
    expect(check, lessThan(armed));
    expect(check, lessThan(pasteCall));
  });
}
