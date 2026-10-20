/// Start and restore placement must stay inside the work area (screen minus
/// taskbar, Dock and menu bar). A window that starts taller than the work
/// area hides its bottom edge (the dictation dock) behind the taskbar.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/window_position_clamp.dart';

void main() {
  // 1920x1080 screen with a 70 px taskbar at the bottom.
  const primaryWork = Rect.fromLTWH(0, 0, 1920, 1010);
  const secondaryWork = Rect.fromLTWH(1920, 0, 1280, 720);
  const minimum = Size(800, 600);

  group('WindowPositionClamp.place', () {
    test('caps a window taller than the work area to the work area', () {
      final placed = WindowPositionClamp.place(
        size: const Size(1100, 1100),
        minimum: minimum,
        displays: const [primaryWork],
        primary: primaryWork,
      );

      expect(placed.size.height, primaryWork.height);
      expect(placed.size.width, 1100);
    });

    test('raises a window below the minimum size to the minimum', () {
      final placed = WindowPositionClamp.place(
        size: const Size(700, 500),
        minimum: minimum,
        displays: const [primaryWork],
        primary: primaryWork,
      );

      expect(placed.size, minimum);
    });

    test('a minimum taller than the work area is capped to the work area', () {
      final placed = WindowPositionClamp.place(
        size: const Size(1100, 750),
        minimum: const Size(800, 1200),
        displays: const [primaryWork],
        primary: primaryWork,
      );

      expect(placed.size.height, primaryWork.height);
    });

    test('centers a fresh window inside the primary work area', () {
      const size = Size(1100, 800);
      final placed = WindowPositionClamp.place(
        size: size,
        minimum: minimum,
        displays: const [primaryWork, secondaryWork],
        primary: primaryWork,
      );

      expect(placed.position, const Offset(410, 105));
      expect(placed.position!.dy + size.height, lessThanOrEqualTo(1010));
    });

    test('centers below a menu bar that shifts the work area top', () {
      const work = Rect.fromLTWH(0, 40, 1920, 1000);
      final placed = WindowPositionClamp.place(
        size: const Size(1100, 800),
        minimum: minimum,
        displays: const [work],
        primary: work,
      );

      expect(placed.position!.dy, greaterThanOrEqualTo(work.top));
      expect(placed.position!.dy + 800, lessThanOrEqualTo(work.bottom));
    });

    test('a stored position is fitted to the work area it lands on', () {
      // Stored on the secondary display, which is now smaller than the
      // window's stored size.
      final placed = WindowPositionClamp.place(
        position: const Offset(2000, 100),
        size: const Size(1100, 900),
        minimum: minimum,
        displays: const [primaryWork, secondaryWork],
        primary: primaryWork,
      );

      expect(placed.size.height, secondaryWork.height);
      expect(placed.position!.dx, greaterThanOrEqualTo(secondaryWork.left));
      expect(
        placed.position!.dx + placed.size.width,
        lessThanOrEqualTo(secondaryWork.right),
      );
      expect(
        placed.position!.dy + placed.size.height,
        lessThanOrEqualTo(secondaryWork.bottom),
      );
    });

    test('without any display info only the minimum is applied', () {
      final placed = WindowPositionClamp.place(
        position: const Offset(10, 20),
        size: const Size(700, 500),
        minimum: minimum,
        displays: const [],
      );

      expect(placed.size, minimum);
      expect(placed.position, const Offset(10, 20));
    });
  });
}
