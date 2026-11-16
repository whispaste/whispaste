import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

void main() {
  group('idle face of the floating button (#483)', () {
    test('only the idle state shows the wave mark, in the ink colour', () {
      for (final s in FloatingButtonVisualState.values) {
        final painter = WpFloatingButtonView.painterFor(state: s);
        final idle = s == FloatingButtonVisualState.idle;
        expect(painter.markAlpha, idle ? 1 : 0, reason: '$s');
        expect(WpFloatingButtonView.showsMark(s), idle, reason: '$s');
        // The disc never paints mark and mic on top of each other.
        expect(painter.glyphAlpha, idle ? 0 : 1, reason: '$s');
      }
    });

    test('capsule swaps mark and mic without showing both', () {
      expect(WpFloatingButtonView.capsuleFaces(0), (1.0, 0.0));
      expect(WpFloatingButtonView.capsuleFaces(1), (0.0, 1.0));
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final (mark, mic) = WpFloatingButtonView.capsuleFaces(t);
        expect(mark > 0 && mic > 0, isFalse, reason: 't=$t');
      }
    });
  });
}
