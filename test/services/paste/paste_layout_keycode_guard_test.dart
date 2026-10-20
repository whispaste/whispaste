// Briefing N7: the macOS paste and copy shortcuts must resolve the key by its
// character on the active keyboard layout. Virtual keycode 9 is the ANSI
// physical position of "V", which types another letter on Dvorak and other
// layouts, so the shortcut would silently do something else.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('macos/Runner/DesktopPasteHost.swift').readAsStringSync();

  test(
    'macOS resolves the V and C shortcut keys by character, not position',
    () {
      expect(source, contains('func keyCode(forCharacter'));
      expect(source, isNot(contains('keyCode: 0x09)')));
      expect(source, isNot(contains('keyCode: 0x08)')));
    },
  );
}
