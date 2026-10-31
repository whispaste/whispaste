/// Wave validity per background (WP-75b, ADR 0024 Nachtrag). A pairing is
/// valid only when the wave, or its darker light step, reaches 3:1 on the
/// background fill. Invalid pairings are never drawn with a silent stand-in:
/// the UI disables them and the stored choice migrates to a valid wave.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

void main() {
  group('validity of the background x wave matrix', () {
    test('ink is invalid on both dark backgrounds', () {
      expect(OverlayWave.ink.isValidOn(OverlayBackground.marine), isFalse);
      expect(OverlayWave.ink.isValidOn(OverlayBackground.graphit), isFalse);
    });

    test('ink is valid on both light backgrounds', () {
      expect(OverlayWave.ink.isValidOn(OverlayBackground.gletscher), isTrue);
      expect(OverlayWave.ink.isValidOn(OverlayBackground.amber), isTrue);
    });

    test('every background keeps at least three valid waves', () {
      for (final background in OverlayBackground.values) {
        final valid = OverlayWave.values
            .where((wave) => wave.isValidOn(background))
            .length;
        expect(
          valid,
          greaterThanOrEqualTo(3),
          reason: '${background.value} has $valid valid waves',
        );
      }
    });

    test('effectiveOn is null exactly when the pairing is invalid', () {
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          expect(
            wave.effectiveOn(background) != null,
            wave.isValidOn(background),
            reason: '${wave.value} on ${background.value}',
          );
        }
      }
    });

    test('every valid pairing reaches 3:1 with the colour it draws', () {
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          final drawn = wave.effectiveOn(background);
          if (drawn == null) continue;
          expect(
            _contrast(drawn, background.surfaceStart),
            greaterThanOrEqualTo(3.0),
            reason: '${wave.value} on ${background.value}',
          );
        }
      }
    });
  });

  group('the colour a pairing draws is the colour its swatch shows', () {
    test('cyan steps down to the darker light step on amber', () {
      expect(
        OverlayWave.cyan.effectiveOn(OverlayBackground.amber),
        WpOverlayTokens.overlayWaveCyanLightStrong,
      );
    });

    test('cyan keeps its base light step on gletscher', () {
      expect(
        OverlayWave.cyan.effectiveOn(OverlayBackground.gletscher),
        WpOverlayTokens.overlayWaveCyanLight,
      );
    });

    test('dark backgrounds draw the dark-tone value', () {
      expect(
        OverlayWave.cyan.effectiveOn(OverlayBackground.marine),
        WpOverlayTokens.overlayWaveCyanDark,
      );
    });

    test(
      'the resolved accent is the effective colour for every valid pair',
      () {
        for (final background in OverlayBackground.values) {
          for (final wave in OverlayWave.values) {
            final drawn = wave.effectiveOn(background);
            if (drawn == null) continue;
            expect(
              OverlayThemeColors.resolve(
                background: background,
                wave: wave,
              ).accent,
              drawn,
              reason: '${wave.value} on ${background.value}',
            );
          }
        }
      },
    );
  });

  group('validOn: deterministic replacement of an invalid wave', () {
    test('a valid wave stays as it is', () {
      expect(
        OverlayWave.violett.validOn(OverlayBackground.graphit),
        OverlayWave.violett,
      );
    });

    test('ink becomes cyan on the dark backgrounds (neutral is retired)', () {
      expect(
        OverlayWave.ink.validOn(OverlayBackground.marine),
        OverlayWave.cyan,
      );
      expect(
        OverlayWave.ink.validOn(OverlayBackground.graphit),
        OverlayWave.cyan,
      );
    });

    test('ink stays ink on the light backgrounds', () {
      expect(
        OverlayWave.ink.validOn(OverlayBackground.gletscher),
        OverlayWave.ink,
      );
    });

    test('every replacement is valid on its background', () {
      for (final background in OverlayBackground.values) {
        for (final wave in OverlayWave.values) {
          expect(
            wave.validOn(background).isValidOn(background),
            isTrue,
            reason: '${wave.value} on ${background.value}',
          );
        }
      }
    });
  });

  group('new wave tokens', () {
    test('ink is black on both tones', () {
      expect(WpOverlayTokens.overlayWaveInkDark, const Color(0xFF000000));
      expect(WpOverlayTokens.overlayWaveInkLight, const Color(0xFF000000));
    });

    test('coral is the red primitive, mint the green primitive', () {
      expect(WpOverlayTokens.overlayWaveCoralDark, const Color(0xFFFF7B7B));
      expect(WpOverlayTokens.overlayWaveCoralLight, const Color(0xFFB42318));
      expect(WpOverlayTokens.overlayWaveMintDark, const Color(0xFF36D98B));
      expect(WpOverlayTokens.overlayWaveMintLight, const Color(0xFF0B6B40));
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
