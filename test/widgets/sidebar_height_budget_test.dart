/// Height-budget test for [WpSidebar] — the rail's rows are fixed-height and
/// its spacers cannot shrink below zero, so the only two things standing
/// between it and a hard RenderFlex overflow are the enforced window minimum
/// ([WpLayout.minWindowHeight]) and its scroll fallback. This file pins both.
///
/// Not covered here on purpose: text scale. The rail is icon-only, and an
/// [Icon] does not grow with `textScaler` — an accessibility-size run of this
/// widget would pass without ever touching the code it claims to test. The
/// scaled case that *is* meaningful (tooltips, labels) lives in
/// `sidebar_large_text_test.dart`; the starved-height case below is what
/// exercises the scroll fallback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart'
    show wpNavDividerAfterIds, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/sidebar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  /// The real production rail (7 nav items + group break + pinned settings)
  /// inside a box of exactly [height] — the room the app shell leaves it
  /// between title bar and status bar.
  Widget railInBox(double height) => makeTestable(
    Builder(
      builder: (context) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              WpSidebar(
                items: wpNavItems(L10n.of(context)),
                dividerAfterIds: wpNavDividerAfterIds,
                activeId: 'history',
                onItemTap: (_) {},
                bottomItems: [wpSettingsNavItem(L10n.of(context))],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// Collects the overflow errors Flutter reports but does not throw.
  List<String> captureOverflows(WidgetTester tester) {
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
    return overflows;
  }

  group('WpSidebar height budget', () {
    test('the enforced window minimum leaves the rail its full budget', () {
      // The window minimum is derived from this number, so this assertion is
      // trivially true by construction — what it guards is the arithmetic in
      // the token itself: 8 rows of 58 + one 24 dp group break + 16 dp bottom
      // inset = 504, plus 64 dp title bar and 48 dp status bar.
      //
      // The group break was 17 dp (a 1 px hairline in 2 × 8 dp of padding)
      // until Ticket 08 removed the line. Spacing has to say what the line
      // said, so it got 7 dp more — and the enforced window minimum grew with
      // it, 621 → 628, which is the direction this file's second test says to
      // take when the rail legitimately needs more room.
      expect(WpNavRail.rowHeight, 58);
      expect(WpNavRail.groupBreakHeight, 24);
      expect(WpNavRail.productionContentHeight, 504);
      expect(WpLayout.frameChromeHeight, 112);
      expect(WpLayout.windowFrameAllowance, 12);
      expect(WpLayout.minWindowHeight, 628);
      expect(
        WpLayout.minWindowHeight -
            WpLayout.frameChromeHeight -
            WpLayout.windowFrameAllowance,
        greaterThanOrEqualTo(WpNavRail.productionContentHeight),
        reason:
            'The window the app enforces must fit the rail it forces — and '
            '`minimumSize` is a window minimum, not a client-area one, so the '
            'frame allowance has to come off before the rail is measured',
      );
    });

    testWidgets('the real rail is no taller than its token budget', (
      tester,
    ) async {
      // Guards the direction the constant cannot: an eighth nav item, a
      // second group break or a taller pill would grow the real rail past
      // the number `minWindowHeight` is computed from.
      await tester.pumpWidget(railInBox(1000));
      await tester.pumpAndSettle();

      final railHeight = tester
          .renderObject<RenderBox>(
            find.descendant(
              of: find.byType(WpSidebar),
              matching: find.byType(IntrinsicHeight),
            ),
          )
          .getMaxIntrinsicHeight(WpLayout.sidebarWidth);

      expect(
        railHeight,
        lessThanOrEqualTo(WpNavRail.productionContentHeight),
        reason:
            'The rail grew past WpNavRail.productionContentHeight — raise '
            'that token (and with it WpLayout.minWindowHeight) instead of '
            'letting the window minimum lie about what the rail needs',
      );
    });

    testWidgets('no overflow at the enforced window minimum (800×621)', (
      tester,
    ) async {
      final overflows = captureOverflows(tester);

      // The worst case the minimum can produce, not the friendliest: on
      // Windows the platform hands the engine a client area smaller than the
      // window minimum by [WpLayout.windowFrameAllowance], so that is the
      // height the rail actually has to survive without scrolling.
      await tester.pumpWidget(
        railInBox(
          WpLayout.minWindowHeight -
              WpLayout.frameChromeHeight -
              WpLayout.windowFrameAllowance,
        ),
      );
      await tester.pumpAndSettle();

      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(tester.takeException(), isNull);

      // At the minimum the rail fits exactly, so the fallback must stay
      // inert — a rail that scrolls at the size the app enforces would be
      // the same bug wearing a scroll view.
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(
        position.maxScrollExtent,
        0,
        reason: 'The rail must not scroll at the enforced window minimum',
      );
    });

    testWidgets('starved height scrolls instead of overflowing', (
      tester,
    ) async {
      final overflows = captureOverflows(tester);

      // Far below anything `minimumSize` would allow — the case a tiling
      // window manager that ignores the request can still produce.
      await tester.pumpWidget(railInBox(300));
      await tester.pumpAndSettle();

      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(tester.takeException(), isNull);

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(
        position.maxScrollExtent,
        WpNavRail.productionContentHeight - 300,
        reason: 'Everything that does not fit must be reachable by scrolling',
      );

      await tester.drag(find.byType(WpSidebar), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rail shows no scrollbar chrome', (tester) async {
      await tester.pumpWidget(railInBox(300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(WpSidebar),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
        reason:
            'The rail is chrome itself — a track down its 72 dp would read '
            'as a second border on every page',
      );
    });
  });
}
