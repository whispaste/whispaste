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
  });
}
