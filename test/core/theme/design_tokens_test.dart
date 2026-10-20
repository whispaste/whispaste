import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';

import '../../../tool/design_tokens/generate_dart.dart';
import '../../test_helpers/dart_sdk.dart';

/// WCAG 2.x relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Composites a translucent [top] over an opaque [bottom].
Color over(Color top, Color bottom) => Color.from(
  alpha: 1,
  red: top.r * top.a + bottom.r * (1 - top.a),
  green: top.g * top.a + bottom.g * (1 - top.a),
  blue: top.b * top.a + bottom.b * (1 - top.a),
);

void main() {
  test('generated tokens are up to date with design-tokens/*.json', () async {
    final expected = await buildFormattedTokens(
      Directory('design-tokens'),
      dartExecutable: resolveDartExecutable(),
    );
    expect(
      File(kGeneratedPath).readAsStringSync(),
      expected,
      reason: 'Run `dart run tool/design_tokens/generate_dart.dart`.',
    );
  });

  group('journal contrast (WCAG AA)', () {
    const p = wpJournalPalette;
    for (final bg in {
      'canvas': p.canvas,
      'pane': p.pane,
      'surface': p.surface,
      'selected': over(p.selected, p.canvas),
    }.entries) {
      test('text on ${bg.key}', () {
        expect(contrast(p.textPrimary, bg.value), greaterThanOrEqualTo(4.5));
        expect(contrast(p.textSecondary, bg.value), greaterThanOrEqualTo(4.5));
        expect(contrast(p.textMuted, bg.value), greaterThanOrEqualTo(4.5));
        expect(contrast(p.accent, bg.value), greaterThanOrEqualTo(4.5));
      });
    }
    test('controls and markers', () {
      expect(contrast(p.borderControl, p.surface), greaterThanOrEqualTo(3));
      expect(contrast(p.focusRing, p.surface), greaterThanOrEqualTo(3));
      expect(contrast(p.onAction, p.action), greaterThanOrEqualTo(4.5));
      expect(contrast(p.onAccentFill, p.accentFill), greaterThanOrEqualTo(4.5));
      expect(contrast(p.onHighlight, p.highlight), greaterThanOrEqualTo(4.5));
      expect(
        contrast(p.highlightText, over(p.highlightSoft, p.surface)),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(p.success, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.error, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.warning, p.surface), greaterThanOrEqualTo(4.5));
    });
  });

  group('stage contrast (WCAG AA)', () {
    const p = wpStagePalette;
    test('text on dock surface', () {
      expect(contrast(p.textPrimary, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.textSecondary, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.textMuted, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.accent, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.onAction, p.action), greaterThanOrEqualTo(4.5));
      expect(contrast(p.focusRing, p.surface), greaterThanOrEqualTo(3));
    });
  });
}
