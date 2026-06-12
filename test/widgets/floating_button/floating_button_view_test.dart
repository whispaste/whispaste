/// Widget/painter tests for the shared floating-button renderer (issue 08).
///
/// Covers:
///  - AC1: the painter is sourced **only** from [OverlayDesignSpec] — disc
///    gradient, border, mic geometry and per-state tint wired by
///    [FloatingButtonView.painterFor] equal spec values, never a platform-local
///    constant. (Native-on-device pixel parity is issue 08b/hardware.)
///  - AC4: the done state tints the mic with the SSOT done gradient whose
///    middle stop is the canonical green `#30C065`.
///  - AC5: the three settings sizes (44/56/80) and master opacity behave
///    identically; every state builds & paints without throwing.
///  - V2 fidelity: white disc, hairline border, NO glow.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

void main() {
  group('FloatingButtonView.painterFor — spec sourcing (AC1)', () {
    test('disc, border and mic geometry come from OverlayDesignSpec', () {
      final painter = FloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
      );
      expect(painter.spec, same(OverlayDesignSpec.button));
      expect(painter.spec.discColor, const Color(0xFFFFFFFF));
      expect(painter.spec.discGradientEnd, const Color(0xFFEDF1F6));
      expect(painter.spec.borderColor, const Color(0x1A101828));
      expect(painter.spec.mic, same(FloatingButtonMicSpec.spike));
      expect(painter.iconColor, OverlayDesignSpec.button.iconColor);
    });

    test('V2 fidelity — no glow', () {
      expect(OverlayDesignSpec.button.hasGlow, isFalse);
    });

    test('idle and disabled have a solid dark mic (no gradient)', () {
      for (final s in const [
        FloatingButtonVisualState.idle,
        FloatingButtonVisualState.disabled,
      ]) {
        expect(FloatingButtonView.painterFor(state: s).iconGradient, isNull);
      }
    });

    test('active states map to the SSOT state gradients', () {
      expect(
        FloatingButtonView.iconGradientFor(FloatingButtonVisualState.recording),
        OverlayDesignSpec.stateGradients[OverlayDesignState.recording]!.stops,
      );
      expect(
        FloatingButtonView.designStateFor(
          FloatingButtonVisualState.transcribing,
        ),
        OverlayDesignState.transcribing,
      );
    });
  });

  group('done-gradient middle stop is #30C065 (AC4)', () {
    test(
      'the done mic tint carries the canonical green as its middle stop',
      () {
        final painter = FloatingButtonView.painterFor(
          state: FloatingButtonVisualState.done,
        );
        expect(painter.iconGradient, isNotNull);
        expect(painter.iconGradient!, hasLength(3));
        expect(painter.iconGradient![1], const Color(0xFF30C065));
      },
    );
  });

  group('mic geometry scales with the disc (spec ratios, AC5)', () {
    test(
      'at the 56px reference disc the spike pixel values are reproduced',
      () {
        const mic = FloatingButtonMicSpec.spike;
        expect(mic.bodyWidthRatio * 56, closeTo(9, 1e-9));
        expect(mic.bodyHeightRatio * 56, closeTo(14, 1e-9));
        expect(mic.bodyRadiusRatio * 56, closeTo(4.5, 1e-9));
        expect(mic.strokeRatio * 56, closeTo(2, 1e-9));
        expect(mic.stemBottomDyRatio * 56, closeTo(11, 1e-9));
      },
    );
  });

  group('master opacity flows straight through (AC5)', () {
    test('opacity is passed to the painter (disc-chrome-only dimming)', () {
      final painter = FloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        opacity: 0.7,
      );
      expect(painter.masterOpacity, 0.7);
    });
  });

  group('window size reserves shadow padding around the disc', () {
    test('disc + 2 × shadowPadding on every side', () {
      for (final d in const [44.0, 56.0, 80.0]) {
        expect(OverlayDesignSpec.buttonWindowSize(d), Size(d + 16, d + 16));
      }
    });
  });

  group('FloatingButtonView — paints every state & size (AC5)', () {
    for (final state in FloatingButtonVisualState.values) {
      for (final size in const [44.0, 56.0, 80.0]) {
        testWidgets('${state.name} · ${size.toInt()}px builds & paints', (
          tester,
        ) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: FloatingButtonView(
                  state: state,
                  diameter: size,
                  opacity: 0.9,
                ),
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(CustomPaint), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('FloatingButtonPainter.shouldRepaint', () {
    test('repaints when state gradient or opacity changes', () {
      final idle = FloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
      );
      final done = FloatingButtonView.painterFor(
        state: FloatingButtonVisualState.done,
      );
      final idleDim = FloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        opacity: 0.5,
      );
      expect(idle.shouldRepaint(done), isTrue);
      expect(idle.shouldRepaint(idleDim), isTrue);
      expect(idle.shouldRepaint(idle), isFalse);
    });
  });
}
