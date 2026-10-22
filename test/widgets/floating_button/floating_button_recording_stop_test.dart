// BTN-REC: while recording, the floating button shows a stop square instead of
// the mic, the ring sits outside the disc, both states keep the same footprint,
// and the ring colour is checked against the stage backdrop (>= 3:1).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors_dark.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

Widget _host(Widget child) => Localizations(
  locale: const Locale('de'),
  delegates: const [L10n.delegate, DefaultWidgetsLocalizations.delegate],
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  group('recording glyph', () {
    test('recording paints the stop square, idle keeps the mic', () {
      expect(
        WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.recording,
        ).stopSquare,
        isTrue,
      );
      expect(
        WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.idle,
        ).stopSquare,
        isFalse,
      );
    });

    test('the stop square is a visible share of the disc', () {
      expect(
        OverlayDesignSpec.buttonStopSquareRatio,
        inInclusiveRange(0.2, 0.5),
      );
    });

    testWidgets('recording exposes the stop label to assistive tech', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const WpFloatingButtonView(
            state: FloatingButtonVisualState.recording,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Aufnahme beenden'), findsOneWidget);
    });
  });

  group('ring', () {
    final colors = OverlayDesignSpec.colorsFor();

    test('ring is painted outside the disc edge at the same line width', () {
      final spec = OverlayDesignSpec.buttonSpecFor(colors, ringed: true);
      expect(spec.borderWidth, 2.0);
      // Outer edge radius measured from the disc centre: stroke centre sits at
      // r - borderInset, half the stroke width lies beyond it.
      final outerEdge = -spec.borderInset + spec.borderWidth / 2;
      expect(outerEdge, greaterThan(0));
      expect(outerEdge, lessThanOrEqualTo(OverlayDesignSpec.shadowPadding));
    });

    test('ring colour reaches 3:1 against the stage backdrop', () {
      const backdrop = WpColorsDark.background;
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          if (!wave.isValidOn(background)) continue;
          final spec = OverlayDesignSpec.buttonSpecFor(
            OverlayDesignSpec.colorsFor(background: background, wave: wave),
            ringed: true,
          );
          expect(
            contrastRatio(spec.borderColor, backdrop),
            greaterThanOrEqualTo(3.0),
            reason: '${background.value}/${wave.value}',
          );
        }
      }
    });

    testWidgets('idle and recording keep the same footprint', (tester) async {
      Size sizeOf(FloatingButtonVisualState state) {
        return tester.getSize(
          find.descendant(
            of: find.byType(WpFloatingButtonView),
            matching: find.byType(CustomPaint),
          ),
        );
      }

      await tester.pumpWidget(
        _host(
          const WpFloatingButtonView(state: FloatingButtonVisualState.idle),
        ),
      );
      final idle = sizeOf(FloatingButtonVisualState.idle);

      await tester.pumpWidget(
        _host(
          const WpFloatingButtonView(
            state: FloatingButtonVisualState.recording,
          ),
        ),
      );
      final recording = sizeOf(FloatingButtonVisualState.recording);

      expect(recording, idle);
      expect(recording, OverlayDesignSpec.buttonWindowSize(56));
    });
  });
}
