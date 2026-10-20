// Widget-level contrast guard for the settings row title (WP-81, 2026-10-18).
//
// The token-level check in test/core/theme/wcag_contrast_test.dart computes
// the pairs from palette values. This test renders a real SettingRow and reads
// the colours the Text widgets actually paint with, so reverting the colour
// override in settings_widgets.dart turns it red.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_accent_badge.dart';

import '../../fixtures/test_helpers.dart';

const _label = 'Learn from corrections';
const _subtitle = 'Watching repeated corrections for suggestions';
const _badge = 'New';

/// Source-over compositing of [fg] onto an opaque [bg].
Color _over(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _linear(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final palettes = <String, WpThemeColors>{
    'light': wpLightColors,
    'dark': wpDarkColors,
    'navy': wpNavyColors,
  };

  for (final entry in palettes.entries) {
    testWidgets('settings row title, subtitle and badge meet 4.5:1 on the '
        'card – ${entry.key}', (tester) async {
      WpColors.activate(entry.value);
      addTearDown(() => WpColors.activate(wpLightColors));

      await tester.pumpWidget(
        makeTestable(
          Container(
            color: WpColors.background,
            padding: const EdgeInsets.all(24),
            child: Container(
              color: WpColors.cardFill,
              child: const SettingRow(
                icon: LucideIcons.sparkles,
                label: _label,
                subtitle: _subtitle,
                badge: _badge,
                trailing: SizedBox.shrink(),
              ),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // What the card really looks like: its translucent fill over the page.
      final card = _over(WpColors.cardFill, WpColors.background);

      Color painted(String text) {
        final widget = tester.widget<Text>(find.text(text));
        return widget.style?.color ??
            DefaultTextStyle.of(tester.element(find.text(text))).style.color!;
      }

      final title = _contrast(painted(_label), card);
      expect(
        title,
        greaterThanOrEqualTo(4.5),
        reason:
            'title ${painted(_label)} on card $card: ${title.toStringAsFixed(2)}:1',
      );

      final subtitle = _contrast(painted(_subtitle), card);
      expect(
        subtitle,
        greaterThanOrEqualTo(4.5),
        reason: 'subtitle on card: ${subtitle.toStringAsFixed(2)}:1',
      );

      // The badge paints its own fill (accentSubtle) on top of the card.
      final badgeFill = _over(WpColors.accentSubtle, card);
      final badgeText = _contrast(painted(_badge), badgeFill);
      expect(
        badgeText,
        greaterThanOrEqualTo(4.5),
        reason: 'badge text on its fill: ${badgeText.toStringAsFixed(2)}:1',
      );
      expect(find.byType(WpAccentBadge), findsOneWidget);
    });
  }
}
