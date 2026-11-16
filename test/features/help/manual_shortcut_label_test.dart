// UIA-HLP-03: the shortcut reference names the platform's own modifier.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/help/manual/manual_chapters.dart';

void main() {
  test('macOS shows Cmd, Windows and Linux show Ctrl (UIA-HLP-03)', () {
    expect(mainShortcutLabel('F', mac: true), 'Cmd+F');
    expect(mainShortcutLabel('N', mac: true), 'Cmd+N');
    expect(mainShortcutLabel('F', mac: false), 'Ctrl+F');
    expect(mainShortcutLabel('N', mac: false), 'Ctrl+N');
  });
}
