/// Widget tests for [WpDiscoverabilityHint] — the reusable, one-time
/// discoverability hint used at both the voice-notes input field and the
/// history search field (issue 03, experience-perf-polish Cluster 2).
///
/// Covers:
///   AC1  Renders (dezent, theme-token-bound) when the "seen" flag is unset.
///   AC2  Stays hidden when the "seen" flag is already persisted.
///   AC3  Dismissing it hides it immediately AND persists the flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_discoverability_hint.dart';

import '../fixtures/test_helpers.dart';

const _hintText = 'Say “tag: name” to add a tag.';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the hint text when the seen-flag is unset', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const WpDiscoverabilityHint(hintId: 'test-hint', text: _hintText),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsOneWidget);
  });

  testWidgets('stays hidden when the seen-flag is already persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discoverability_hint_seen_test-hint': true,
    });

    await tester.pumpWidget(
      makeTestable(
        const WpDiscoverabilityHint(hintId: 'test-hint', text: _hintText),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsNothing);
  });

  testWidgets('dismissing the hint hides it and persists the seen-flag', (
    tester,
  ) async {
    late L10n l10n;
    l10n = await L10n.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      makeTestable(
        const WpDiscoverabilityHint(hintId: 'test-hint', text: _hintText),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_hintText), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(l10n.hintDismiss));
    await tester.pumpAndSettle();

    expect(find.text(_hintText), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('discoverability_hint_seen_test-hint'), isTrue);
  });
}
