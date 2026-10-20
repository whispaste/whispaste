/// WCAG contrast over the dock's token pairs (WP-79).
///
/// The dock sits on the navy stage in every appearance mode, so every pair is
/// measured against the stage canvas (translucent roles are composited over
/// it first, as the screen shows them):
/// - text on the dock: >= 4.5:1, secondary text included;
/// - disabled text: >= 3:1 (the only exemption, still legible);
/// - a control border (the outline of a selector): >= 3:1 (WCAG 1.4.11);
/// - text on a filled action: >= 4.5:1 in both the cyan and the amber fill.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// WCAG 2.1 contrast ratio of two opaque colours (order does not matter).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] as the screen paints it over [bg]: translucent roles are blended.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  const stage = wpStagePalette;
  // The opaque dock background: a change to it breaks these pairs.
  final canvas = stage.surface;
  // A selector's fill, composited over the dock background.
  final controlFill = _over(stage.control, canvas);

  group('dock text on the navy stage', () {
    final textOnDock = <String, Color>{
      'textPrimary': stage.textPrimary,
      'textSecondary': stage.textSecondary,
      'textMuted': stage.textMuted,
      'accent': stage.accent,
    };
    for (final entry in textOnDock.entries) {
      test('${entry.key} reaches 4.5:1 on the canvas', () {
        final ratio = contrastRatio(_over(entry.value, canvas), canvas);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: entry.key);
      });
    }

    test('secondary text reaches 4.5:1 on a selector fill', () {
      final fill = _over(stage.control, canvas);
      final ratio = contrastRatio(_over(stage.textSecondary, fill), fill);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('primary text reaches 4.5:1 on a hovered selector fill', () {
      final fill = _over(stage.controlHover, canvas);
      final ratio = contrastRatio(_over(stage.textPrimary, fill), fill);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  test('disabled text stays legible at 3:1 or more (the only exemption)', () {
    final ratio = contrastRatio(
      _over(stage.textDisabled, controlFill),
      controlFill,
    );
    expect(ratio, greaterThanOrEqualTo(3.0));
  });

  test('selector outline reaches 3:1 on the control fill (WCAG 1.4.11)', () {
    final ratio = contrastRatio(
      _over(stage.borderControl, controlFill),
      controlFill,
    );
    expect(ratio, greaterThanOrEqualTo(3.0));
  });

  group('labels on filled actions', () {
    test('navy label on the cyan action fill reaches 4.5:1', () {
      final ratio = contrastRatio(stage.onAction, stage.action);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('navy label on the Marine amber dictate fill reaches 4.5:1', () {
      final ratio = contrastRatio(
        wpNavyColors.onPrimaryRecord,
        wpNavyColors.primaryRecordFill,
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });
}
