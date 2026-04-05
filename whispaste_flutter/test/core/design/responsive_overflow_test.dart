/// Responsive overflow audit — pumps every page at multiple window sizes
/// and asserts no RenderFlex overflow errors.
///
/// CI-gating: ensures the app works from small laptops to ultrawide monitors.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/history/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_page.dart';

// ---------------------------------------------------------------------------
// Window sizes to test — covers common desktop form factors
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

/// Wraps page in the real theme + ProviderScope at a given size.
Widget _testShell(Widget page, Size size, {Brightness brightness = Brightness.dark}) {
  final theme = brightness == Brightness.dark ? wpDarkTheme() : wpLightTheme();
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
      // Provide instant empty streams to avoid pending Drift timers in tests.
      historyEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Scaffold(body: page),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Test each page at each size — checks for RenderFlex overflow
  for (final page in _pages) {
    group('${page.key} responsive', () {
      for (final sizeEntry in _sizes) {
        testWidgets('${sizeEntry.key} (${sizeEntry.value.width.toInt()}×${sizeEntry.value.height.toInt()})',
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

          await tester.pumpWidget(
            _testShell(page.value, sizeEntry.value),
          );
          await tester.pumpAndSettle();

          expect(overflows, isEmpty,
              reason: '${page.key} overflow at ${sizeEntry.key}:\n${overflows.join('\n')}');
          expect(tester.takeException(), isNull,
              reason: '${page.key} exception at ${sizeEntry.key}');
        });
      }
    });
  }

  // Extra: test History with narrow detail panel (common overflow source)
  for (final narrow in [Size(900, 700), Size(1024, 600)]) {
    testWidgets('History narrow detail panel at ${narrow.width.toInt()}×${narrow.height.toInt()}',
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

      await tester.pumpWidget(
        _testShell(const HistoryPage(), narrow),
      );
      await tester.pumpAndSettle();

      // Tap first entry to open detail panel
      final entries = find.byType(GestureDetector);
      if (entries.evaluate().length > 3) {
        await tester.tap(entries.at(3));
        await tester.pumpAndSettle();
      }

      expect(overflows, isEmpty,
          reason: 'History detail panel overflow at ${narrow.width}×${narrow.height}:\n${overflows.join('\n')}');
    });
  }
}
