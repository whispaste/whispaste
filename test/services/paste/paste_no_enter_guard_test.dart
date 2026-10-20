// Briefing B3 criterion 5: inserting text is never sending it. The native
// paste hosts must not post a Return or Enter keystroke on any platform.
// This is a source guard, because the keystroke code only runs on the
// real desktop; the Dart paths are covered in paster_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _enterKeys = RegExp(
  r'kVK_Return|kVK_ANSI_KeypadEnter|VK_RETURN|KEY_ENTER|KEY_KPENTER|XK_Return|XK_KP_Enter',
);

void main() {
  const pasteHosts = [
    'macos/Runner/DesktopPasteHost.swift',
    'windows/runner/desktop_paste_host.cpp',
    'linux/runner/desktop_paste_host.cc',
  ];

  for (final path in pasteHosts) {
    test('$path posts no Enter or Return key', () {
      final source = File(path).readAsStringSync();
      final hits = _enterKeys
          .allMatches(source)
          .map((m) => m.group(0))
          .toList();
      expect(hits, isEmpty, reason: 'Enter keystroke found in $path');
    });
  }
}
