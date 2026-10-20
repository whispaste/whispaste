// WP-95 floating button look: the shape, recording ring and resting opacity
// reach the painter and the widget (no pixel comparison here; see the golden
// test next to this file).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

void main() {
  group('painterFor', () {
    test('square look sets the rounded-square shape', () {
      final painter = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        look: const FloatingButtonLook(square: true),
      );
      expect(painter.square, isTrue);
    });

    test('round look is the default disc', () {
      final painter = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
      );
      expect(painter.square, isFalse);
    });

    test('recording draws the coloured ring only when the ring is on', () {
      final withRing = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.recording,
      );
      final noRing = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.recording,
        look: const FloatingButtonLook(ring: false),
      );
      expect(withRing.spec.borderWidth, 2.0);
      expect(noRing.spec.borderWidth, isNot(2.0));
    });

    test('ring setting has no effect while idle', () {
      final painter = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        look: const FloatingButtonLook(ring: true),
      );
      expect(painter.spec.borderWidth, isNot(2.0));
    });

    test('the square corner ratio stays inside the disc', () {
      expect(
        OverlayDesignSpec.buttonSquareCornerRatio,
        inInclusiveRange(0.0, 1.0),
      );
    });
  });

  group('resting opacity', () {
    Widget build(FloatingButtonVisualState state, FloatingButtonLook look) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: WpFloatingButtonView(state: state, look: look),
        );

    testWidgets('idle uses the resting opacity', (tester) async {
      await tester.pumpWidget(
        build(
          FloatingButtonVisualState.idle,
          const FloatingButtonLook(idleOpacity: '40'),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WpFloatingButtonView),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, closeTo(0.4, 1e-9));
    });

    testWidgets('recording is always fully opaque', (tester) async {
      await tester.pumpWidget(
        build(
          FloatingButtonVisualState.recording,
          const FloatingButtonLook(idleOpacity: '40'),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WpFloatingButtonView),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });
  });

  testWidgets('the square window size equals the round one', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WpFloatingButtonView(
            state: FloatingButtonVisualState.idle,
            diameter: 80,
            look: FloatingButtonLook(square: true, idleOpacity: '70'),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(WpFloatingButtonView));
    expect(size, OverlayDesignSpec.buttonWindowSize(80));
  });
}
