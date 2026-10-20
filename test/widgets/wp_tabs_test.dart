import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_tabs.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('tapping a tab reports its index', (tester) async {
    int? picked;
    await tester.pumpWidget(
      makeTestable(
        WpTabs(
          labels: const ['Overview', 'Details', 'History'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );

    await tester.tap(find.text('History'));
    expect(picked, 2);
  });

  testWidgets('selected tab uses the accent, others textSecondary', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        WpTabs(
          labels: const ['Overview', 'Details'],
          selectedIndex: 1,
          onSelected: (_) {},
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('Details')).style?.color,
      WpColors.accent,
    );
    expect(
      tester.widget<Text>(find.text('Overview')).style?.color,
      WpColors.textSecondary,
    );
  });

  testWidgets('exposes the selected tab to semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        WpTabs(
          labels: const ['Overview', 'Details'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );

    final overview = tester.getSemantics(find.text('Overview'));
    expect(overview.flagsCollection.isSelected, ui.Tristate.isTrue);
    final details = tester.getSemantics(find.text('Details'));
    expect(details.flagsCollection.isSelected, ui.Tristate.isFalse);
    handle.dispose();
  });

  bool focusIsOn(WidgetTester tester, String label) =>
      Focus.of(tester.element(find.text(label))).hasFocus;

  testWidgets(
    'arrow keys move focus between tabs, Home and End jump to the ends',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpTabs(
            labels: const ['Overview', 'Details', 'History'],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(focusIsOn(tester, 'Overview'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(focusIsOn(tester, 'Details'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(focusIsOn(tester, 'History'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(focusIsOn(tester, 'Overview'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(
        focusIsOn(tester, 'History'),
        isTrue,
        reason: 'wraps at the start',
      );
    },
  );

  testWidgets('Left and Right are mirrored in RTL', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Directionality(
          textDirection: TextDirection.rtl,
          child: WpTabs(
            labels: const ['Overview', 'Details', 'History'],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(focusIsOn(tester, 'Overview'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(focusIsOn(tester, 'Details'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focusIsOn(tester, 'Overview'), isTrue);
  });

  testWidgets('the row is a tab bar and each label a tab with its identifier', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        WpTabs(
          labels: const ['Overview', 'Details'],
          selectedIndex: 0,
          onSelected: (_) {},
          itemIdentifiers: const ['tabs-overview', 'tabs-details'],
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsIdentifier('tabs-details')).role,
      SemanticsRole.tab,
    );
    expect(find.bySemanticsIdentifier('tabs-overview'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.role == SemanticsRole.tabBar,
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  Future<void> pumpOverflowing(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      makeTestable(
        Directionality(
          textDirection: direction,
          child: WpTabs(
            labels: List.generate(12, (i) => 'Tab number $i'),
            selectedIndex: 0,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double scrollOffset(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
      .controller!
      .offset;

  testWidgets('no chevron while all tabs fit', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      makeTestable(
        WpTabs(
          labels: const ['Overview', 'Details'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wp-tabs-scroll-start')), findsNothing);
    expect(find.byKey(const Key('wp-tabs-scroll-end')), findsNothing);
  });

  testWidgets(
    'end chevron scrolls one tab width and the start chevron appears',
    (tester) async {
      await pumpOverflowing(tester);
      expect(find.byKey(const Key('wp-tabs-scroll-start')), findsNothing);
      expect(find.byKey(const Key('wp-tabs-scroll-end')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wp-tabs-scroll-end')));
      await tester.pumpAndSettle();
      final afterOne = scrollOffset(tester);
      expect(afterOne, greaterThan(0));
      expect(find.byKey(const Key('wp-tabs-scroll-start')), findsOneWidget);

      await tester.tap(find.byKey(const Key('wp-tabs-scroll-start')));
      await tester.pumpAndSettle();
      expect(scrollOffset(tester), 0);
      expect(find.byKey(const Key('wp-tabs-scroll-start')), findsNothing);
    },
  );

  testWidgets('chevrons are mirrored under RTL', (tester) async {
    await pumpOverflowing(tester, direction: TextDirection.rtl);
    final startCenter = tester.getCenter(
      find.byKey(const Key('wp-tabs-scroll-end')),
    );
    final viewportCenter = tester.getCenter(find.byType(WpTabs));
    // Under RTL the scroll origin is on the right, so the trailing chevron is
    // on the left edge.
    expect(startCenter.dx, lessThan(viewportCenter.dx));

    await tester.tap(find.byKey(const Key('wp-tabs-scroll-end')));
    await tester.pumpAndSettle();
    final startChevron = tester.getCenter(
      find.byKey(const Key('wp-tabs-scroll-start')),
    );
    expect(startChevron.dx, greaterThan(viewportCenter.dx));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('wp-tabs-scroll-start')),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.chevron_right,
      reason: 'the start chevron points toward the start edge (right in RTL)',
    );
  });

  testWidgets('chevrons are labelled buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpOverflowing(tester);
    final end = tester.getSemantics(
      find.bySemanticsIdentifier('wp-tabs-scroll-end'),
    );
    expect(end.label, 'Show more tabs');
    expect(end.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('chevron hit area is at least 48 px wide', (tester) async {
    await pumpOverflowing(tester);
    final size = tester.getSize(find.byKey(const Key('wp-tabs-scroll-end')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a vertical mouse wheel scrolls the row sideways', (
    tester,
  ) async {
    await pumpOverflowing(tester);
    final center = tester.getCenter(find.byType(WpTabs));
    expect(scrollOffset(tester), 0);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), greaterThan(0));
  });

  testWidgets('each tab exposes its visible label as its accessible name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const labels = ['Overview', 'Details', 'History'];
    await tester.pumpWidget(
      makeTestable(
        WpTabs(labels: labels, selectedIndex: 0, onSelected: (_) {}),
      ),
    );

    for (final label in labels) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(node.label, label);
      expect(node.role, SemanticsRole.tab);
    }
    handle.dispose();
  });
}
