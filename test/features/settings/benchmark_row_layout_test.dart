/// Layout guard for the speech-section benchmark row (UX-066).
///
/// The benchmark row sits in the speech area of the Settings page. The page is
/// rendered in the real screenshot shell (sidebar, page header, content pane)
/// at the 800x716 app minimum, so the row's width is the same as in the app.
/// Any layout exception in that section (the benchmark row or the tier rows
/// next to it) fails the test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/record_device_listing_stub.dart';
import '../../ux_audit/ux_fixtures.dart';
import 'settings_area_fixture.dart';

/// The Settings page pinned to the speech area, built the way the screenshot
/// harness builds it.
UxScreen _speechSettings() => UxScreen(
  id: 'settings-speech-benchmark',
  activePageId: 'settings',
  build: () => ProviderScope(
    overrides: [settingsAreaAt(SettingsArea.speech)],
    child: const SettingsPage(),
  ),
);

Future<void> _pumpAndExpectNoLayoutException(
  WidgetTester tester, {
  required double scale,
  required String theme,
  required String locale,
}) async {
  final db = await openSeededUxDatabase(tester);
  addTearDown(() => tester.runAsync(db.close));

  await pumpUxScreen(
    tester,
    screen: _speechSettings(),
    db: db,
    size: kUxSizeMinimum,
    scale: scale,
    theme: theme,
    locale: locale,
  );

  expect(tester.takeException(), isNull);
  expect(
    find.byKey(const ValueKey('settings-row-speech-benchmark')),
    findsOneWidget,
  );
}

void main() {
  setUpAll(stubRecordDeviceListing);

  testWidgets(
    'benchmark row lays out without overflow at 800x716, text scale 2.0, dark, de',
    (tester) => _pumpAndExpectNoLayoutException(
      tester,
      scale: 2.0,
      theme: 'dark',
      locale: 'de',
    ),
  );

  testWidgets(
    'benchmark row lays out without overflow at 800x716, text scale 2.0, navy, de',
    (tester) => _pumpAndExpectNoLayoutException(
      tester,
      scale: 2.0,
      theme: 'navy',
      locale: 'de',
    ),
  );

  testWidgets(
    'benchmark row lays out without overflow at 800x716, text scale 1.0, dark, de',
    (tester) => _pumpAndExpectNoLayoutException(
      tester,
      scale: 1.0,
      theme: 'dark',
      locale: 'de',
    ),
  );

  testWidgets(
    'benchmark row lays out without overflow at 800x716, text scale 2.0, dark, he (RTL)',
    (tester) => _pumpAndExpectNoLayoutException(
      tester,
      scale: 2.0,
      theme: 'dark',
      locale: 'he',
    ),
  );
}
