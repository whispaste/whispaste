/// Tests for [AnalyticsPage].
///
/// Covers: empty state, dashboard with mocked data, hero stat labels,
/// period chips (7d / 30d / 90d / all), reset confirm dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:drift/native.dart';
import 'package:whispaste/core/data/database.dart'
    show
        AnalyticsCorrection,
        AnalyticsModelUsage,
        AnalyticsWording,
        HistoryDatabase;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/widgets/wp_button.dart';

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

    testWidgets('shows wording totals and frequent corrections (9.7)', (
      tester,
    ) async {
      const withWording = AnalyticsData(
        totalRecordings: 3,
        totalDurationMinutes: 4,
        totalWords: 20,
        timeSavedMinutes: 2,
        weeklyActivity: [1.0, 0, 0, 0, 0, 0, 0],
        modelUsage: <AnalyticsModelUsage>[],
        durationBuckets: [3, 0, 0, 0, 0],
        localSavingsUsd: 0,
        cloudCostUsd: 0,
        wording: AnalyticsWording(
          rawWords: 42,
          revisedWords: 37,
          actionCount: 2,
        ),
        topCorrections: [
          AnalyticsCorrection(sourceText: 'gaus', targetText: 'Gauß', count: 4),
        ],
      );
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(withWording),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.analyticsWordingTitle), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('gaus → Gauß'), findsOneWidget);
      expect(find.text('4×'), findsOneWidget);
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

    testWidgets(
      'shows the average hotkey-to-text latency in seconds when data exists',
      (tester) async {
        const dataWithLatency = AnalyticsData(
          totalRecordings: 42,
          totalDurationMinutes: 120,
          totalWords: 5000,
          timeSavedMinutes: 80,
          weeklyActivity: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
          modelUsage: <AnalyticsModelUsage>[],
          durationBuckets: [5, 3, 2, 1, 0],
          localSavingsUsd: 2.50,
          cloudCostUsd: 0.75,
          averageStopToTextMs: 1830,
        );

        await tester.pumpWidget(
          makeTestable(
            const AnalyticsPage(),
            overrides: _dataOverrides(dataWithLatency),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.analyticsAvgLatency), findsOneWidget);
        expect(find.text('1.8s'), findsOneWidget);
        // The tile measures from the stop, not a speed (XP-6-09).
        expect(l10n.analyticsAvgLatency, 'Avg. time to text');
      },
    );

    testWidgets('gracefully omits the latency stat when no samples exist yet', (
      tester,
    ) async {
      // _mockData has no averageStopToTextMs set — defaults to null,
      // simulating recordings that exist but predate the latency KPI
      // (or a period with no successful pipeline completions yet).
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.analyticsAvgLatency), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
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

      // The period chips ride in the Overview section header at the top of
      // the dashboard. ensureVisible is kept so the tap survives a future
      // window size that scrolls the header out of view.
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

      // The reset button is the page's only WpButton.
      // Scroll to bring it into view before tapping.
      expect(find.byType(WpButton), findsOneWidget);
      await tester.ensureVisible(find.byType(WpButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WpButton));
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
      await tester.ensureVisible(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WpButton));
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
      await tester.ensureVisible(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WpButton));
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

    testWidgets('a successful reset reports the outcome, not the dialog title '
        '(UIA-ANA-02)', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.analyticsReset).last);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.analyticsResetDone), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed reset shows an error toast and keeps the page '
        '(UIA-ANA-02)', (tester) async {
      final db = _FailingResetDb();
      addTearDown(db.close);
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          db: db,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(WpButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.analyticsReset).last);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(l10n.errorGeneric), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
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

    // Removed 2026-08-11 (dark-only build): `renders without error in light
    // theme` (section 7, "Works in light theme"). There is one theme now.
  });

  // ---------------------------------------------------------------------------
  // UIA-ANA-01: an empty period keeps the period selector and says that this
  // period has no recordings, instead of the whole-page "no recordings yet".
  testWidgets(
    'an empty period keeps the selector and names the period (UIA-ANA-01)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(AnalyticsData.empty),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AnalyticsPage)),
      );
      container
          .read(analyticsPeriodProvider.notifier)
          .setPeriod(
            AnalyticsPeriod.values.firstWhere(
              (p) => p != AnalyticsPeriod.allTime,
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('No recordings in this period'), findsOneWidget);
      expect(find.text(l10n.analyticsEmptyTitle), findsNothing);
    },
  );

  // UIA-ANA-04: the cost and savings figures say they are estimates.
  testWidgets('the cost panel marks its figures as estimates (UIA-ANA-04)', (
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

    expect(
      find.text('Estimated from list prices per transcription'),
      findsOneWidget,
    );
  });

  // UIA-ANA-05: a screen reader hears the seven day values, not a blank image.
  testWidgets(
    'the activity chart announces its seven day values (UIA-ANA-05)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'1.*2.*3.*4.*5.*6.*7')),
        findsOneWidget,
      );
    },
  );

  // UIA-ANA-06: a quiet week says so instead of showing an empty chart.
  testWidgets(
    'a week without recordings says so above the chart (UIA-ANA-06)',
    (tester) async {
      const quietWeek = AnalyticsData(
        totalRecordings: 3,
        totalDurationMinutes: 4,
        totalWords: 20,
        timeSavedMinutes: 2,
        weeklyActivity: [0, 0, 0, 0, 0, 0, 0],
        modelUsage: <AnalyticsModelUsage>[],
        durationBuckets: [3, 0, 0, 0, 0],
        localSavingsUsd: 0,
        cloudCostUsd: 0,
      );
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(quietWeek),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No recordings in the last 7 days'), findsOneWidget);
    },
  );

  // UIA-ANA-07: counts share the thousands separator used by the hero stats.
  testWidgets(
    'counts in every panel use the same thousands separator (UIA-ANA-07)',
    (tester) async {
      const big = AnalyticsData(
        totalRecordings: 42,
        totalDurationMinutes: 120,
        totalWords: 5000,
        timeSavedMinutes: 80,
        weeklyActivity: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
        modelUsage: <AnalyticsModelUsage>[],
        durationBuckets: [1234, 0, 0, 0, 0],
        localSavingsUsd: 2.50,
        cloudCostUsd: 0.75,
      );
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(big),
          locale: const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1234'), findsNothing);
      expect(find.text('1.234'), findsWidgets);
    },
  );

  // UIA-ANA-08: an empty model list says that there is no model data yet.
  testWidgets(
    'an empty model list says so instead of a bare dash (UIA-ANA-08)',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(_mockData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNothing);
      expect(find.text('No model data in this period'), findsOneWidget);
    },
  );

  // UIA-ANA-11: the loading skeleton is announced to screen readers.
  testWidgets(
    'the loading skeleton is announced to screen readers (UIA-ANA-11)',
    (tester) async {
      final pending = Completer<AnalyticsData>();
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: [analyticsProvider.overrideWith((ref) => pending.future)],
          locale: const Locale('en'),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Loading statistics'), findsOneWidget);
    },
  );
}

class _FailingResetDb extends HistoryDatabase {
  _FailingResetDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> resetDailyStats() async {
    throw StateError('database is locked');
  }
}
