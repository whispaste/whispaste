// BTN-REC: while recording, the floating button shows a stop square instead of
// the mic, the ring straddles the disc edge, both states keep the same footprint,
// and the ring stands out from the disc in every colour set (#369).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
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

  group('recording ring colour', () {
    final pairs = [
      for (final background in OverlayBackground.values)
        for (final wave in OverlayWave.values)
          if (wave.isValidOn(background)) (background, wave),
    ];

    test('the ring stands out from the disc in every colour set', () {
      for (final (background, wave) in pairs) {
        final spec = WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.recording,
          background: background,
          wave: wave,
        ).spec;
        expect(
          contrastRatio(spec.borderColor, spec.discColor),
          greaterThanOrEqualTo(3.0),
          reason: '${background.value}/${wave.value}',
        );
        expect(spec.borderWidth, OverlayDesignSpec.buttonRingWidth);
      }
    });

    test('on dark discs the ring also stands out from the backdrop', () {
      for (final (background, wave) in pairs) {
        if (background.tone != OverlayDesignTheme.dark) continue;
        final spec = WpFloatingButtonView.painterFor(
          state: FloatingButtonVisualState.recording,
          background: background,
          wave: wave,
        ).spec;
        expect(
          contrastRatio(spec.borderColor, OverlayDesignSpec.buttonRingBackdrop),
          greaterThanOrEqualTo(3.0),
          reason: '${background.value}/${wave.value}',
        );
      }
    });

    test('the idle button has no recording ring', () {
      final spec = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        background: OverlayBackground.amber,
        wave: OverlayWave.ink,
      ).spec;
      expect(spec.borderWidth, isNot(OverlayDesignSpec.buttonRingWidth));
    });
  });
}
