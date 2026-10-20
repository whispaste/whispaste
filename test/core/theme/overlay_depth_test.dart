/// Depth of the overlay pill and floating button on a dark desktop (UX-048,
/// maintainer decision 6a+b). Dark presets get a 1 px light outer edge and a
/// stronger painted shadow; light presets keep the shadow and get no edge.
/// Both come from tokens and reach the painters through the resolved colours.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('edge (UX-048)', () {
    test('dark presets carry a translucent light edge from their token', () {
      expect(OverlayBackground.marine.edge, WpOverlayTokens.overlayMarineEdge);
      expect(
        OverlayBackground.graphit.edge,
        WpOverlayTokens.overlayGraphitEdge,
      );
      for (final background in [
        OverlayBackground.marine,
        OverlayBackground.graphit,
      ]) {
        expect(background.edge.a, greaterThan(0), reason: background.value);
        expect(background.edge.a, lessThan(1), reason: background.value);
        expect(background.edge.r, 1.0, reason: background.value);
      }
    });

    test('light presets draw no edge', () {
      expect(OverlayBackground.gletscher.edge.a, 0);
      expect(OverlayBackground.amber.edge.a, 0);
    });

    test('the edge reaches the resolved colours and the button spec', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.marine,
      );
      expect(colors.edge, OverlayBackground.marine.edge);
      final spec = OverlayDesignSpec.buttonSpecFor(colors);
      expect(spec.edgeColor, colors.edge);
    });
  });

  group('shadow (UX-048)', () {
    test('the dark tone shadow is stronger than the light tone shadow', () {
      final dark = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.marine,
      ).shadow;
      final light = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.gletscher,
      ).shadow;
      expect(dark, WpOverlayTokens.overlayShadowDark);
      expect(light, WpOverlayTokens.overlayShadowLight);
      expect(dark.a, greaterThan(light.a));
    });

    test('the light shadow keeps the previous 20 percent', () {
      expect(WpOverlayTokens.overlayShadowLight.a, closeTo(0.2, 0.005));
    });

    test('the button spec carries the same shadow as the pill', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.graphit,
      );
      expect(
        OverlayDesignSpec.buttonSpecFor(colors).shadowColor,
        colors.shadow,
      );
    });
  });
}
