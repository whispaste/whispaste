/// WCAG AA contrast for the colour roles the ticket components paint with.
///
/// Covers the pairs introduced or reused by the restyled base components,
/// across the light, dark and brand appearances. Translucent roles are
/// composited over the surface they sit on before the ratio is taken.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors_dark.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/theme_colors.dart';

import 'wcag_contrast_test.dart' show alphaComposite, contrastRatio;

const _sets = <String, WpThemeColors>{
  'light': wpLightColors,
  'dark': wpDarkColors,
  'navy': wpNavyColors,
};

void main() {
  for (final entry in _sets.entries) {
    final name = entry.key;
    final c = entry.value;

    group('$name appearance', () {
      test('onCta on every CTA state reaches 4.5:1', () {
        for (final fill in [c.ctaFill, c.ctaHover, c.ctaPressed]) {
          expect(
            contrastRatio(c.onCta, fill),
            greaterThanOrEqualTo(4.5),
            reason: 'onCta on $fill',
          );
        }
      });

      test(
        'control edge reaches 3:1 on surface and surfaceVariant (UIA-FND-01)',
        () {
          for (final bg in [c.surface, c.surfaceVariant]) {
            expect(
              contrastRatio(c.controlEdge, bg),
              greaterThanOrEqualTo(3.0),
              reason: 'controlEdge ${c.controlEdge} over $bg',
            );
          }
        },
      );

      test('control edge is opaque, so the 3:1 check needs no compositing', () {
        expect(c.controlEdge.a, 1.0);
      });

      test('warning text on its badge tint reaches 4.5:1 (UIA-FND-04)', () {
        final badge = alphaComposite(c.warningOrangeBadgeFill, c.surface);
        expect(
          contrastRatio(c.warningOrangeText, badge),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('secondary text on the active fill reaches 4.5:1 (UIA-FND-03)', () {
        expect(
          contrastRatio(c.textSecondary, c.active),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('onAction on action fill reaches 4.5:1', () {
        expect(contrastRatio(c.onAction, c.action), greaterThanOrEqualTo(4.5));
      });

      test('accent text on surface reaches 4.5:1', () {
        expect(
          contrastRatio(c.accent, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'accent is used as link and secondary-action text',
        );
      });

      test('accent text on composited accentSubtle reaches 4.5:1', () {
        final chip = alphaComposite(c.accentSubtle, c.surface);
        expect(contrastRatio(c.accent, chip), greaterThanOrEqualTo(4.5));
      });

      test('onError on error fill reaches 4.5:1', () {
        expect(contrastRatio(c.onError, c.error), greaterThanOrEqualTo(4.5));
      });

      test('highlightText on composited highlightSoft reaches 4.5:1', () {
        final chip = alphaComposite(c.highlightSoft, c.surface);
        expect(contrastRatio(c.highlightText, chip), greaterThanOrEqualTo(4.5));
      });

      test('onPrimaryRecord on primaryRecordFill reaches 4.5:1', () {
        expect(
          contrastRatio(c.onPrimaryRecord, c.primaryRecordFill),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('primaryRecordFill against the navy dock reaches 3:1', () {
        expect(
          contrastRatio(c.primaryRecordFill, WpColorsDark.background),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('textMuted on surface reaches 4.5:1', () {
        expect(
          contrastRatio(c.textMuted, c.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('switch thumb on the off track reaches 3:1 (WCAG 1.4.11)', () {
        expect(
          contrastRatio(WpPalette.white, c.switchTrackOff),
          greaterThanOrEqualTo(3.0),
          reason: 'the white thumb must stay distinguishable from its track',
        );
      });

      test('switch off track on the background reaches 3:1 (WCAG 1.4.11)', () {
        expect(
          contrastRatio(c.switchTrackOff, c.background),
          greaterThanOrEqualTo(3.0),
          reason: 'the track is the only outline of an off switch',
        );
      });

      test('textPrimary on composited selected card fill reaches 4.5:1', () {
        final card = alphaComposite(c.cardFillElevated, c.surface);
        expect(contrastRatio(c.textPrimary, card), greaterThanOrEqualTo(4.5));
      });

      // #1075: the Statistik section headings (Überblick, Aktivität,
      // Einblicke) and their subtitles are the theme's headlineMedium and
      // bodySmall; they sit on the page ground and must read at 4.5:1 there.
      test('section heading and subtitle reach 4.5:1 on the page', () {
        final text = wpThemeFor(c).textTheme;
        for (final bg in [c.background, c.surface]) {
          for (final style in [text.headlineMedium!, text.bodySmall!]) {
            expect(
              contrastRatio(style.color!, bg),
              greaterThanOrEqualTo(4.5),
              reason: '${style.color} on $bg',
            );
          }
        }
      });

      // #1075: the key-figure tile lays the accent tint over the elevated
      // card; its number and label keep AA, its accent icon keeps 3:1.
      test('key-figure tile keeps text 4.5:1 and icon 3:1', () {
        final card = alphaComposite(
          c.accentSubtle,
          alphaComposite(c.cardFillElevated, c.surface),
        );
        expect(contrastRatio(c.textPrimary, card), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.textSecondary, card), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.accent, card), greaterThanOrEqualTo(3.0));
      });

      // #1075: the duration bars come from the accent family; every rung is
      // a graphical object and clears the card it sits on at 3:1.
      test('duration bars (accent) reach 3:1 on the card and track', () {
        final card = alphaComposite(c.cardFill, c.surface);
        final track = alphaComposite(c.surfaceVariant, card);
        expect(contrastRatio(c.accent, card), greaterThanOrEqualTo(3.0));
        expect(contrastRatio(c.accent, track), greaterThanOrEqualTo(3.0));
      });
    });
  }
}
