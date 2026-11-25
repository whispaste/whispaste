/// The copy button names the key that actually copies: Cmd on macOS, where
/// the copy handler ignores Ctrl (#1845). The label showed "⌃ C" there.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the copy tooltip uses the platform command key', () {
    final src = File(
      'lib/features/history/widgets/history_detail_panel.dart',
    ).readAsStringSync();
    expect(src, isNot(contains("formatHotkeyShortcut('ctrl', 'c'")));
    expect(src, contains("commandShortcutLabel('C', l10n: l10n)"));
  });
}
