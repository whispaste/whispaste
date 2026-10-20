// Contrast guard for the settings controls that blended into their ground in
// the dark and Marine modes (UX-008): the off state of a switch is a UI
// component boundary (3:1 against its surface), and helper text is text
// (4.5:1). Checked per mode against the theme that the app actually builds.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/core/theme/theme_colors.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] composited over the opaque [bg].
Color _over(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

void main() {
  final modes = <String, WpThemeColors>{
    'light': wpLightColors,
    'dark': wpDarkColors,
    'navy': wpNavyColors,
  };

  for (final entry in modes.entries) {
    final mode = entry.key;
    final c = entry.value;

    test('$mode: switch off track keeps 3:1 against its surface', () {
      final theme = wpThemeFor(c);
      final track = theme.switchTheme.trackColor!.resolve(<WidgetState>{})!;
      expect(
        _ratio(_over(track, c.surface), c.surface),
        greaterThanOrEqualTo(3.0),
        reason: '$mode: off track ${track.toString()} vs surface',
      );
    });

    test('$mode: helper text keeps 4.5:1 on surface and background', () {
      for (final ground in [c.surface, c.background, c.surfaceElevated]) {
        final text = _over(c.textMuted, ground);
        expect(_ratio(text, ground), greaterThanOrEqualTo(4.5), reason: mode);
      }
    });

    test('$mode: helper text of a switched-off row keeps 3:1', () {
      final ground = c.surface;
      final text = _over(
        c.textMuted.withValues(alpha: WpDisabledTokens.rowOpacity),
        ground,
      );
      expect(_ratio(text, ground), greaterThanOrEqualTo(3.0), reason: mode);
    });
  }
}
