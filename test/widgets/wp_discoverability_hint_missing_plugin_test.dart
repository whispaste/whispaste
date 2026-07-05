/// Regression test for [WpDiscoverabilityHint] under a missing
/// SharedPreferences plugin (issue 03, experience-perf-polish Cluster 2).
///
/// `test/screenshots/store_screenshots_test.dart` (the `golden_screenshot`
/// harness) never registers the shared_preferences mock channel, so the very
/// first `SharedPreferences.getInstance()` call throws
/// `MissingPluginException`. Kept in its own file (its own test isolate) so
/// no earlier test's `SharedPreferences.setMockInitialValues` call primes the
/// package's cached singleton before this scenario runs.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_discoverability_hint.dart';

import '../fixtures/test_helpers.dart';

const _hintText = 'Say “tag: name” to add a tag.';

void main() {
  testWidgets(
    'renders without crashing when the SharedPreferences plugin is unavailable',
    (tester) async {
      // No `SharedPreferences.setMockInitialValues` call anywhere in this
      // isolate — the method channel has no handler at all, exactly like the
      // golden_screenshot harness.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            null,
          );

      await tester.pumpWidget(
        makeTestable(
          const WpDiscoverabilityHint(
            hintId: 'test-hint',
            text: _hintText,
            isDark: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fails closed — never shows the hint rather than crashing the host page.
      expect(find.text(_hintText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
