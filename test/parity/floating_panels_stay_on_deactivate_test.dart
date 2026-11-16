// Floating panels stay on screen when the app loses activation (#484).
//
// NSPanel hides on deactivate by default, unlike NSWindow. The button and the
// overlay must stay visible while the user works in another app, so both
// panels have to opt out. Windows and Linux have no such default.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in const [
    'macos/Runner/FloatingButtonWindow.swift',
    'macos/Runner/FloatingOverlayWindow.swift',
  ]) {
    test('$path opts out of hiding on deactivate', () {
      expect(
        File(path).readAsStringSync(),
        contains('hidesOnDeactivate = false'),
      );
    });
  }
}
