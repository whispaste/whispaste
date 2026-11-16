// Logic tests for the glass overlay look (business logic only, no pixels).
//
// Covers: the preset is persisted and resolved, the glass flag reaches the
// colour set, the ink follows the glass tone, and the glyphs keep WCAG AA
// (4.5:1) on the glass body and on the opaque fallback, using the token
// values. A glass tone is only proven against its matching backdrop class
// (dark glass over a dark desktop, light glass over a light one): the body
// is faint by design, so a mismatched backdrop cannot be guaranteed.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

void main() {
  test('glass is a persisted background preset', () {
    expect(OverlayBackground.fromValue('glass'), OverlayBackground.glass);
    expect(OverlayBackground.glass.value, 'glass');
  });

  test('only the glass preset resolves to the glass colour set', () {
    for (final preset in OverlayBackground.values) {
      final colors = OverlayDesignSpec.colorsFor(background: preset);
      expect(
        colors.glass,
        preset == OverlayBackground.glass,
        reason: preset.value,
      );
    }
  });

  test('glass ink follows the glass tone', () {
    final dark = OverlayDesignSpec.colorsFor(
      background: OverlayBackground.glass,
      glassTone: OverlayDesignTheme.dark,
    );
    final light = OverlayDesignSpec.colorsFor(
      background: OverlayBackground.glass,
      glassTone: OverlayDesignTheme.light,
    );
    expect(dark.tone, OverlayDesignTheme.dark);
    expect(dark.ink, _white);
    expect(light.tone, OverlayDesignTheme.light);
    expect(light.ink, WpOverlayTokens.overlayGletscherInk);
  });

  test('glyphs keep AA (4.5:1) on the glass body over a matching backdrop', () {
    // Dark glass: white ink over a dark desktop (the faint black tint on it).
    final darkWorst = OverlayOpacityGate.worstContrast(
      fill: OverlayBackground.glassFillFor(OverlayDesignTheme.dark),
      accent: _white,
      alpha: OverlayBackground.glassFillFor(OverlayDesignTheme.dark).a,
      backdrops: const [_black],
    );
    expect(darkWorst, greaterThanOrEqualTo(4.5));

    // Light glass: Gletscher ink over a light desktop (the white tint on it).
    final lightWorst = OverlayOpacityGate.worstContrast(
      fill: OverlayBackground.glassFillFor(OverlayDesignTheme.light),
      accent: WpOverlayTokens.overlayGletscherInk,
      alpha: OverlayBackground.glassFillFor(OverlayDesignTheme.light).a,
      backdrops: const [_white],
    );
    expect(lightWorst, greaterThanOrEqualTo(4.5));
  });

  test('glyphs keep AA on the opaque fallback body of both tones', () {
    expect(
      contrastRatio(
        _white,
        OverlayBackground.glassOpaqueFor(OverlayDesignTheme.dark),
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(
        WpOverlayTokens.overlayGletscherInk,
        OverlayBackground.glassOpaqueFor(OverlayDesignTheme.light),
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('the opaque fallback is what the painter paints under reduced '
      'transparency', () {
    final colors = OverlayDesignSpec.colorsFor(
      background: OverlayBackground.glass,
      glassTone: OverlayDesignTheme.light,
    );
    expect(colors.opaqueFill, OverlayBackground.glassOpaqueFor(colors.tone));
    expect(colors.opaqueFill.a, 1);
  });

  test(
    'glass is monochrome: wave, dot and transcribing take the glyph colour',
    () {
      for (final tone in OverlayDesignTheme.values) {
        final colors = OverlayDesignSpec.colorsFor(
          background: OverlayBackground.glass,
          wave: OverlayWave.coral,
          glassTone: tone,
        );
        expect(colors.accent, colors.ink, reason: tone.name);
        expect(colors.transcribingAccent, colors.ink, reason: tone.name);
      }
    },
  );
}
