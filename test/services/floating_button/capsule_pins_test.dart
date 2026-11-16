import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/idle_capsule.dart';

void main() {
  const screen = Rect.fromLTWH(0, 0, 1440, 900);
  const pill = Size(112, 28);
  const rest = Size(56, 20);

  Rect at(double x, double y, Size size) =>
      Rect.fromLTWH(x, y, size.width, size.height);

  test('a middle-of-screen capsule grows to the defaults', () {
    final pins = CapsulePins.resolve(
      home: at(600, 400, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: true,
    );
    expect(pins.pinnedRight, isFalse);
    expect(pins.pinnedBottom, isTrue);
  });

  test('near the right edge the pill grows leftwards', () {
    final pins = CapsulePins.resolve(
      home: at(1420 - 56, 400, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: true,
    );
    expect(pins.pinnedRight, isTrue);
  });

  test('near the bottom edge the pill grows upwards on macOS', () {
    final pins = CapsulePins.resolve(
      home: at(600, 900 - 20, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: true,
    );
    expect(pins.pinnedBottom, isTrue);
  });

  test('near the bottom edge the pill grows upwards on Windows and Linux', () {
    final pins = CapsulePins.resolve(
      home: at(600, 900 - 20, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: false,
    );
    expect(pins.pinnedBottom, isTrue);
  });

  test('near the top edge the pill grows downwards on Windows and Linux', () {
    final pins = CapsulePins.resolve(
      home: at(600, 0, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: false,
    );
    expect(pins.pinnedBottom, isFalse);
  });

  test('near the top edge the pill grows downwards on macOS too', () {
    final pins = CapsulePins.resolve(
      home: at(600, 0, rest),
      pill: pill,
      screen: screen,
      defaultPinsBottom: true,
    );
    expect(pins.pinnedBottom, isFalse);
  });

  test(
    'the rest size itself returns the defaults, so shrinking lands home',
    () {
      for (final defaultPinsBottom in [true, false]) {
        for (final home in [
          at(0, 0, rest),
          at(1440 - 56, 900 - 20, rest),
          at(600, 400, rest),
        ]) {
          final pins = CapsulePins.resolve(
            home: home,
            pill: rest,
            screen: screen,
            defaultPinsBottom: defaultPinsBottom,
          );
          expect(pins.pinnedRight, isFalse, reason: '$home');
          expect(pins.pinnedBottom, defaultPinsBottom, reason: '$home');
        }
      }
    },
  );
}
