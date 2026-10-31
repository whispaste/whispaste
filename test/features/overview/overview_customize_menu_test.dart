import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_customize_menu.dart';
import 'package:whispaste/features/overview/overview_providers.dart';

import '../../fixtures/test_helpers.dart';

/// Hand-off test: an entry of "Übersicht anpassen" switches its block in the
/// stored overview state. Entries are found by key, never by label.
/// The menu entry by key. A [CheckboxMenuButton] hands its key to the inner
/// [MenuItemButton], so the finder names the checkbox entry by type.
Finder entry(String id) => find.byWidgetPredicate(
  (w) => w is CheckboxMenuButton && w.key == ValueKey('overview-customize-$id'),
);

void main() {
  testWidgets('switching a block off and the tips off is remembered', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: OverviewCustomizeMenu())),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OverviewCustomizeMenu)),
    );

    Future<void> choose(String id) async {
      await tester.tap(find.byKey(const ValueKey('overview-customize')));
      await tester.pumpAndSettle();
      await tester.tap(entry(id));
      await tester.pumpAndSettle();
    }

    await choose('recent');
    expect(container.read(overviewPrefsProvider).hiddenBlocks, {
      OverviewBlock.recent,
    });

    await choose('tips');
    expect(container.read(overviewPrefsProvider).tips.off, isTrue);

    await choose('recent');
    expect(container.read(overviewPrefsProvider).hiddenBlocks, isEmpty);
  });

  testWidgets('keyboard: Enter opens, Escape closes and returns the focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: OverviewCustomizeMenu())),
    );
    await tester.pumpAndSettle();

    // The trigger is the only focusable control: one Tab focuses it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'WpIconButton',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(entry('recent'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(entry('recent'), findsNothing);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'WpIconButton',
    );
  });
}
