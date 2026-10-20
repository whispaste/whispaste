/// Scroll-ownership guard (UX checklist, `.claude/agents/ux-reviewer.md`
/// section "Scroll-Besitz"). Runs in the normal suite.
///
/// For every screen (page or tab) at the minimum window size 800x716 and at
/// 1100x720, the primary vertical scroll area must
///   * own at least [kUxMinScrollShare] of the content pane's height, and
///   * start within [kUxMaxChromeAbove] of the pane's height, i.e. the fixed
///     chrome above the list (header, intro, tools) stays small.
///
/// Known failures carry a skip with the ticket that fixes them; the guard
/// tightens as those skips are removed. Set `UX_GUARD_MEASURE=1` to run the
/// skipped cases too and print the measured table.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;

import 'ux_fixtures.dart';

/// Primary scroll area must be at least this share of the content pane.
/// Rationale: WCAG 1.4.10 Reflow requires content to be usable without a
/// second scroll dimension; a list that owns less than 60 % of a 716 px window
/// shows barely one list row per screen, which is the failure the maintainer
/// reported on the Dictionary page. The 60 % floor leaves room for the page
/// header and one tool row on the smallest window.
const double kUxMinScrollShare = 0.60;

/// Fixed chrome above the primary list may take at most this share of the
/// pane. Rationale: NN/g on sticky headers asks for the least header height
/// that still gives readable targets; Microsoft's small-window class
/// (< 640 px wide, here 800 px as the app minimum) expects content to stay the
/// focus. 35 % of ~650 px is ~225 px, enough for a page header and a search
/// bar.
const double kUxMaxChromeAbove = 0.35;

/// Ticket that owns each known failure. Keyed by screen id from
/// `kUxScreens`. Empty means the guard is green for that screen.
const Map<String, String> kUxGuardSkips = {
  'history@800x716':
      'WP-82 / UX-031: Aufnahmen, Filterleiste umbricht ueber der Liste',
  'help@800x716': 'WP-82 / UX-032: Hilfe, leerer Kopfbereich ueber dem Inhalt',
  'analytics@800x716':
      'UX-035: Harness-Luecke, Statistik zeigt Leerzustand trotz Seeds',
  'analytics@1100x720':
      'UX-035: Harness-Luecke, Statistik zeigt Leerzustand trotz Seeds',
};

class _Measure {
  const _Measure({
    required this.share,
    required this.chrome,
    required this.hasScroll,
  });
  final double share;
  final double chrome;
  final bool hasScroll;
}

/// Finds the primary vertical scrollable (largest viewport) inside the pane
/// and measures it relative to the pane.
_Measure _measure(WidgetTester tester) {
  final pane = find.byKey(const ValueKey(kUxPaneKey));
  final paneSize = tester.getSize(pane);
  final paneTop = tester.getTopLeft(pane).dy;

  final elements = find
      .descendant(of: pane, matching: find.byType(Scrollable))
      .evaluate()
      .toList();
  Element? primary;
  double best = -1;
  for (final e in elements) {
    final s = e.widget as Scrollable;
    final vertical =
        s.axisDirection == AxisDirection.down ||
        s.axisDirection == AxisDirection.up;
    if (!vertical) continue;
    final h = tester
        .getSize(find.byElementPredicate((el) => identical(el, e)))
        .height;
    if (h > best) {
      best = h;
      primary = e;
    }
  }
  if (primary == null) {
    return const _Measure(share: 1, chrome: 0, hasScroll: false);
  }
  final target = find.byElementPredicate((el) => identical(el, primary));
  final viewport = tester.getSize(target);
  final top = tester.getTopLeft(target).dy - paneTop;
  return _Measure(
    share: viewport.height / paneSize.height,
    chrome: top / paneSize.height,
    hasScroll: true,
  );
}

void main() {
  setUpAll(() async => loadAppFonts());

  final measuring = Platform.environment['UX_GUARD_MEASURE'] == '1';
  final rows = <String>['screen | size | scroll share | chrome above | result'];

  // Not guarded, on purpose. The onboarding steps and the shell variants
  // (ux_fixtures.dart: kUxOnboardingSteps, kUxShellIds) are not in
  // kUxScreens, so this loop never sees them:
  //  - Onboarding has a fixed 1100x720 window and no list that owns the pane.
  //    Its fit without scrolling is asserted by onboarding_overlay_test.dart.
  //  - The shell variants carry an empty pane; the sidebar, title bar, dock and
  //    toast stack are window chrome, outside the content pane this guard
  //    measures.
  for (final screen in kUxScreens) {
    for (final size in kUxGuardSizes) {
      final name =
          '${screen.id} @ ${size.width.toInt()}x${size.height.toInt()}';
      final skipKey =
          '${screen.id}@${size.width.toInt()}x${size.height.toInt()}';
      final skip = (!measuring && kUxGuardSkips.containsKey(skipKey))
          ? kUxGuardSkips[skipKey]
          : null;
      testWidgets(
        skip == null ? 'ux-guard: $name' : 'ux-guard: $name (skip: $skip)',
        skip: skip != null,
        (tester) async {
          final db = await openSeededUxDatabase(tester);
          addTearDown(() => tester.runAsync(db.close));

          await pumpUxScreen(
            tester,
            screen: screen,
            db: db,
            size: size,
            scale: 1.0,
            theme: 'dark',
            locale: 'de',
          );
          final error = tester.takeException();
          expect(error, isNull, reason: 'layout exception on $name');

          final m = _measure(tester);
          // Let the screen's timers run out, otherwise the framework reports
          // them as pending after the test body.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 5));
          final ok =
              !m.hasScroll ||
              (m.share >= kUxMinScrollShare && m.chrome <= kUxMaxChromeAbove);
          rows.add(
            '${screen.id} | ${size.width.toInt()}x${size.height.toInt()} | '
            '${(m.share * 100).toStringAsFixed(0)} % | '
            '${(m.chrome * 100).toStringAsFixed(0)} % | '
            '${ok ? 'ok' : 'FAIL'}',
          );
          expect(
            m.share,
            greaterThanOrEqualTo(kUxMinScrollShare),
            reason: '$name: primary scroll area owns too little of the pane',
          );
          expect(
            m.chrome,
            lessThanOrEqualTo(kUxMaxChromeAbove),
            reason: '$name: fixed chrome above the primary list is too tall',
          );
        },
      );
    }
  }

  tearDownAll(() {
    if (measuring) {
      // ignore: avoid_print
      print(rows.join('\n'));
    }
  });
}
