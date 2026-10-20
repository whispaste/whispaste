/// Pins the settings deep-link highlight: a soft tint behind the target row.
///
/// The tint is a positioned background (no border, no outline, no layout), so
/// the row never moves while it is marked. It fades in quickly and out over
/// 1.5 s once the page clears the target. Reduce motion turns both fades into
/// a static tint, and the title and explanation keep WCAG AA contrast on it in
/// every colour set.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

const _rowId = 'general-app-language';

Finder _rowOf(String rowId) => find.byKey(ValueKey('settings-row-$rowId'));

Finder _fillOf(String rowId) => find.descendant(
  of: _rowOf(rowId),
  matching: find.byKey(const ValueKey('settings-row-highlight-fill')),
);

/// Opacity the fill is currently painted with (the animated value).
double _fillOpacity(WidgetTester tester, String rowId) => tester
    .widget<FadeTransition>(
      // Nearest FadeTransition above the fill: the one AnimatedOpacity builds.
      find
          .ancestor(of: _fillOf(rowId), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

void _mark(WidgetTester tester, String? rowId) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SettingsPage)),
  );
  container.read(settingsHighlightTargetProvider.notifier).set(rowId);
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(const SettingsPage(), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
}

/// WCAG 2.x contrast ratio of [fg] over [bg].
double _contrast(Color fg, Color bg) {
  final a = fg.computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => WpColors.activate(wpLightColors));

  group('settings deep-link highlight', () {
    testWidgets('shows a tint on the target row only', (tester) async {
      await _pumpPage(tester);
      expect(_fillOpacity(tester, _rowId), 0);

      _mark(tester, _rowId);
      await tester.pump();
      await tester.pump(WpMotion.highlightIn);

      expect(_fillOpacity(tester, _rowId), 1);
    });

    testWidgets('paints no border or outline around the row', (tester) async {
      await _pumpPage(tester);
      _mark(tester, _rowId);
      await tester.pump(WpMotion.highlightIn);

      final fill = tester.widget<DecoratedBox>(_fillOf(_rowId));
      final decoration = fill.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: 'no outline as highlight');
      expect(decoration.color, isNotNull);

      final rowContainers = tester.widgetList<Container>(
        find.descendant(of: _rowOf(_rowId), matching: find.byType(Container)),
      );
      for (final c in rowContainers) {
        expect(
          (c.foregroundDecoration as BoxDecoration?)?.border,
          isNull,
          reason: 'the row must not paint a ring',
        );
      }
    });

    testWidgets('fill spans the row bounds plus the inset, nothing more', (
      tester,
    ) async {
      await _pumpPage(tester);
      final before = tester.getRect(_rowOf(_rowId));
      _mark(tester, _rowId);
      await tester.pump(WpMotion.highlightIn);

      expect(
        tester.getRect(_rowOf(_rowId)),
        before,
        reason: 'the tint must not move or resize the row',
      );
      expect(
        tester.getRect(_fillOf(_rowId)),
        Rect.fromLTRB(
          before.left - WpSpacing.sm,
          before.top,
          before.right + WpSpacing.sm,
          before.bottom,
        ),
        reason:
            'the fill covers the row band with WpSpacing.sm of air on each '
            'side, so the label keeps its inner padding inside the tint',
      );
    });

    testWidgets('fades out over 1.5 s after the target is cleared', (
      tester,
    ) async {
      await _pumpPage(tester);
      _mark(tester, _rowId);
      await tester.pump();
      await tester.pump(WpMotion.highlightIn);
      expect(_fillOpacity(tester, _rowId), 1);

      _mark(tester, null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      final midway = _fillOpacity(tester, _rowId);
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1), reason: 'still fading at the midpoint');

      await tester.pump(WpMotion.highlightOut);
      await tester.pumpAndSettle();
      expect(_fillOpacity(tester, _rowId), 0);
    });

    testWidgets('reduced motion shows a static tint without animation', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpPage(tester);

      _mark(tester, _rowId);
      await tester.pumpAndSettle();
      expect(
        _fillOpacity(tester, _rowId),
        1,
        reason: 'no fade-in: the tint is there at once',
      );

      _mark(tester, null);
      await tester.pumpAndSettle();
      expect(
        _fillOpacity(tester, _rowId),
        0,
        reason: 'no fade-out: the tint is gone at once',
      );
    });

    test('title and explanation keep WCAG AA contrast on the tint', () {
      for (final set in [wpLightColors, wpDarkColors, wpNavyColors]) {
        final base = Color.alphaBlend(set.cardFill, set.background);
        final tint = Color.alphaBlend(set.accentActiveFill, base);
        expect(
          _contrast(set.textPrimary, tint),
          greaterThanOrEqualTo(4.5),
          reason: 'title on tint (${set.brightness})',
        );
        expect(
          _contrast(set.textMuted, tint),
          greaterThanOrEqualTo(4.5),
          reason: 'explanation on tint (${set.brightness})',
        );
      }
    });
  });
}
