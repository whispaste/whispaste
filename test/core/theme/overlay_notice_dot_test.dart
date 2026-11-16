// The notice card's status dot keeps its meaning on every background
// (overlay F2): an error is red and a hint amber, never the plain ink, each
// at 3:1 on the card's opaque body. Glass once fell back to white for both.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  const reds = [
    WpOverlayTokens.overlaySignalDarkError,
    WpOverlayTokens.overlaySignalLightError,
    WpPalette.red400,
    WpPalette.red800,
  ];
  const ambers = [
    WpOverlayTokens.overlaySignalDarkTranscribing,
    WpOverlayTokens.overlaySignalLightTranscribing,
    WpPalette.amber400,
    WpPalette.amber800,
  ];

  for (final background in OverlayBackground.values) {
    for (final glassTone in OverlayDesignTheme.values) {
      if (background != OverlayBackground.glass &&
          glassTone != OverlayDesignTheme.dark) {
        continue;
      }
      final name = background == OverlayBackground.glass
          ? 'glass-${glassTone.name}'
          : background.value;

      test('$name: error dot is red and hint dot amber, both legible', () {
        final colors = OverlayDesignSpec.colorsFor(
          background: background,
          glassTone: glassTone,
        );
        expect(reds, contains(colors.noticeErrorDot));
        expect(ambers, contains(colors.noticeHintDot));
        expect(
          contrastRatio(colors.noticeErrorDot, colors.opaqueFill),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          contrastRatio(colors.noticeHintDot, colors.opaqueFill),
          greaterThanOrEqualTo(3.0),
        );
      });
    }
  }
}
