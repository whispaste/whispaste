// Parity guard PAR-034 (Linux paste and copy keys follow the keyboard layout).
//
// uinput sends evdev key positions, and the X server or the Wayland compositor
// maps them through the active layout. A fixed KEY_V therefore types another
// letter on Dvorak-like layouts, so Ctrl+KEY_V does not paste there. macOS
// resolves the letter per layout (briefing N7, commit abe852de6). The Linux
// runner must resolve the evdev code of "v" and "c" from the GDK keymap, and
// it must register every letter key on the virtual device, because the kernel
// drops key events for keys that were never registered.
//
// Static check: it proves the lookup and the registration exist in the source,
// not that Ctrl+V pastes on a Dvorak session (runtime check, Stufe C).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const runner = 'linux/runner/desktop_paste_host.cc';
  const header = 'linux/runner/desktop_paste_host.h';
  late String source;
  late String headerSource;

  setUpAll(() {
    source = File(runner).readAsStringSync();
    headerSource = File(header).readAsStringSync();
  });

  test('paste and copy resolve their letter through the GDK keymap', () {
    expect(source, contains('gdk_keymap_get_entries_for_keyval'));
    expect(
      source,
      contains('LetterKeycode(GDK_KEY_v, KEY_V)'),
      reason: 'paste must follow the letter "v" on the active layout',
    );
    expect(
      source,
      contains('LetterKeycode(GDK_KEY_c, KEY_C)'),
      reason: 'copySelection must follow the letter "c" on the active layout',
    );
    expect(headerSource, contains('int LetterKeycode('));
  });

  test('no fixed V or C position is sent any more', () {
    expect(
      RegExp(r'SendCtrlShortcut\(KEY_[VC]\)').hasMatch(source),
      isFalse,
      reason: 'a fixed evdev position types another letter on Dvorak',
    );
  });

  test('every letter key is registered on the virtual device', () {
    expect(
      RegExp(
        r'kLetterKeys\[\] = \{[^}]*KEY_A[^}]*KEY_Z[^}]*\};',
      ).hasMatch(source),
      isTrue,
      reason: 'kLetterKeys must list KEY_A..KEY_Z',
    );
    expect(
      source,
      contains('for (const int key : kLetterKeys)'),
      reason: 'EnsureUinputDevice must register each letter key',
    );
    expect(source, contains('ioctl(fd, UI_SET_KEYBIT, key)'));
  });
}
