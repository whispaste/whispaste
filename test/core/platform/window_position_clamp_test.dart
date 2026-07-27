/// Multi-monitor clamp tests (audit finding: main window / floating button
/// position restored without any bounds check could start off every
/// currently connected display after a monitor was unplugged).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/window_position_clamp.dart';

void main() {
  const size = Size(56, 56);
  const primary = Rect.fromLTWH(0, 0, 1920, 1080);
  const secondary = Rect.fromLTWH(1920, 0, 1280, 720);

  group('WindowPositionClamp.clamp', () {
    test('leaves an on-screen position untouched', () {
      const position = Offset(100, 100);
      final result = WindowPositionClamp.clamp(
        position: position,
        size: size,
        displays: const [primary],
      );
      expect(result, position);
    });

    test('clamps a position off every display back onto the nearest one', () {
      // Saved on a 3rd monitor to the left of the primary — now unplugged.
      const stale = Offset(-2000, 200);
      final result = WindowPositionClamp.clamp(
        position: stale,
        size: size,
        displays: const [primary, secondary],
      );
      expect(result.dx, greaterThanOrEqualTo(primary.left));
      expect(result.dx + size.width, lessThanOrEqualTo(primary.right));
      expect(result.dy, greaterThanOrEqualTo(primary.top));
      expect(result.dy + size.height, lessThanOrEqualTo(primary.bottom));
    });

    test('picks the display the window center actually falls on', () {
      const onSecondary = Offset(2000, 100);
      final result = WindowPositionClamp.clamp(
        position: onSecondary,
        size: size,
        displays: const [primary, secondary],
      );
      expect(result, onSecondary);
    });

    test('clamps a partially off-screen position back within its display', () {
      const partiallyOff = Offset(1900, 100);
      final result = WindowPositionClamp.clamp(
        position: partiallyOff,
        size: size,
        displays: const [primary],
      );
      expect(result.dx + size.width, lessThanOrEqualTo(primary.right));
    });

    test('returns the position unchanged when no displays are known', () {
      const position = Offset(-500, -500);
      final result = WindowPositionClamp.clamp(
        position: position,
        size: size,
        displays: const [],
      );
      expect(result, position);
    });

    test('pins to the top-left in-margin corner when the display is smaller '
        'than the window', () {
      const tinyDisplay = Rect.fromLTWH(0, 0, 40, 40);
      final result = WindowPositionClamp.clamp(
        position: const Offset(1000, 1000),
        size: size,
        displays: const [tinyDisplay],
      );
      expect(result, const Offset(0, 0));
    });
  });
}
