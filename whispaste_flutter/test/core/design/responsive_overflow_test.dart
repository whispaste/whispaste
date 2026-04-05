/// Responsive overflow audit — pumps every page at multiple window sizes
/// and asserts no RenderFlex overflow errors.
///
/// CI-gating: ensures the app works from small laptops to ultrawide monitors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
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
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
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

          await tester.pumpWidget(
            _testShell(page.value, sizeEntry.value),
          );
          await tester.pumpAndSettle();

          // If we get here without a RenderFlex overflow exception,
          // the page handles this size correctly.
          expect(tester.takeException(), isNull,
              reason: '${page.key} overflowed at ${sizeEntry.key}');
        });
      }
    });
  }
}
