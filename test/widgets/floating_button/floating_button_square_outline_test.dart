// The square floating button draws every outline as the rounded square: a
// circle left inside the square reads as a second, round button.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

/// Counts the circles a painter draws; every other call is ignored.
class _CircleCounter implements Canvas {
  int circles = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  for (final background in OverlayBackground.values) {
    test('square look draws no circle on ${background.name}', () {
      final painter = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        background: background,
        look: const FloatingButtonLook(square: true),
      );
      final canvas = _CircleCounter();
      painter.paint(canvas, const Size(120, 120));
      expect(canvas.circles, 0);
    });
  }
}
