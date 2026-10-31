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
import 'package:whispaste/core/theme/colors.dart';
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

    // Removed 2026-08-11 (dark-only build): `renders without error in light
    // theme` (section 7, "Works in light theme"). There is one theme now.
  });

  // ---------------------------------------------------------------------------
  // 8. Color assignment — nominal for models, ordinal for durations (Ticket 14)
  // ---------------------------------------------------------------------------
  //
  // Both panels used to paint the same accent gradient, so the color said only
  // "this is a bar". They now carry two *different* kinds of meaning, and the
  // point of the tests below is that the two kinds stay apart: models are an
  // unordered set and get distinct hues, durations are an ordered one and get a
  // single hue at rising weight.

  group('bar colors', () {
    /// Three models and five non-empty duration buckets — every bar and every
    /// ramp rung actually gets painted. (`_mockData` ends on a zero bucket,
    /// whose bar has zero width and would let a missing rung pass unnoticed.)
    const colorData = AnalyticsData(
      totalRecordings: 42,
      totalDurationMinutes: 120,
      totalWords: 5000,
      timeSavedMinutes: 80,
      weeklyActivity: [1, 2, 3, 4, 5, 6, 7],
      modelUsage: [
        AnalyticsModelUsage(model: 'whisper-small', count: 20, fraction: 0.5),
        AnalyticsModelUsage(model: 'whisper-medium', count: 12, fraction: 0.3),
        AnalyticsModelUsage(
          model: 'whisper-large-v3-turbo',
          count: 8,
          fraction: 0.2,
        ),
      ],
      durationBuckets: [5, 4, 3, 2, 1],
      localSavingsUsd: 2.50,
      cloudCostUsd: 0.75,
    );

    /// Solid fills painted by [ColoredBox] — the model bars and both tracks.
    List<Color> coloredBoxFills(WidgetTester tester) => tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((b) => b.color)
        .toList();

    /// Fills painted through a [BoxDecoration] — the duration bars.
    List<Color> decorationFills(WidgetTester tester) => tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .whereType<Color>()
        .toList();

    List<Gradient> decorationGradients(WidgetTester tester) => tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<Gradient>()
        .toList();

    // The `light` row went with the light stack (2026-08-11): it pumped the
    // same page at `Brightness.light` and asked the duration ramp for its
    // light derivation, neither of which the app can produce any more.
    testWidgets('dark: every model bar wears its own slot', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(colorData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final fills = coloredBoxFills(tester);
      final expected = [
        for (final id in const [
          'whisper-small',
          'whisper-medium',
          'whisper-large-v3-turbo',
        ])
          categorySlotForModel(id).color(),
      ];
      expect(
        expected.toSet(),
        hasLength(3),
        reason:
            'two of the three shipped models resolve to one hue — a nominal '
            'scale whose members collide cannot separate its categories',
      );
      for (final color in expected) {
        expect(
          fills,
          contains(color),
          reason:
              'dark: no bar is painted in '
              '#${color.toARGB32().toRadixString(16)} — the model bars are '
              'not reaching their category slot',
        );
      }
    });

    testWidgets('dark: the duration bars are one hue at five weights', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(colorData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // `iris` named outright rather than read back off the widget: the point
      // of the assertion is *which* slot the ramp comes from. It is not the
      // brand accent (Ticket 11, ② = b) and it is not one of the model hues
      // one panel up, and both only hold as long as the source is pinned.
      final ramp = WpCategorySlot.iris.ramp(5);
      final fills = decorationFills(tester);
      for (final rung in ramp) {
        expect(
          fills,
          contains(rung),
          reason:
              'dark: the duration panel is missing the rung '
              '#${rung.toARGB32().toRadixString(16)} — an ordinal scale with '
              'a gap in it no longer reads as ordered',
        );
      }
      expect(
        ramp.toSet(),
        hasLength(5),
        reason:
            'dark: two rungs of the duration ramp resolve to the same '
            'color — the scale has fewer steps than buckets',
      );
    });

    testWidgets('the brand gradient is off this page entirely', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: _dataOverrides(colorData),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Zero. This number has only ever gone down, and each step had the same
      // reason: the gradient marks a *selection*, and nothing on a dashboard
      // is selected.
      //
      // It was seven — the three `WpSection`s each hung a 3 px accent bar
      // beside their heading, which Ticket 08 removed as a generic
      // interaction accent on a non-interactive heading. It was then four,
      // one 2 px strip per hero pill, and those were the last: a pill is not
      // tappable either, so the strip promised the same interaction the
      // removed hover highlight had promised, and wearing it on every tile
      // meant the row had four equally loud cells and no lead (ticket 32,
      // finding B4). The lead pill is now marked by the elevated rung of the
      // card material instead — a difference in weight rather than a badge.
      //
      // Guarded here rather than trusted: `analytics_page.dart` still names
      // the token in its comments, so a source grep would not see the
      // difference between explaining the removal and undoing it.
      expect(
        decorationGradients(
          tester,
        ).where((g) => g == WpColorsDark.accentWarmGradient).length,
        0,
        reason:
            'the accent gradient is back on the analytics page. It marks the '
            'sidebar\'s active rail item and nothing else — a statistic is '
            'not a selection, and neither is a section heading',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 9. The narrowest window — period selector in the header, hero numbers below
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
  group('at the minimum window width', () {
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

    // -------------------------------------------------------------------------
    // The hero number at the same pressure.
    //
    // Ticket 14 moved the value from `headlineMedium` (16) to `headlineLarge`
    // (22) so it clears its 11 px caption by 2:1 instead of 1.45:1. That is a
    // ~38 % wider number inside a pill only ~110 px wide at the minimum window,
    // and the failure mode is silent in both directions: `maxLines: 1` clips
    // without raising the overflow assertion the group above watches for, and
    // without it the number wraps and leaves one pill taller than its four
    // neighbours. Hence the `FittedBox` — which cannot overflow by
    // construction, so the two measurements worth taking are what it *costs*
    // where it engages, and that the 22 px rung is real rather than nominal
    // everywhere else.
    //
    // Measured against `pressureData`: 1,234,567 words and 164 h of audio, the
    // longest strings the five formatters can produce.
    //
    // The room, measured rather than assumed (`getMaxIntrinsicWidth` of the
    // widest of the five values, against ~104 px of pill):
    //
    //   de   1.0×  ~104 → fits        1.15×  117 → scaled
    //   en   1.0×  ~104 → fits        1.15×  117 → scaled
    //   he   1.0×   124 → scaled      1.15×  143 → scaled
    //
    // Hebrew is the tightest of the three here as it is in the header group
    // above, and it is the reason the guard exists at all rather than the 22 px
    // simply being declared safe.
    // -------------------------------------------------------------------------

    for (final localeCode in const ['de', 'en', 'he']) {
      for (final textScale in const [1.0, 1.15]) {
        testWidgets('$localeCode at ${textScale}x: hero value stays >= 16 px', (
          tester,
        ) async {
          final t = await L10n.delegate.load(Locale(localeCode));

          tester.view.physicalSize = minWindow;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

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

          // Every hero label is present, so every hero value is too — the
          // values themselves are locale-formatted and not worth restating
          // here; the label is the stable handle on the pill.
          for (final label in [
            t.analyticsTotalRecordings,
            t.analyticsTotalDuration,
            t.analyticsWordsDictated,
            t.analyticsTimeSaved,
          ]) {
            expect(find.text(label), findsOneWidget, reason: 'pill "$label"');
          }

          final values = tester.renderObjectList<RenderParagraph>(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  w.style?.fontSize == 22 &&
                  w.style?.fontWeight == FontWeight.w700,
            ),
          );
          expect(
            values.length,
            5,
            reason:
                'expected five hero values at the 22 px rung — '
                '`pressureData` has a latency sample, so all five pills render',
          );

          // A `BoxFit.scaleDown` box cannot overflow by construction, so "is it
          // cut" is not the question worth asking — "how much did it give up"
          // is. The box lays its child out unbounded and then sizes itself to
          // `min(child, available)`, so the ratio of the two is the scale the
          // number is actually painted at.
          final boxes = find.byWidgetPredicate(
            (w) => w is FittedBox && w.fit == BoxFit.scaleDown,
          );
          expect(tester.widgetList(boxes), hasLength(5));

          for (var i = 0; i < 5; i++) {
            final scale =
                tester.getSize(boxes.at(i)).width /
                values.elementAt(i).size.width;
            expect(
              scale,
              lessThanOrEqualTo(1.0001),
              reason:
                  'hero value $i was scaled *up*, which scaleDown cannot do',
            );
            // `scale * 22` is the rung the value effectively renders at *before*
            // the user's text scaler — the same footing as the 16 it is compared
            // against, since that rung was scaled too. The floor is therefore
            // the rung this ticket replaced: whatever the guard gives up at the
            // narrow extremes, the number may never come out smaller than it
            // was before. The worst case measures 15.993 (he, 1.15×), i.e. the
            // guard hands back the whole type increase there and not a pixel
            // more, so the half-pixel of tolerance is float slack, not headroom.
            // If this fires, the hero row has genuinely run out of width and the
            // fix is the row (fewer pills per line), not a smaller number.
            expect(
              scale * 22,
              greaterThanOrEqualTo(15.5),
              reason:
                  'hero value $i renders at an effective rung of '
                  '${(scale * 22).toStringAsFixed(3)} px at '
                  '800px/$localeCode/${textScale}x — below the 16 px rung it '
                  'had before Ticket 14, so the type change has been undone by '
                  'the guard that was meant to protect it',
            );
          }
        });
      }
    }

    // The other half of the guarantee: the `FittedBox` is a safety net for the
    // narrow extremes, not a licence to ship a smaller number everywhere. Under
    // the same seven-digit pressure at the minimum window, plain text size, the
    // Latin locales render the value at the full 22 px rung — unscaled.
    for (final localeCode in const ['de', 'en']) {
      testWidgets('$localeCode: the hero value keeps its full 22 px rung', (
        tester,
      ) async {
        tester.view.physicalSize = minWindow;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          makeTestable(
            const AnalyticsPage(),
            size: minWindow,
            overrides: _dataOverrides(pressureData),
            locale: Locale(localeCode),
          ),
        );
        await tester.pumpAndSettle();

        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.style?.fontSize == 22 &&
                w.style?.fontWeight == FontWeight.w700,
          ),
        );
        expect(
          paragraphs.length,
          5,
          reason:
              'expected five hero values at the 22 px rung — `pressureData` '
              'has a latency sample, so all five pills render',
        );

        final boxes = find.byWidgetPredicate(
          (w) => w is FittedBox && w.fit == BoxFit.scaleDown,
        );
        for (var i = 0; i < 5; i++) {
          final painted = tester.getRect(boxes.at(i)).width;
          final unscaled = paragraphs.elementAt(i).size.width;
          expect(
            painted,
            closeTo(unscaled, 0.5),
            reason:
                'hero value $i is being scaled down to '
                '${(painted / unscaled * 100).toStringAsFixed(0)}% at '
                '800px/$localeCode — a normal dashboard must get the whole '
                '22 px, or the type rung the ticket bought is fiction',
          );
        }
      });
    }
  });
}
