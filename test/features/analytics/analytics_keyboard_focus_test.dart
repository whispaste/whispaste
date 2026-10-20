// UIA-R-ANA-026: the statistics page is operable by keyboard alone. The period
// chips take focus in order, Space and Enter select them, Tab reaches the
// reset button, and Enter there opens the confirmation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart' show AnalyticsModelUsage;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../fixtures/test_helpers.dart';

const _mockData = AnalyticsData(
  totalRecordings: 42,
  totalDurationMinutes: 120,
  totalWords: 5000,
  timeSavedMinutes: 80,
  weeklyActivity: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
  modelUsage: <AnalyticsModelUsage>[],
  durationBuckets: [5, 3, 2, 1, 0],
  localSavingsUsd: 2.50,
  cloudCostUsd: 0.75,
);

/// Presses Tab until the focused element sits inside a widget [matches]
/// accepts, or fails after [max] presses.
Future<void> _tabUntil(
  WidgetTester tester,
  bool Function(BuildContext context) matches, {
  int max = 40,
}) async {
  for (var i = 0; i < max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && matches(context)) return;
  }
  fail('Tab never reached the expected control within $max presses');
}

bool _onChip(BuildContext context, String label) =>
    context.findAncestorWidgetOfExactType<WpFilterChip>()?.label == label;

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'period chips take focus in order and Space or Enter selects them '
    '(UIA-R-ANA-026)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: [analyticsProvider.overrideWith((ref) async => _mockData)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AnalyticsPage)),
      );

      // First chip in the traversal order.
      await _tabUntil(
        tester,
        (context) => _onChip(context, l10n.analyticsPeriod7d),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(container.read(analyticsPeriodProvider), AnalyticsPeriod.last7d);

      // Tab moves to the next chip, not to the one just activated.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _onChip(
          FocusManager.instance.primaryFocus!.context!,
          l10n.analyticsPeriod30d,
        ),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(analyticsPeriodProvider), AnalyticsPeriod.last30d);
    },
  );

  testWidgets(
    'Tab reaches the reset button after the chips and Enter opens its '
    'confirmation (UIA-R-ANA-026)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: [analyticsProvider.overrideWith((ref) async => _mockData)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await _tabUntil(
        tester,
        (context) => _onChip(context, l10n.analyticsPeriod7d),
      );
      await _tabUntil(
        tester,
        (context) =>
            context.findAncestorWidgetOfExactType<WpButton>()?.label ==
            l10n.analyticsReset,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(l10n.analyticsResetTitle), findsOneWidget);
    },
  );
}
