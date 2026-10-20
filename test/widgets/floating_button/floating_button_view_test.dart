/// Widget/painter tests for the shared floating-button renderer (issue 08).
///
/// Covers:
///  - AC1: the painter is sourced **only** from [OverlayDesignSpec] — disc
///    gradient, border, mic geometry and per-state tint wired by
///    [WpFloatingButtonView.painterFor] equal spec values, never a platform-local
///    constant. (Native-on-device pixel parity is issue 08b/hardware.)
///  - AC4: the done state tints the mic with the SSOT done gradient whose
///    middle stop is the canonical green `#30C065`.
///  - AC5: the three settings sizes (44/56/80) behave
///    identically; every state builds & paints without throwing.
///  - V2 fidelity: white disc, hairline border, NO glow.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

void main() {
  group('WpFloatingButtonView.painterFor — spec sourcing (AC1)', () {
    test(
      'disc follows the marine preset, mic geometry from OverlayDesignSpec',
      () {
        final painter = WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.idle,
        );
        expect(painter.spec.discColor, WpOverlayTokens.overlayMarineSurface);
        expect(painter.spec.mic, same(FloatingButtonMicSpec.spike));
        expect(painter.iconColor, WpOverlayTokens.overlayMarineInk);
      },
    );

    test('idle and disabled have a solid dark mic (no gradient)', () {
      for (final s in const [
        FloatingButtonVisualState.idle,
        FloatingButtonVisualState.disabled,
      ]) {
        expect(WpFloatingButtonView.painterFor(state: s).iconGradient, isNull);
      }
    });

    test('active states map to the signal glyph stops of their tone', () {
      expect(
        WpFloatingButtonView.iconGradientFor(
          FloatingButtonVisualState.recording,
          OverlayDesignSpec.colorsFor(),
        ),
        OverlayDesignSpec.glyphStopsFor(
          OverlayDesignState.recording,
          OverlayDesignSpec.colorsFor(),
        ),
      );
      expect(
        WpFloatingButtonView.designStateFor(
          FloatingButtonVisualState.transcribing,
        ),
        OverlayDesignState.transcribing,
      );
    });
  });

  group('done mic tint is the flat signal green (WP-75)', () {
    test(
      'the done mic tint is the dark-tone done signal on a dark background',
      () {
        final painter = WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.done,
        );
        expect(painter.iconGradient, isNotNull);
        expect(painter.iconGradient!, hasLength(2));
        expect(
          painter.iconGradient!.first,
          WpOverlayTokens.overlaySignalDarkDone,
        );
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

  group('window size reserves shadow padding around the disc', () {
    test('disc + 2 × shadowPadding on every side', () {
      for (final d in const [44.0, 56.0, 80.0]) {
        expect(OverlayDesignSpec.buttonWindowSize(d), Size(d + 16, d + 16));
      }
    });
  });

  group('WpFloatingButtonView — paints every state & size (AC5)', () {
    for (final state in FloatingButtonVisualState.values) {
      for (final size in const [44.0, 56.0, 80.0]) {
        testWidgets('${state.name} · ${size.toInt()}px builds & paints', (
          tester,
        ) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: WpFloatingButtonView(state: state, diameter: size),
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

  group('WpFloatingButtonPainter.shouldRepaint', () {
    test('repaints when state gradient changes', () {
      final idle = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
      );
      final done = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.done,
      );
      expect(idle.shouldRepaint(done), isTrue);
      expect(idle.shouldRepaint(idle), isFalse);
    });
  });
}
