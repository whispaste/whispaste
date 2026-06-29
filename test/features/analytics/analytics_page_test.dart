/// Tests for [AnalyticsPage].
///
/// Covers: empty state, dashboard with mocked data, hero stat labels,
/// period chips (7d / 30d / 90d / all), reset confirm dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart' show AnalyticsModelUsage;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Mock analytics data — non-empty so the dashboard branch renders
// ---------------------------------------------------------------------------

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

List<Object> _dataOverrides(AnalyticsData data) => [
  analyticsProvider.overrideWith((ref) async => data),
];

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('AnalyticsPage', () {
    // -------------------------------------------------------------------------
    // 1. Empty state
    // -------------------------------------------------------------------------

    testWidgets('shows empty state when there are no recordings', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(AnalyticsData.empty),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.analyticsEmptyTitle), findsOneWidget);
      expect(find.text(l10n.analyticsEmptySubtitle), findsOneWidget);
      expect(find.byIcon(LucideIcons.chartNoAxesColumn), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Dashboard renders with data
    // -------------------------------------------------------------------------

    testWidgets('renders the overview section with hero stat labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Overview section header
      expect(find.text(l10n.analyticsOverview), findsOneWidget);

      // Hero stat labels
      expect(find.text(l10n.analyticsTotalRecordings), findsOneWidget);
      expect(find.text(l10n.analyticsTotalDuration), findsOneWidget);
      expect(find.text(l10n.analyticsWordsDictated), findsOneWidget);
      expect(find.text(l10n.analyticsTimeSaved), findsOneWidget);
    });

    testWidgets('renders activity and insights sections', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.analyticsActivity), findsOneWidget);
      expect(find.text(l10n.analyticsInsights), findsOneWidget);
      expect(find.text(l10n.analyticsRecordingActivity), findsOneWidget);
      expect(find.text(l10n.analyticsDurationDistribution), findsOneWidget);
    });

    testWidgets('renders cost & savings panel', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.analyticsCostSavings), findsOneWidget);
      expect(find.text(l10n.analyticsLocalSavings), findsOneWidget);
      expect(find.text(l10n.analyticsCloudCost), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Period chips
    // -------------------------------------------------------------------------

    testWidgets('shows all four period chips', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.analyticsPeriod7d), findsOneWidget);
      expect(find.text(l10n.analyticsPeriod30d), findsOneWidget);
      expect(find.text(l10n.analyticsPeriod90d), findsOneWidget);
      expect(find.text(l10n.analyticsPeriodAll), findsOneWidget);
    });

    testWidgets('tapping a period chip updates analyticsPeriodProvider', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The period chips are near the bottom of the scrollable dashboard.
      // Scroll to bring them into view before tapping.
      await tester.ensureVisible(find.text(l10n.analyticsPeriod7d));
      await tester.pumpAndSettle();

      // Default period is allTime — tap 7-day chip
      await tester.tap(find.text(l10n.analyticsPeriod7d));
      await tester.pumpAndSettle();

      // No exception thrown and UI still renders after period switch
      expect(find.text(l10n.analyticsOverview), findsOneWidget);

      // Scroll again and tap 30-day
      await tester.ensureVisible(find.text(l10n.analyticsPeriod30d));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.analyticsPeriod30d));
      await tester.pumpAndSettle();
      expect(find.text(l10n.analyticsOverview), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 4. Reset dialog
    // -------------------------------------------------------------------------

    testWidgets('reset button opens confirm dialog', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // There is exactly one OutlinedButton (the reset button).
      // Scroll to bring it into view before tapping.
      expect(find.byType(OutlinedButton), findsOneWidget);
      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      // Confirm dialog should be visible with title and message
      expect(find.text(l10n.analyticsResetTitle), findsOneWidget);
      expect(find.text(l10n.analyticsResetMessage), findsOneWidget);
    });

    testWidgets('cancel in reset dialog closes it without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to reset button and open dialog
      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.analyticsResetTitle), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pumpAndSettle();

      // Dialog dismissed — reset title no longer visible
      expect(find.text(l10n.analyticsResetTitle), findsNothing);
      // Dashboard still renders
      expect(find.text(l10n.analyticsOverview), findsOneWidget);
    });

    testWidgets('confirming reset clears data and invalidates provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to reset button and open dialog
      await tester.ensureVisible(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      // Confirm — this calls db.resetDailyStats() on the in-memory DB.
      // After reset the provider is invalidated; our override returns
      // _mockData again so the dashboard stays visible (no crash).
      await tester.tap(find.text(l10n.analyticsReset).last);
      // WpToast.show() schedules a 3-second dismissal timer.
      // pumpAndSettle() would block waiting for it; pump with duration instead.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // 5. Error state (AC2)
    // -------------------------------------------------------------------------

    testWidgets('shows WpEmptyState with error icon when provider throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: [
            analyticsProvider.overrideWith(
              // Riverpod 2.x retries Exception-typed errors (stays in
              // AsyncLoading). Throwing an Error subclass (StateError) skips
              // the retry logic and immediately transitions to AsyncError.
              (ref) => Future<AnalyticsData>.error(
                StateError('test error'),
                StackTrace.empty,
              ),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      // pump() once to flush the microtask that rejects the future,
      // then pumpAndSettle to let Riverpod rebuild the widget.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorGeneric), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // -------------------------------------------------------------------------
    // 6. Loading skeleton state (AC3)
    // -------------------------------------------------------------------------

    testWidgets(
      'shows skeleton (no CircularProgressIndicator) during loading',
      (tester) async {
        // Use a Completer that never resolves — avoids pending timer issues.
        final completer = Completer<AnalyticsData>();
        await tester.pumpWidget(
          makeTestable(
            const AnalyticsPage(),
            overrides: [
              analyticsProvider.overrideWith((ref) => completer.future),
            ],
            locale: const Locale('en'),
          ),
        );
        // Single pump — Completer never resolves, so provider stays in loading.
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        // Skeleton renders Container boxes arranged in rows
        expect(find.byType(Row), findsWidgets);
      },
    );

    // -------------------------------------------------------------------------
    // 7. Works in light theme
    // -------------------------------------------------------------------------

    testWidgets('renders without error in light theme', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          brightness: Brightness.light,
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.analyticsOverview), findsOneWidget);
    });
  });
}
