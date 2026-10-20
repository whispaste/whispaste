/// WpHeroButton fill and label (UIA-CMP-01, Maintainer decision 2026-10-19).
///
/// The hero CTA is a flat amber surface in every appearance, with navy label
/// text. The label must reach WCAG AA (4.5:1) against the resting, hover and
/// pressed fill of each appearance, and the fill must be a token, not a
/// gradient.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../core/theme/wcag_contrast_test.dart' show contrastRatio;
import '../fixtures/test_helpers.dart';

const _appearances = <String, WpThemeColors>{
  'light': wpLightColors,
  'dark': wpDarkColors,
  'navy': wpNavyColors,
};

void main() {
  for (final entry in _appearances.entries) {
    testWidgets('${entry.key}: flat CTA fill with navy label', (tester) async {
      final colors = entry.value;
      WpColors.activate(colors);
      addTearDown(() => WpColors.activate(wpDarkColors));

      await tester.pumpWidget(
        makeTestable(WpHeroButton(label: 'Weiter', onPressed: () {})),
      );

      final text = tester.widget<Text>(find.text('Weiter'));
      expect(text.style?.color, colors.onCta);

      final ink = tester.widget<Ink>(find.byType(Ink).first);
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, colors.ctaFill);

      for (final fill in [colors.ctaFill, colors.ctaHover, colors.ctaPressed]) {
        expect(
          contrastRatio(colors.onCta, fill),
          greaterThanOrEqualTo(4.5),
          reason: 'label ${colors.onCta} on CTA state $fill',
        );
      }
    });
  }
}
