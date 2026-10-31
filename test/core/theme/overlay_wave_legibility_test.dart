/// Wave legibility on the light surfaces (WP-75b). A wave keeps its own hue
/// whenever some step of that hue reaches 3:1 on the fill. An invalid pairing
/// is disabled in the UI instead (see overlay_wave_validity_test.dart).
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('every valid light-tone wave pairing', () {
    for (final background in OverlayBackground.values) {
      if (background.tone != OverlayDesignTheme.light) continue;
      for (final wave in OverlayWave.values) {
        if (!wave.isValidOn(background)) continue;
        test('${wave.value} on ${background.value} reaches 3:1', () {
          final colors = OverlayThemeColors.resolve(
            background: background,
            wave: wave,
          );
          expect(
            _contrast(colors.accent, background.surfaceStart),
            greaterThanOrEqualTo(3.0),
          );
        });
      }
    }
  });
}
