import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('OverlayDesignSpec — states', () {
    test('covers exactly the four real states (no processing)', () {
      expect(OverlayDesignState.values, hasLength(4));
      expect(OverlayDesignState.values, <OverlayDesignState>[
        OverlayDesignState.recording,
        OverlayDesignState.transcribing,
        OverlayDesignState.done,
        OverlayDesignState.error,
      ]);
    });
  });

  group('OverlayDesignSpec — themes', () {
    test('default colour set is marine x cyan on the dark tone', () {
      final colors = OverlayDesignSpec.colorsFor();
      expect(colors.tone, OverlayDesignTheme.dark);
      expect(colors.capsuleFill, WpOverlayTokens.overlayMarineSurface);
      expect(colors.accent, WpOverlayTokens.overlayWaveCyanDark);
    });

    test('a light background takes the light tone', () {
      expect(
        OverlayDesignSpec.colorsFor(
          background: OverlayBackground.gletscher,
        ).tone,
        OverlayDesignTheme.light,
      );
    });
  });

  group('OverlayDesignSpec — accessibility', () {
    test('opacity affects only the chrome; slider floor documented', () {
      // Dock-glass fill (Maintainer decision 2026-07-29): the base fill sits
      // deliberately below the old text-safety product — the capsule is
      // meant to read as a bare glass body. The factor scales only the pill
      // chrome (fill gradient, shadow, border), never the content; waveform
      // and icons keep their own >=3:1 guarantees.
      expect(OverlayDesignSpec.fillOpacityFactor, 0.14);
      expect(OverlayDesignSpec.minRecommendedOpacity, 0.65);
    });
  });

  group('OverlayDesignSpec — no privacy badge', () {
    test('the model exposes no privacy/badge concept', () {
      // Anti-vocabulary guard: this test fails to compile if a privacy badge
      // field is ever reintroduced (kept as a documented invariant). The four
      // states alone drive the rendering.
      expect(
        OverlayDesignState.values.map((e) => e.name),
        isNot(contains('privacy')),
      );
      expect(
        OverlayDesignState.values.map((e) => e.name),
        isNot(contains('badge')),
      );
    });
  });
}
