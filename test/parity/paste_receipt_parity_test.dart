// Parity guard GR-015, PAR-032, PAR-033 and XP-7-14 (paste proof and target
// check on all three desktop platforms).
//
// - GR-015: every desktop controller proves a paste through a clipboard read
//   receipt. Linux serves the transcript per X selection request
//   (linux/runner/clipboard_receipt.cc), like delayed rendering on Windows and
//   the pasteboard data provider on macOS.
// - PAR-032: the paste only goes to the captured target. macOS refuses a
//   switched target, Windows and Linux (X11) bring it back first and refuse
//   when that fails.
// - PAR-033: without a receipt nothing is restored; the transcript stays on
//   the clipboard on every platform.
// - XP-7-14: the Linux paste delay does not block the GTK main thread, which
//   also serves the selection requests the receipt depends on.
//
// Static check: it proves the paths exist in the source, not that a paste
// lands (runtime: test/scripts/clipboard_receipt_test.sh and the E2E runs).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/windows_desktop_paste_controller.dart';

/// Body of the C++ function whose definition starts with [signature].
String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature not found');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(open, i + 1);
  }
  fail('unbalanced braces after $signature');
}

void main() {
  late String linuxHost;

  setUpAll(() {
    linuxHost = File('linux/runner/desktop_paste_host.cc').readAsStringSync();
  });

  test('every desktop controller offers the receipt bridge (GR-015)', () {
    expect(MacOSDesktopPasteController(), isA<ClipboardReceiptBridge>());
    expect(WindowsDesktopPasteController(), isA<ClipboardReceiptBridge>());
    expect(LinuxDesktopPasteController(), isA<ClipboardReceiptBridge>());
  });

  test('every platform saves and restores the full clipboard (P1.1)', () {
    expect(MacOSDesktopPasteController(), isA<ClipboardSnapshotBridge>());
    expect(WindowsDesktopPasteController(), isA<ClipboardSnapshotBridge>());
    expect(LinuxDesktopPasteController(), isA<ClipboardSnapshotBridge>());
    final hosts = {
      'macOS': File('macos/Runner/DesktopPasteHost.swift').readAsStringSync(),
      'Windows': File(
        'windows/runner/desktop_paste_host.cpp',
      ).readAsStringSync(),
      'Linux': linuxHost,
    };
    for (final MapEntry(key: platform, value: source) in hosts.entries) {
      for (final method in [
        'snapshotClipboard',
        'restoreClipboardSnapshotIfOwner',
        'discardClipboardSnapshot',
      ]) {
        expect(
          source,
          contains('"$method"'),
          reason: '$platform host handles $method',
        );
      }
    }
  });

  test('the Linux receipt is built and runtime-tested in CI', () {
    expect(
      File('linux/runner/CMakeLists.txt').readAsStringSync(),
      contains('"clipboard_receipt.cc"'),
    );
    expect(
      File('.github/workflows/ci.yml').readAsStringSync(),
      contains('bash test/scripts/clipboard_receipt_test.sh'),
    );
  });

  test('only a read after the shortcut counts on Linux, as on Windows', () {
    final tick = _body(linuxHost, 'bool DesktopPasteHost::PasteTick()');
    final send = tick.indexOf('SendShortcut(');
    final mark = tick.indexOf('receipt_->MarkKeystrokePosted()');
    expect(send, isNonNegative);
    expect(
      mark,
      greaterThan(send),
      reason: 'mark only a shortcut that went out',
    );
  });

  test("WhisPaste's own Linux clipboard reads are no receipt", () {
    // GTK answers a read from the owning process through the receipt's own
    // get callback; the side panel snapshot must not count as the paste.
    final sidePanel = File(
      'linux/runner/side_panel_host.cc',
    ).readAsStringSync();
    expect(
      _body(sidePanel, 'void SidePanelHost::EmitClipboardSnapshot()'),
      contains('ClipboardReceipt::ScopedSelfRead'),
    );
  });

  test('the Linux paste checks the captured X11 target (PAR-032)', () {
    final start = _body(linuxHost, 'void DesktopPasteHost::StartPaste(');
    expect(start, contains('X11ActiveWindow(display) == target_window_'));
    expect(start, contains('X11RequestActivation(display, target_window_)'));
    expect(start, contains('"target_changed"'));
    final tick = _body(linuxHost, 'bool DesktopPasteHost::PasteTick()');
    expect(tick, contains('"target_changed"'));
    // macOS refuses, Windows brings the target back: both check it.
    expect(
      File('macos/Runner/DesktopPasteHost.swift').readAsStringSync(),
      contains('"target_changed"'),
    );
    expect(
      File('windows/runner/desktop_paste_host.cpp').readAsStringSync(),
      contains('BringTargetToForeground()'),
    );
  });

  test('the Linux paste delay never blocks the main thread (XP-7-14)', () {
    for (final signature in [
      'void DesktopPasteHost::StartPaste(',
      'bool DesktopPasteHost::PasteTick()',
    ]) {
      expect(_body(linuxHost, signature), isNot(contains('sleep_for')));
    }
    expect(linuxHost, contains('g_timeout_add(kPastePollMs, OnPasteTick'));
  });

  test('nothing is restored without a receipt (PAR-033)', () {
    final paster = File(
      'lib/services/paste/desktop_paster.dart',
    ).readAsStringSync();
    final end = paster.indexOf('return _unarmedReceiptOutcome();');
    final start = paster.lastIndexOf('if (receipts == null) {', end);
    expect(start, isNonNegative);
    // Code only: the comments in this branch name the restore they skip.
    final code = paster
        .substring(start, end)
        .split('\n')
        .where((line) => !line.trim().startsWith('//'))
        .join('\n');
    expect(code, isNot(contains('estore')));
  });
}
