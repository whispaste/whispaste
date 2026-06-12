/// AC2 (issue 08): Dark/Light follows the system uniformly via
/// `platformBrightness` for BOTH floating surfaces (overlay + button).
///
/// The single shared resolver [resolveFloatingSurfaceIsDark] is the only path
/// both surfaces use, so they can never disagree. These tests pin its truth
/// table and the specific regression it fixes: the floating button used to map
/// `ThemeMode.system` to dark unconditionally (`themeMode != ThemeMode.light`),
/// which is wrong on a light-mode system.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_theme_brightness.dart';

void main() {
  group('resolveFloatingSurfaceIsDark — explicit modes ignore brightness', () {
    test('ThemeMode.dark is always dark', () {
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.dark,
          platformBrightness: Brightness.light,
        ),
        isTrue,
      );
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.dark,
          platformBrightness: Brightness.dark,
        ),
        isTrue,
      );
    });

    test('ThemeMode.light is always light', () {
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.light,
          platformBrightness: Brightness.dark,
        ),
        isFalse,
      );
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.light,
          platformBrightness: Brightness.light,
        ),
        isFalse,
      );
    });
  });

  group('resolveFloatingSurfaceIsDark — system follows platformBrightness', () {
    test('system + dark platform → dark', () {
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.system,
          platformBrightness: Brightness.dark,
        ),
        isTrue,
      );
    });

    test('system + light platform → light (the bug D5 fix)', () {
      // The old button logic `themeMode != ThemeMode.light` returned dark here.
      expect(
        resolveFloatingSurfaceIsDark(
          ThemeMode.system,
          platformBrightness: Brightness.light,
        ),
        isFalse,
      );
    });
  });

  test('the resolver disagrees with the old buggy button expression', () {
    // Documents exactly what was wrong: on a light-mode system, the old
    // `themeMode != ThemeMode.light` flagged the button as dark.
    bool oldButtonLogic(ThemeMode m) => m != ThemeMode.light;
    expect(oldButtonLogic(ThemeMode.system), isTrue); // wrong
    expect(
      resolveFloatingSurfaceIsDark(
        ThemeMode.system,
        platformBrightness: Brightness.light,
      ),
      isFalse, // correct
    );
  });
}
