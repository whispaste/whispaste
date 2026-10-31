import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// When Raw Input refuses the watched right Win key, the start-menu mask must
/// not stay on: the key is then no longer the trigger, and a Win tap has to
/// open the start menu again. The Linux host returns false without changing
/// state; the Windows host must reset the watch and the hook in the same way.
/// PAR-055.
void main() {
  test('watchModifier drops the Win mask when Raw Input refuses the key', () {
    final source = File(
      'windows/runner/keyboard_monitor_host.cpp',
    ).readAsStringSync();
    final start = source.indexOf('if (method == "watchModifier")');
    final end = source.indexOf('if (method == "armRelease")');
    expect(start, greaterThan(-1), reason: 'watchModifier branch not found');
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);

    // Comment lines may sit inside the refusal block; the reset must come
    // before the reply to Dart.
    final refusal = RegExp(
      r'const bool registered = EnsureRawInputRegistered\(\);\s*'
      r'if \(!registered\) \{\s*(//[^\n]*\n\s*)*'
      r'watched_mod_vk_ = 0;\s*UpdateMenuMaskHook\(\);\s*\}\s*'
      r'result->Success\(EncodableValue\(registered\)\);',
    );
    expect(
      refusal.hasMatch(branch),
      isTrue,
      reason:
          'after a refused EnsureRawInputRegistered() the watched key must be '
          'cleared and UpdateMenuMaskHook() called before the reply (PAR-055)',
    );
  });
}
