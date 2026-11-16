// Briefing B3 criterion 5: inserting text is never sending it. The native
// paste hosts must not post a Return or Enter keystroke on any platform.
// This is a source guard, because the keystroke code only runs on the
// real desktop; the Dart paths are covered in paster_test.dart.
//
// Auto-send (#564) is the one deliberate exception: `SendEnterKey` posts a
// plain Enter, only on an explicit request after a confirmed paste. Enter
// stays forbidden everywhere else, so the paste path itself never sends.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _enterKeys = RegExp(
  r'kVK_Return|kVK_ANSI_KeypadEnter|VK_RETURN|KEY_ENTER|KEY_KPENTER|XK_Return|XK_KP_Enter',
);

/// Drops the auto-send function body and the uinput key registration that
/// only exists to make it work.
String _withoutAutoSend(String source) {
  final body = RegExp(r'\bSendEnterKey\([^)]*\)[^{]*\{.*?\n\}\n', dotAll: true);
  return source
      .replaceAll(body, '')
      .replaceAll(RegExp(r'[^\n]*UI_SET_KEYBIT, KEY_ENTER\)[^\n]*'), '');
}

void main() {
  const pasteHosts = [
    'macos/Runner/DesktopPasteHost.swift',
    'windows/runner/desktop_paste_host.cpp',
    'linux/runner/desktop_paste_host.cc',
  ];

  for (final path in pasteHosts) {
    test('$path posts no Enter or Return key', () {
      final source = _withoutAutoSend(File(path).readAsStringSync());
      final hits = _enterKeys
          .allMatches(source)
          .map((m) => m.group(0))
          .toList();
      expect(hits, isEmpty, reason: 'Enter keystroke found in $path');
    });
  }
}
