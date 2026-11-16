/// Tests for [AnalyticsPage].
///
/// Covers behaviour only: period chips (by testID), reset flow and its
/// service hand-over, error / loading / failed-panel states.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:drift/native.dart';
import 'package:whispaste/core/data/database.dart'
    show AnalyticsModelUsage, HistoryDatabase;
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
  dailyActivity: [1, 2, 3, 4, 5, 6, 7],
  modelUsage: <AnalyticsModelUsage>[],
  durationBuckets: [5, 3, 2, 1, 0],
  localSavingsUsd: 2.50,
  cloudCostUsd: 0.75,
);

List<Object> _dataOverrides(AnalyticsData data) => [
  analyticsProvider.overrideWith((ref) async => data),
  analyticsSnapshotProvider.overrideWith((ref) async => null),
];

late L10n l10n;

const _heatmap = ValueKey('analytics-activity-heatmap');
const _reset = ValueKey('analytics-reset');

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  AnalyticsData data, {
  HistoryDatabase? db,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const AnalyticsPage(),
      overrides: _dataOverrides(data),
      db: db,
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(AnalyticsPage)));
}

Future<void> _openResetDialog(WidgetTester tester) async {
  final button = find.byKey(_reset);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('an empty database shows no dashboard panels', (tester) async {
    await _pumpPage(tester, AnalyticsData.empty);

    expect(find.byKey(_heatmap), findsNothing);
    expect(find.byKey(_reset), findsNothing);
  });

  testWidgets('data renders the dashboard with heatmap and reset', (
    tester,
  ) async {
    await _pumpPage(tester, _mockData);

    expect(find.byKey(_heatmap), findsOneWidget);
    expect(find.byKey(_reset), findsOneWidget);
  });

  testWidgets('every period chip sets analyticsPeriodProvider', (tester) async {
    final container = await _pumpPage(tester, _mockData);

    for (final period in AnalyticsPeriod.values.reversed) {
      final chip = find.bySemanticsIdentifier(
        'analytics-period-${period.name}',
      );
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(container.read(analyticsPeriodProvider), period);
    }
  });

  testWidgets('an empty period keeps the period chips', (tester) async {
    final container = await _pumpPage(tester, AnalyticsData.empty);
    container
        .read(analyticsPeriodProvider.notifier)
        .setPeriod(AnalyticsPeriod.last7d);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier('analytics-period-last30d'),
      findsOneWidget,
    );
  });

  testWidgets('cancel in the reset dialog closes it without resetting', (
    tester,
  ) async {
    final db = _CountingResetDb();
    addTearDown(db.close);
    await _pumpPage(tester, _mockData, db: db);
    await _openResetDialog(tester);
    expect(
      find.byKey(const ValueKey('confirm-dialog-confirm')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confirm-dialog-confirm')), findsNothing);
    expect(find.byKey(_heatmap), findsOneWidget);
    expect(db.resetCalls, 0);
  });

  testWidgets('confirming the reset calls resetDailyStats once and '
      'announces it without a banner (#557)', (tester) async {
    final db = _CountingResetDb();
    addTearDown(db.close);
    await _pumpPage(tester, _mockData, db: db);
    await _openResetDialog(tester);
    expect(db.resetCalls, 0);
    tester.takeAnnouncements();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pump(const Duration(seconds: 1));

    expect(db.resetCalls, 1);
    expect(
      tester.takeAnnouncements().map((a) => a.message),
      contains(l10n.analyticsResetDone),
    );
    expect(
      find.byKey(const ValueKey('page-notice-analytics-reset-failed')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed reset shows a sticky error notice and keeps the page '
      '(UIA-ANA-02)', (tester) async {
    final db = _FailingResetDb();
    addTearDown(db.close);
    await _pumpPage(tester, _mockData, db: db);
    await _openResetDialog(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pump(const Duration(seconds: 1));

    const notice = ValueKey('page-notice-analytics-reset-failed');
    expect(find.byKey(notice), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(notice), findsOneWidget);
    expect(find.byKey(_heatmap), findsOneWidget);
  });

  testWidgets('a failing provider shows the page retry', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const AnalyticsPage(),
        overrides: [
          analyticsProvider.overrideWith(
            // An Error subclass skips Riverpod's Exception retry.
            (ref) => Future<AnalyticsData>.error(
              StateError('test error'),
              StackTrace.empty,
            ),
          ),
          analyticsSnapshotProvider.overrideWith((ref) async => null),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analytics-retry')), findsOneWidget);
    expect(find.byKey(_heatmap), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('while loading without snapshot no panels show', (tester) async {
    final pending = Completer<AnalyticsData>();
    await tester.pumpWidget(
      makeTestable(
        const AnalyticsPage(),
        overrides: [
          analyticsProvider.overrideWith((ref) => pending.future),
          analyticsSnapshotProvider.overrideWith((ref) async => null),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(find.byKey(_heatmap), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // #887: one failed query shows a retry in its own panel; the rest stays.
  testWidgets('a failed panel shows its own retry, the rest stays', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      const AnalyticsData(
        totalRecordings: 42,
        totalDurationMinutes: 120,
        totalWords: 5000,
        timeSavedMinutes: 80,
        dailyActivity: [1, 2, 3, 4, 5, 6, 7],
        modelUsage: <AnalyticsModelUsage>[],
        durationBuckets: [5, 3, 2, 1, 0],
        localSavingsUsd: 2.50,
        cloudCostUsd: 0.75,
        failedPanels: {AnalyticsPanel.wording},
      ),
    );

    expect(
      find.byKey(const ValueKey('analytics-wording-retry')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('analytics-retry')), findsNothing);
    expect(find.byKey(_heatmap), findsOneWidget);
    expect(find.byKey(_reset), findsOneWidget);
  });

  // #887: while the live figures load, the last snapshot is shown at once.
  testWidgets('shows the snapshot while the live figures load', (tester) async {
    final pending = Completer<AnalyticsData>();
    await tester.pumpWidget(
      makeTestable(
        const AnalyticsPage(),
        overrides: [
          analyticsProvider.overrideWith((ref) => pending.future),
          analyticsSnapshotProvider.overrideWith((ref) async => _mockData),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_heatmap), findsOneWidget);
  });
}

class _FailingResetDb extends HistoryDatabase {
  _FailingResetDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> resetDailyStats() async {
    throw StateError('database is locked');
  }
}

class _CountingResetDb extends HistoryDatabase {
  _CountingResetDb() : super.forTesting(NativeDatabase.memory());

  int resetCalls = 0;

  @override
  Future<void> resetDailyStats() async {
    resetCalls++;
  }
}
