/// Overlay theme presets (ticket, ADR 0024): background × wave × signal
/// contrast, and the preset identity/defaults.
///
/// Every combination a user can pick must keep the graphics above the
/// non-text minimum (3:1) and the glyph ink above AA (4.5:1) on every stop of
/// the pill's fill gradient. The floating button reuses the same fill, so the
/// same guard covers its disc.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('background presets', () {
    test('names, tones and the legacy fallback', () {
      expect(OverlayBackground.values.map((b) => b.value), <String>[
        'marine',
        'graphit',
        'gletscher',
        'amber',
      ]);
      expect(OverlayBackground.marine.tone, OverlayDesignTheme.dark);
      expect(OverlayBackground.graphit.tone, OverlayDesignTheme.dark);
      expect(OverlayBackground.gletscher.tone, OverlayDesignTheme.light);
      // Amber (Bernstein) is a light surface: dark ink on it, light waves.
      expect(OverlayBackground.amber.tone, OverlayDesignTheme.light);
      expect(OverlayBackground.fromValue('amber'), OverlayBackground.amber);
      expect(OverlayBackground.fromValue(null), OverlayBackground.marine);
      expect(OverlayBackground.fromValue('petrol'), OverlayBackground.marine);
      // Legacy overlay_style values both resolve to the one fill that the
      // Glas/Volldeckend pair already shared (UX-013).
      expect(OverlayBackground.fromValue('glass'), OverlayBackground.marine);
      expect(OverlayBackground.fromValue('solid'), OverlayBackground.marine);
    });

    test('presets read their colours from the generated tokens', () {
      expect(
        OverlayBackground.marine.surfaceStart,
        WpOverlayTokens.overlayMarineSurface,
      );
      expect(
        OverlayBackground.gletscher.ink,
        WpOverlayTokens.overlayGletscherInk,
      );
      expect(
        OverlayBackground.amber.surfaceStart,
        WpOverlayTokens.overlayAmberSurface,
      );
    });
  });

  group('wave presets', () {
    test('names, default and per-tone values', () {
      expect(OverlayWave.values.map((w) => w.value), <String>[
        'cyan',
        'violett',
        'ink',
        'amber',
        'coral',
        'mint',
      ]);
      expect(OverlayWave.fromValue(null), OverlayWave.cyan);
      expect(OverlayWave.fromValue('amber'), OverlayWave.amber);
      expect(OverlayWave.fromValue('plaid'), OverlayWave.cyan);
      expect(
        OverlayWave.cyan.valueOn(OverlayDesignTheme.dark),
        WpOverlayTokens.overlayWaveCyanDark,
      );
      expect(
        OverlayWave.cyan.valueOn(OverlayDesignTheme.light),
        WpOverlayTokens.overlayWaveCyanLight,
      );
    });
  });

  group('validity of the pairings (WP-75b)', () {
    test('only ink is invalid, and only on the dark backgrounds', () {
      final invalid = [
        for (final background in OverlayBackground.values)
          for (final wave in OverlayWave.values)
            if (!wave.isValidOn(background))
              '${background.value} × ${wave.value}',
      ];
      expect(invalid, ['marine × ink', 'graphit × ink']);
    });
  });

  group('contrast of every background × wave × signal', () {
    for (final background in OverlayBackground.values) {
      for (final wave in OverlayWave.values) {
        // Invalid pairings are disabled in the settings and never drawn.
        if (!wave.isValidOn(background)) continue;
        final label = '${background.value} × ${wave.value}';

        test('pill and button keep their contrast: $label', () {
          final colors = OverlayDesignSpec.colorsFor(
            background: background,
            wave: wave,
          );
          // The fill is one flat colour (no gradient, no sheen), so the
          // contrast floor is checked on that single surface.
          final surfaces = [background.surfaceStart];

          for (final surface in surfaces) {
            expect(
              _contrast(colors.accent, surface),
              greaterThanOrEqualTo(3.0),
              reason: 'wave ${colors.accent} on $surface ($label)',
            );
            expect(
              _contrast(colors.ink, surface),
              greaterThanOrEqualTo(4.5),
              reason: 'glyph ink ${colors.ink} on $surface ($label)',
            );
            for (final signal in [
              colors.transcribingAccent,
              colors.success,
              colors.error,
            ]) {
              expect(
                _contrast(signal, surface),
                greaterThanOrEqualTo(3.0),
                reason: 'signal $signal on $surface ($label)',
              );
            }
            for (final state in OverlayDesignState.values) {
              for (final stop in OverlayDesignSpec.glyphStopsFor(
                state,
                colors,
              )) {
                expect(
                  _contrast(stop, surface),
                  greaterThanOrEqualTo(3.0),
                  reason:
                      'button glyph $stop ${state.name} on $surface '
                      '($label)',
                );
              }
            }
          }
        });
      }
    }
  });

  group('amber (Bernstein) background and wave', () {
    test('amber keeps the dark ink, so text and glyphs reach AA on it', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.amber,
      );
      expect(colors.ink, WpOverlayTokens.overlayAmberInk);
      expect(
        _contrast(colors.ink, OverlayBackground.amber.surfaceStart),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('an amber wave keeps its own token on amber (3:1 by design)', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.amber,
        wave: OverlayWave.amber,
      );
      expect(colors.accent, WpOverlayTokens.overlayWaveAmberLight);
    });

    test('cyan on amber steps to the darker cyan, not the ink', () {
      // Cyan 600 is about 2.9:1 on amber; the darker cyan 700 reaches 4.1:1.
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.amber,
        wave: OverlayWave.cyan,
      );
      expect(colors.accent, WpOverlayTokens.overlayWaveCyanLightStrong);
    });

    test('a done check that cannot reach 3:1 on amber uses the ink', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.amber,
      );
      expect(colors.success, WpOverlayTokens.overlayAmberInk);
    });

    test('pairings that already pass keep their token values', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.marine,
        wave: OverlayWave.cyan,
      );
      expect(colors.accent, WpOverlayTokens.overlayWaveCyanDark);
      expect(colors.success, WpOverlayTokens.overlaySignalDarkDone);
    });
  });

  group('resolved colour set', () {
    test('the default pairing is marine × cyan and keeps the wave accent', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.marine,
        wave: OverlayWave.cyan,
      );
      expect(colors.tone, OverlayDesignTheme.dark);
      expect(colors.accent, WpOverlayTokens.overlayWaveCyanDark);
      expect(colors.capsuleFill, WpOverlayTokens.overlayMarineSurface);
      expect(colors.ink, WpOverlayTokens.overlayMarineInk);
      expect(colors.inkOutline, WpOverlayTokens.overlayMarineInkOutline);
      expect(
        colors.transcribingAccent,
        WpOverlayTokens.overlaySignalDarkTranscribing,
      );
    });

    test('a light background takes the light wave and signal set', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.gletscher,
        wave: OverlayWave.violett,
      );
      expect(colors.tone, OverlayDesignTheme.light);
      expect(colors.accent, WpOverlayTokens.overlayWaveViolettLight);
      expect(
        colors.transcribingAccent,
        WpOverlayTokens.overlaySignalLightTranscribing,
      );
    });

    test('the hairline border is the wave colour at 20 percent', () {
      final colors = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.marine,
        wave: OverlayWave.violett,
      );
      expect(colors.capsuleBorder, colors.accent.withValues(alpha: 0.2));
    });

    test('equal inputs give equal colour sets (repaint checks rely on it)', () {
      final a = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.graphit,
        wave: OverlayWave.cyan,
      );
      final b = OverlayDesignSpec.colorsFor(
        background: OverlayBackground.graphit,
        wave: OverlayWave.cyan,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('recording mic follows the wave (ADR 0024, Nachtrag 2026-10-22)', () {
    const pairings = [
      (OverlayBackground.amber, OverlayWave.ink),
      (OverlayBackground.amber, OverlayWave.cyan),
      (OverlayBackground.marine, OverlayWave.cyan),
      (OverlayBackground.graphit, OverlayWave.coral),
      (OverlayBackground.gletscher, OverlayWave.violett),
    ];

    for (final (background, wave) in pairings) {
      test('${background.value} x ${wave.value}: the recording mic is the wave '
          'colour, as the dot in the pill', () {
        final colors = OverlayDesignSpec.colorsFor(
          background: background,
          wave: wave,
        );
        expect(
          OverlayDesignSpec.glyphStopsFor(OverlayDesignState.recording, colors),
          [colors.accent, colors.accent],
        );
      });
    }

    test('falls back to the ink where the wave is not legible on the fill', () {
      final base = OverlayDesignSpec.colorsFor();
      final illegible = OverlayThemeColors(
        tone: base.tone,
        capsuleFill: const Color(0xFFFFFFFF),
        ink: base.ink,
        inkOutline: base.inkOutline,
        edge: base.edge,
        shadow: base.shadow,
        capsuleBorder: base.capsuleBorder,
        accent: const Color(0xFFF2F2F2),
        transcribingAccent: base.transcribingAccent,
        success: base.success,
        error: base.error,
      );
      expect(
        OverlayDesignSpec.glyphStopsFor(
          OverlayDesignState.recording,
          illegible,
        ),
        [base.ink, base.ink],
      );
    });
  });
}
