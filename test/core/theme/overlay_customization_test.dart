/// WP-95: overlay shape, waveform style, content and opacity policies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('persisted names', () {
    test('form values match the native contract', () {
      expect(OverlayForm.values.map((f) => f.value), [
        'pill',
        'rounded-rect',
        'compact-circle',
        'edge-bar',
      ]);
    });

    test('wave style values match the native contract', () {
      expect(OverlayWaveStyle.values.map((s) => s.value), [
        'bars',
        'line',
        'dots',
      ]);
    });

    test('opacity steps are 100, 80 and 60 percent', () {
      expect(OverlayOpacity.values.map((o) => o.percent), [100, 80, 60]);
    });
  });

  group('fallbacks for unknown or missing values', () {
    test('unknown form falls back to pill', () {
      expect(OverlayForm.fromValue('hexagon'), OverlayForm.pill);
      expect(OverlayForm.fromValue(null), OverlayForm.pill);
    });

    test('unknown wave style falls back to bars', () {
      expect(OverlayWaveStyle.fromValue('spiral'), OverlayWaveStyle.bars);
      expect(OverlayWaveStyle.fromValue(null), OverlayWaveStyle.bars);
    });

    test('unknown or non-numeric opacity falls back to full', () {
      expect(OverlayOpacity.fromValue('42'), OverlayOpacity.full);
      expect(OverlayOpacity.fromValue('abc'), OverlayOpacity.full);
      expect(OverlayOpacity.fromValue(null), OverlayOpacity.full);
    });

    test('known values round-trip', () {
      for (final form in OverlayForm.values) {
        expect(OverlayForm.fromValue(form.value), form);
      }
      for (final style in OverlayWaveStyle.values) {
        expect(OverlayWaveStyle.fromValue(style.value), style);
      }
      for (final opacity in OverlayOpacity.values) {
        expect(OverlayOpacity.fromValue('${opacity.percent}'), opacity);
      }
    });
  });

  group('OverlayPolicy', () {
    test('edge bar falls back to pill without edge docking (Wayland)', () {
      expect(
        OverlayPolicy.effectiveForm(
          OverlayForm.edgeBar,
          edgeDockingSupported: false,
        ),
        OverlayForm.pill,
      );
    });

    test('edge bar stays where edge docking is supported', () {
      expect(
        OverlayPolicy.effectiveForm(
          OverlayForm.edgeBar,
          edgeDockingSupported: true,
        ),
        OverlayForm.edgeBar,
      );
    });

    test('other forms are never changed by the fallback', () {
      for (final form in OverlayForm.values.where(
        (f) => f != OverlayForm.edgeBar,
      )) {
        expect(
          OverlayPolicy.effectiveForm(form, edgeDockingSupported: false),
          form,
        );
      }
    });

    test('reduce motion turns the fluid outline off', () {
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: true, reduceMotion: true),
        isFalse,
      );
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: true, reduceMotion: false),
        isTrue,
      );
      expect(
        OverlayPolicy.effectiveWaveFluid(setting: false, reduceMotion: false),
        isFalse,
      );
    });

    test('stop control is always visible', () {
      expect(OverlayPolicy.stopAlwaysVisible, isTrue);
    });
  });

  group('OverlayOpacityGate', () {
    test('every background and wave pairing keeps the opacity contract', () {
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          // Disabled pairings are never resolved (the picker greys them out).
          if (!wave.isValidOn(background)) continue;
          final accent = OverlayThemeColors.resolve(
            background: background,
            wave: wave,
          ).accent;
          for (final requested in OverlayOpacity.values) {
            final result = OverlayOpacityGate.clamp(
              requested: requested,
              fill: background.surfaceStart,
              accent: accent,
            );

            // Never less opaque than asked for.
            expect(
              result.percent,
              greaterThanOrEqualTo(requested.percent),
              reason: '${background.value}/${wave.value}/${requested.percent}',
            );

            // Either the result keeps 3:1, or it is the full fill, the final
            // fallback that is guarded by the token tests.
            final contrast = OverlayOpacityGate.worstContrast(
              fill: background.surfaceStart,
              accent: accent,
              alpha: result.alpha,
            );
            expect(
              contrast >= OverlayOpacityGate.minimumContrast ||
                  result == OverlayOpacity.full,
              isTrue,
              reason:
                  '${background.value}/${wave.value}/${requested.percent} '
                  'gives ${contrast.toStringAsFixed(2)}:1 at ${result.percent}',
            );
          }
        }
      }
    });

    test('a request that already passes is not changed', () {
      final result = OverlayOpacityGate.clamp(
        requested: OverlayOpacity.full,
        fill: OverlayBackground.marine.surfaceStart,
        accent: WpOverlayTokens.overlayWaveCyanDark,
      );
      expect(result, OverlayOpacity.full);
    });

    test('marine with cyan steps 60 percent up to 80 (1.68:1 at 60)', () {
      // Over white the 60 percent marine fill lifts far enough that the dark
      // cyan falls to 1.68:1. The 80 percent step reaches 3.36:1.
      final result = OverlayOpacityGate.clamp(
        requested: OverlayOpacity.subtle,
        fill: OverlayBackground.marine.surfaceStart,
        accent: WpOverlayTokens.overlayWaveCyanDark,
      );
      expect(result, OverlayOpacity.reduced);
    });

    test(
      'gletscher with light cyan steps 80 percent up to full (2.76:1 at 80)',
      () {
        final result = OverlayOpacityGate.clamp(
          requested: OverlayOpacity.reduced,
          fill: OverlayBackground.gletscher.surfaceStart,
          accent: WpOverlayTokens.overlayWaveCyanLight,
        );
        expect(result, OverlayOpacity.full);
      },
    );
  });
}
