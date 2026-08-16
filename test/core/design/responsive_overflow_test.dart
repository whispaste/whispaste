/// Responsive overflow audit — pumps every page at multiple window sizes
/// and asserts no RenderFlex overflow errors.
///
/// CI-gating: ensures the app works from small laptops to ultrawide monitors.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/empty_state.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;

// ---------------------------------------------------------------------------
// Window sizes to test — covers common desktop form factors
//
// The narrow entry deliberately sits *below* the window minimum the app
// enforces ([WpLayout.minWindowHeight], 628 dp): these cases pump a bare page
// without the app chrome, so a page that survives 800 × 600 here has more room
// than it will ever get inside the real shell. The nav rail's own height
// budget, which is what sets that minimum, is pinned separately in
// `test/widgets/sidebar_height_budget_test.dart` — no page in this file
// renders the rail at all.
// ---------------------------------------------------------------------------
const _sizes = <MapEntry<String, Size>>[
  MapEntry('small laptop', Size(1024, 768)),
  MapEntry('HD', Size(1280, 800)),
  MapEntry('Full HD', Size(1920, 1080)),
  MapEntry('QHD', Size(2560, 1440)),
  MapEntry('narrow window', Size(800, 600)),
];

// ---------------------------------------------------------------------------
// Pages to test
// ---------------------------------------------------------------------------
final _pages = <MapEntry<String, Widget>>[
  const MapEntry('History', HistoryPage()),
  const MapEntry('Settings', SettingsPage()),
  const MapEntry('Replacements', ReplacementsPage()),
  const MapEntry('Analytics', AnalyticsPage()),
  const MapEntry('About', AboutPage()),
  const MapEntry('Feedback', FeedbackPage()),
];

/// Analytics with something to draw: long model names and five-digit counts,
/// so the page's fixed-width text boxes are actually under pressure. The
/// empty-state path exercises none of them.
const _populatedAnalytics = AnalyticsData(
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

/// Wraps page in the real theme + ProviderScope at a given size.
Widget _testShell(
  Widget page,
  Size size, {
  double textScale = 1.0,
  // A seeded database for the cases that need History to render *rows*. When
  // null, the three entry streams are stubbed empty (the default here, which
  // keeps the size sweep free of pending Drift timers); when given, the real
  // providers run against it so the list, its cards and the detail panel are
  // actually laid out. See the accessibility-text-size group below for why
  // an empty History is not enough there.
  HistoryDatabase? seededDb,
  // Untyped for the same reason `test_helpers.dart` does it: this Riverpod
  // version does not export the `Override` type name.
  List extraOverrides = const [],
}) {
  final theme = wpDarkTheme();
  return ProviderScope(
    overrides: [
      if (seededDb != null)
        historyDatabaseProvider.overrideWithValue(seededDb)
      else ...[
        historyDatabaseProvider.overrideWith((ref) {
          final db = HistoryDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        // Provide instant empty streams to avoid pending Drift timers.
        historyEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      hw.gpuInfoProvider.overrideWith(
        (ref) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Scaffold(body: page),
        ),
      ),
    ),
  );
}

/// Titles for the seeded History fixture. Deliberately long and unbroken:
/// an enlarged system font clips where a string cannot wrap, and a fixture of
/// three-word titles would pass every width.
const _seededTitles = <String>[
  'Quarterly planning session with the whole distributed platform team',
  'Podcast outline — episode 14, dictation-first workflows',
  'Bug report: hotkey stops responding after the display sleeps',
];

/// Rows for the accessibility-text-size cases below. Mirrors the fixture in
/// `history_detail_accent_audit_test.dart`, with longer copy.
Future<void> _seedHistory(HistoryDatabase db) async {
  final now = DateTime.now();
  for (final (i, title) in _seededTitles.indexed) {
    await db
        .into(db.historyEntries)
        .insert(
          HistoryEntriesCompanion(
            id: Value('overflow-$i'),
            title: Value(title),
            content: Value(
              '$title — a transcript body long enough that the detail '
              'panel has to wrap it several times at an accessibility text '
              'size, which is the case this fixture exists for.',
            ),
            timestamp: Value(now.subtract(Duration(minutes: 5 * (i + 1)))),
            durationSec: const Value(128.0),
            processingDurationSec: const Value(1.4),
            language: const Value('en'),
            model: const Value('whisper-large-v3-turbo'),
            isLocal: const Value(true),
            source: const Value('dictation'),
            colorSlot: Value(i),
          ),
        );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Test each page at each size — checks for RenderFlex overflow
  for (final page in _pages) {
    group('${page.key} responsive', () {
      for (final sizeEntry in _sizes) {
        testWidgets(
          '${sizeEntry.key} (${sizeEntry.value.width.toInt()}×${sizeEntry.value.height.toInt()})',
          (tester) async {
            tester.view.physicalSize = sizeEntry.value;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            // Capture overflow errors that Flutter logs (but doesn't throw)
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

            // Seeded for every page: only Analytics reads it, and without a
            // seed it renders WpEmptyState — so the dashboard itself (period
            // chips next to the Reset button, the duration bars' fixed label
            // columns) would never be laid out at any of these sizes.
            await tester.pumpWidget(
              _testShell(
                page.value,
                sizeEntry.value,
                extraOverrides: [
                  analyticsProvider.overrideWith(
                    (ref) async => _populatedAnalytics,
                  ),
                ],
              ),
            );
            await tester.pumpAndSettle();

            if (page.key == 'Analytics') {
              expect(
                find.byType(WpEmptyState),
                findsNothing,
                reason:
                    'Analytics must render seeded data, not the empty state',
              );
            }

            expect(
              overflows,
              isEmpty,
              reason:
                  '${page.key} overflow at ${sizeEntry.key}:\n${overflows.join('\n')}',
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.key} exception at ${sizeEntry.key}',
            );
          },
        );
      }
    });
  }

  // Extra: the pages whose frame ticket 07 unified (About moved to
  // WpSection's 16px headline, Settings to WpPageShell) — checked at an
  // accessibility text size, where a grown section head is most likely to
  // push a row over the edge.
  //
  // Analytics joins them: it is the page with the most hard-coded text boxes
  // in the app (the duration bars pin their label and count to fixed widths),
  // which is exactly the shape that survives every window size and still
  // clips the moment the system font grows. It needs seeded data to say
  // anything at all — with an empty database it renders the empty state and
  // none of those boxes exist, so the size sweep above never sees them.
  for (final page in const <MapEntry<String, Widget>>[
    MapEntry('About', AboutPage()),
    MapEntry('Settings', SettingsPage()),
    MapEntry('Analytics', AnalyticsPage()),
  ]) {
    testWidgets('${page.key} at textScaler 1.5', (tester) async {
      const size = Size(1280, 800);
      tester.view.physicalSize = size;
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
        _testShell(
          page.value,
          size,
          textScale: 1.5,
          extraOverrides: [
            analyticsProvider.overrideWith((ref) async => _populatedAnalytics),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Guard against a hollow pass: if the override ever stops taking, the
      // page falls back to its empty state and this case silently stops
      // testing the fixed-width boxes it exists for.
      if (page.key == 'Analytics') {
        expect(
          find.byType(WpEmptyState),
          findsNothing,
          reason: 'Analytics must render seeded data, not the empty state',
        );
      }

      expect(
        overflows,
        isEmpty,
        reason: '${page.key} overflow at 1.5x text:\n${overflows.join('\n')}',
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Extra: History at an accessibility text size, with rows on screen.
  //
  // This is the project's "check the layout at an enlarged system font"
  // convention, and History is the screen Ticket 13 owes it on. The group
  // above cannot stand in for it: it stubs the three entry streams empty, so
  // History renders `WpEmptyState` and none of the geometry the check is
  // about — the card padding, the metadata row under each title, the detail
  // panel's header — is ever laid out. The two "narrow detail panel" cases
  // below have the same hole; they tap `GestureDetector` #3 only `if` more
  // than three exist, and with an empty list they never do.
  //
  // 1.5 is the same rung About/Settings/Analytics are checked at. Two widths:
  // the group's reference size, and the narrowest one where the list and the
  // detail panel still share the window.
  //
  // Only the default (list) view mode is covered — switching modes needs the
  // settings provider the page reads its mode from, which is outside this
  // file's shell. The card grid's own geometry is pinned separately in
  // `history_card_multiselect_test.dart`.
  for (final narrow in <Size>[const Size(1280, 800), const Size(1024, 768)]) {
    testWidgets(
      'History with entries at textScaler 1.5 (${narrow.width.toInt()}×${narrow.height.toInt()})',
      (tester) async {
        tester.view.physicalSize = narrow;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await _seedHistory(db);

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
          _testShell(const HistoryPage(), narrow, textScale: 1.5, seededDb: db),
        );
        await tester.pumpAndSettle();

        // Guard against a hollow pass: without rows this case degenerates
        // into the empty-state check the sweep above already does.
        expect(
          find.byType(WpEmptyState),
          findsNothing,
          reason: 'History must render the seeded rows, not the empty state',
        );

        // Open the detail panel — the half of the screen the size sweep
        // never reaches, and the one with the most text in the least width.
        await tester.tap(find.text(_seededTitles.first).first);
        await tester.pumpAndSettle();

        expect(
          overflows,
          isEmpty,
          reason:
              'History overflow at 1.5x text, ${narrow.width.toInt()}×'
              '${narrow.height.toInt()}:\n${overflows.join('\n')}',
        );
        expect(tester.takeException(), isNull);

        // Drift's stream queries schedule a cleanup timer when their last
        // listener goes away, and Riverpod drops those listeners while the
        // tree is being unmounted — too late for flutter_test, which checks
        // for pending timers straight after the body. Tear the tree down
        // inside the body instead, so the cleanup runs while the fake clock
        // is still turning. (Same idiom as
        // `history_detail_accent_audit_test.dart`.)
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  // Extra: test History with narrow detail panel (common overflow source)
  for (final narrow in [const Size(900, 700), const Size(1024, 600)]) {
    testWidgets(
      'History narrow detail panel at ${narrow.width.toInt()}×${narrow.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = narrow;
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

        await tester.pumpWidget(_testShell(const HistoryPage(), narrow));
        await tester.pumpAndSettle();

        // Tap first entry to open detail panel
        final entries = find.byType(GestureDetector);
        if (entries.evaluate().length > 3) {
          await tester.tap(entries.at(3));
          await tester.pumpAndSettle();
        }

        expect(
          overflows,
          isEmpty,
          reason:
              'History detail panel overflow at ${narrow.width}×${narrow.height}:\n${overflows.join('\n')}',
        );
      },
    );
  }
}
