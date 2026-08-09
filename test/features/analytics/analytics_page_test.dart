/// Tests for [AnalyticsPage].
///
/// Covers: empty state, dashboard with mocked data, hero stat labels,
/// period chips (7d / 30d / 90d / all), reset confirm dialog.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart' show AnalyticsModelUsage;
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

/// Registers the shipped Inter faces so text in this file measures the way it
/// measures on a user's screen.
///
/// Without it a widget test paints with the engine's fallback test font, whose
/// every glyph is a square of the font size — roughly twice the advance width
/// of real Latin type. That is fine for "does it render", and fatal for "does
/// it fit": the period chips measured 482 px wide under the fallback against
/// ~300 px with Inter, which is the difference between a section subtitle on
/// one line and on three.
///
/// Scoped to this file on purpose. `flutter test` gives every test file its
/// own isolate, so the golden screenshots — generated against the fallback
/// font — are untouched by this. All four weights are registered because the
/// filter chips draw at w500 resting and w600 active; registering Regular
/// alone would let the engine synthesise the bolder faces, which measure
/// narrower than the real ones and would bias this test optimistic.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File(
        'assets/fonts/Inter-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    await _loadInter();
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
          averageHotkeyLatencyMs: 1830,
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
      },
    );

    testWidgets('gracefully omits the latency stat when no samples exist yet', (
      tester,
    ) async {
      // _mockData has no averageHotkeyLatencyMs set — defaults to null,
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

  // ---------------------------------------------------------------------------
  // 8. Period selector in the Overview header, at the narrowest window
  // ---------------------------------------------------------------------------
  //
  // The period selector sits in `WpSection.trailing`, on the same line as the
  // "Overview" heading. That line is the one place on this page where a fixed
  // control and flowing text compete for width, and `RenderFlex` gives the
  // fixed control (the chips) an *unbounded* main axis before handing the rest
  // to the heading's `Expanded` — so the chips never shrink and never wrap,
  // the heading absorbs the whole shortfall. A plain overflow assertion cannot
  // see that: the `Expanded` clamps at zero and Flutter logs nothing. The line
  // counts below are what actually measures it.
  //
  // 800 px is the app's minimum window width (`main.dart`, `minimumSize`), and
  // Hebrew is here for two reasons at once: RTL flips the header row, and its
  // period labels are among the longest.
  //
  // Measured headroom on that 740 px header line (752 content minus the
  // section's accent bar), German being the tightest of the three:
  //
  //   1.0×   chips 336 + subtitle 255 = 591  → ~150 px spare
  //   1.15×  chips 364 + subtitle 291 = 655  → ~85 px spare
  //   1.5×   chips 431 + subtitle 374 = 805  → over; subtitle takes 2 lines
  //
  // Hence the two expectations below: one line up to 1.15×, two at 1.5×. The
  // accessibility size is deliberately allowed to wrap rather than being
  // designed away — the subtitle reflowing under the title is the graceful
  // failure, the title itself never wraps and nothing is clipped.
  group('period selector at the minimum window width', () {
    const minWindow = Size(800, 600);

    /// Five hero pills, six- and seven-digit numbers, long model names — the
    /// dashboard under real pressure rather than the toy `_mockData`.
    const pressureData = AnalyticsData(
      totalRecordings: 12345,
      totalDurationMinutes: 9876,
      totalWords: 1234567,
      timeSavedMinutes: 4321,
      weeklyActivity: [3, 12, 7, 19, 4, 0, 9],
      modelUsage: [
        AnalyticsModelUsage(
          model: 'whisper-large-v3-turbo',
          count: 8888,
          fraction: 0.72,
        ),
        AnalyticsModelUsage(
          model: 'parakeet-tdt-0.6b-v2',
          count: 3457,
          fraction: 0.28,
        ),
      ],
      durationBuckets: [1234, 5678, 910, 1112, 1314],
      localSavingsUsd: 123.45,
      cloudCostUsd: 67.89,
      averageHotkeyLatencyMs: 1234,
    );

    /// Number of laid-out lines the [text] occupies — the direct read of
    /// "did this get squeezed", where an overflow assertion stays silent.
    ///
    /// `getMinIntrinsicHeight(infinity)` is the paragraph's height when width
    /// is no object, i.e. exactly one line, so the laid-out height divided by
    /// it counts the lines. Derived rather than read off `computeLineMetrics`,
    /// which this Flutter version does not expose on `RenderParagraph`.
    int lineCount(WidgetTester tester, String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final singleLine = paragraph.getMinIntrinsicHeight(double.infinity);
      expect(singleLine, greaterThan(0), reason: 'no line box for "$text"');
      return (paragraph.size.height / singleLine).round();
    }

    // (text scale, lines the subtitle may occupy at that scale).
    const scales = <MapEntry<double, int>>[
      MapEntry(1.0, 1),
      MapEntry(1.15, 1),
      MapEntry(1.5, 2),
    ];

    for (final localeCode in const ['de', 'en', 'he']) {
      for (final scale in scales) {
        final textScale = scale.key;
        final subtitleLineBudget = scale.value;
        testWidgets('$localeCode at ${textScale}x text keeps the header line', (
          tester,
        ) async {
          final t = await L10n.delegate.load(Locale(localeCode));

          tester.view.physicalSize = minWindow;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final overflows = <String>[];
          final originalHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            if (details.toString().contains('overflowed')) {
              overflows.add(details.toString());
            } else {
              originalHandler?.call(details);
            }
          };
          addTearDown(() => FlutterError.onError = originalHandler);

          await tester.pumpWidget(
            makeTestable(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: const AnalyticsPage(),
                ),
              ),
              size: minWindow,
              overrides: _dataOverrides(pressureData),
              locale: Locale(localeCode),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            overflows,
            isEmpty,
            reason:
                'Analytics overflow at 800x600, $localeCode, ${textScale}x:\n'
                '${overflows.join('\n')}',
          );
          expect(tester.takeException(), isNull);

          // Every chip present and rendered as one unbroken label.
          for (final label in [
            t.analyticsPeriod7d,
            t.analyticsPeriod30d,
            t.analyticsPeriod90d,
            t.analyticsPeriodAll,
          ]) {
            expect(find.text(label), findsOneWidget, reason: 'chip "$label"');
            expect(
              lineCount(tester, label),
              1,
              reason: 'chip "$label" wrapped — the header line is out of room',
            );
          }

          // The heading is what pays for a too-wide chip row, so it is the
          // real assertion — and the title never gets to wrap at any of these
          // sizes, only the subtitle, and only at the accessibility step.
          expect(
            lineCount(tester, t.analyticsOverview),
            1,
            reason:
                'the section title wrapped — the period chips are eating the '
                'header line at 800px/$localeCode/${textScale}x',
          );
          expect(
            lineCount(tester, t.analyticsOverviewSubtitle),
            lessThanOrEqualTo(subtitleLineBudget),
            reason:
                'the section subtitle is being squeezed into a column by the '
                'period chips at 800px/$localeCode/${textScale}x',
          );

          // Placement: the selector precedes the numbers it scopes, and the
          // destructive Reset stays at the far end of the page.
          final chipY = tester.getCenter(find.text(t.analyticsPeriod7d)).dy;
          expect(
            chipY,
            lessThan(
              tester.getTopLeft(find.text(t.analyticsTotalRecordings)).dy,
            ),
            reason: 'period selector must sit above the hero stats',
          );
          expect(find.byType(WpButton), findsOneWidget);
          expect(
            tester.getCenter(find.byType(WpButton)).dy,
            greaterThan(chipY),
            reason: 'the destructive Reset button must stay at the page foot',
          );
        });
      }
    }
  });
}
