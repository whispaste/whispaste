/// Contrast guard for every overlay pill state × background preset × wave
/// preset (UX-013, WP-75, ADR 0024).
///
/// Every pill renders on an opaque preset fill. The glyph ink must reach WCAG
/// AA (>= 4.5:1) on every stop of that fill, and the semantic status colours
/// and the wave must reach the non-text minimum (>= 3:1). Because the fill is
/// opaque, this holds over any desktop.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';

double _luminance(Color c) {
  double lin(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final background in OverlayBackground.values) {
    for (final wave in OverlayWave.values) {
      for (final state in OverlayDesignState.values) {
        final label = '${state.name} × ${background.value} × ${wave.value}';

        test('overlay pill contrast: $label', () {
          // Invalid pairs are disabled in the picker and never rendered; the
          // guard checks the wave that actually renders (ADR 0024).
          final colors = OverlayDesignSpec.colorsFor(
            background: background,
            wave: wave.validOn(background),
          );
          final stops = [colors.capsuleFill];
          final statuses = [
            colors.accent,
            colors.transcribingAccent,
            colors.success,
            colors.error,
            ...OverlayDesignSpec.glyphStopsFor(state, colors),
          ];

          for (final stop in stops) {
            expect(
              _contrast(colors.ink, stop),
              greaterThanOrEqualTo(4.5),
              reason: 'glyph ink on $stop ($label)',
            );
            for (final status in statuses) {
              expect(
                _contrast(status, stop),
                greaterThanOrEqualTo(3.0),
                reason: 'status $status on $stop ($label)',
              );
            }
          }
        });
      }
    }
  }
}
