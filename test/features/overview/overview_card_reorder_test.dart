import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/overview/overview_customize_menu.dart';
import 'package:whispaste/features/overview/overview_movable_card.dart';
import 'package:whispaste/features/overview/overview_providers.dart';

import '../../fixtures/test_helpers.dart';

/// #1970: hand-off from the card grip and the "Übersicht anpassen" menu to
/// the stored order, and the stored order back into the page state.
/// Elements are found by key, never by label.

const _shownCards = [
  OverviewBlock.recent,
  OverviewBlock.notes,
  OverviewBlock.storage,
];

/// Three movable cards in the two columns of the wide layout, built from
/// the stored order and columns as the page builds them.
class _Column extends ConsumerWidget {
  const _Column();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(overviewPrefsProvider);
    final visible = [
      for (final b in prefs.blockOrder)
        if (_shownCards.contains(b)) b,
    ];
    Widget column(bool side) => Expanded(
      child: Column(
        children: [
          for (final b in visible)
            if (prefs.sideBlocks.contains(b) == side)
              OverviewMovableCard(
                key: ValueKey('card-${b.id}'),
                block: b,
                visible: visible,
                side: side,
                child: SizedBox(height: 160, child: Text(b.id)),
              ),
          if (ref.watch(overviewDragActiveProvider))
            OverviewColumnDrop(
              side: side,
              blocks: [
                for (final b in visible)
                  if (prefs.sideBlocks.contains(b) == side) b,
              ],
              visible: visible,
            ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column(false), column(true)],
    );
  }
}

Set<OverviewBlock> sideOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(_Column)),
).read(overviewPrefsProvider).sideBlocks;

Finder grip(OverviewBlock b) => find.byKey(ValueKey('overview-move-${b.id}'));

List<OverviewBlock> orderOf(WidgetTester tester, Type within) =>
    ProviderScope.containerOf(
      tester.element(find.byType(within)),
    ).read(overviewPrefsProvider).blockOrder;

void main() {
  late HistoryDatabase db;
  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));

  testWidgets('a stored order is read back into the page state', (
    tester,
  ) async {
    await tester.runAsync(
      () => db.writeAppSetting('overview_block_order', 'notes,recent'),
    );
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.runAsync(
      () => ProviderScope.containerOf(
        tester.element(find.byType(_Column)),
      ).read(overviewPrefsProvider.notifier).ready,
    );
    await tester.pumpAndSettle();
    final order = orderOf(tester, _Column);
    expect(
      order.indexOf(OverviewBlock.notes),
      lessThan(order.indexOf(OverviewBlock.recent)),
    );
    // The page follows the stored order.
    expect(
      tester.getTopLeft(find.text('notes')).dy,
      lessThan(tester.getTopLeft(find.text('recent')).dy),
    );
  });

  testWidgets('arrow keys on the grip move the card, store it and announce', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.pumpAndSettle();

    // The first Tab reaches the grip of the first card ("Letzte Aufnahmen").
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final order = orderOf(tester, _Column);
    expect(
      order.indexOf(OverviewBlock.recent),
      greaterThan(order.indexOf(OverviewBlock.notes)),
    );
    expect(tester.takeAnnouncements().map((a) => a.message), [contains('2')]);
    final stored = await tester.runAsync(
      () => db.readAppSetting('overview_block_order'),
    );
    expect(overviewBlockOrderFromStored(stored), order);

    // The focus stays on the moved grip: the next press moves it back.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(orderOf(tester, _Column), kOverviewDefaultBlockOrder);
  });

  testWidgets('dragging the grip onto another card takes its place', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.pumpAndSettle();

    final from = tester.getCenter(grip(OverviewBlock.notes));
    final to = tester.getCenter(find.byKey(const ValueKey('card-recent')));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('overview-move-drop-line')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final order = orderOf(tester, _Column);
    expect(
      order.indexOf(OverviewBlock.notes),
      lessThan(order.indexOf(OverviewBlock.recent)),
    );
  });

  testWidgets('arrow right moves a card into the side column and stores it', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.pumpAndSettle();
    expect(sideOf(tester).contains(OverviewBlock.recent), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(sideOf(tester).contains(OverviewBlock.recent), isTrue);
    expect(
      tester.getTopLeft(find.text('recent')).dx,
      greaterThan(tester.getTopLeft(find.text('notes')).dx),
    );
    expect(tester.takeAnnouncements(), isNotEmpty);
    final stored = await tester.runAsync(
      () => db.readAppSetting('overview_side_blocks'),
    );
    expect(overviewSideBlocksFromStored(stored), sideOf(tester));
  });

  testWidgets('dragging onto a card of the other column changes the column', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(grip(OverviewBlock.storage)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('card-recent'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(sideOf(tester).contains(OverviewBlock.storage), isFalse);
    final order = orderOf(tester, _Column);
    expect(
      order.indexOf(OverviewBlock.storage),
      lessThan(order.indexOf(OverviewBlock.recent)),
    );
  });

  testWidgets('the drop place at the end of the side column takes a card', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const Scaffold(body: _Column()), db: db),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(grip(OverviewBlock.notes)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final drop = find.byKey(const ValueKey('overview-column-drop-side'));
    expect(drop, findsOneWidget);
    await gesture.moveTo(tester.getCenter(drop));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(sideOf(tester).contains(OverviewBlock.notes), isTrue);
    final order = orderOf(tester, _Column);
    expect(
      order.indexOf(OverviewBlock.notes),
      greaterThan(order.indexOf(OverviewBlock.storage)),
    );
    expect(
      find.byKey(const ValueKey('overview-column-drop-side')),
      findsNothing,
    );
  });

  group('"Übersicht anpassen"', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('overview-customize')));
      await tester.pumpAndSettle();
    }

    double entryTop(WidgetTester tester, String id) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) =>
                w is CheckboxMenuButton &&
                w.key == ValueKey('overview-customize-$id'),
          ),
        )
        .dy;

    testWidgets('lists the cards in page order and moves with Alt+arrow', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const Scaffold(body: OverviewCustomizeMenu()), db: db),
      );
      await tester.pumpAndSettle();
      await open(tester);
      // The focus is on the first entry, the figures.
      expect(entryTop(tester, 'figures'), lessThan(entryTop(tester, 'recent')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      final order = orderOf(tester, OverviewCustomizeMenu);
      expect(order.take(2), [OverviewBlock.recent, OverviewBlock.figures]);
      expect(entryTop(tester, 'recent'), lessThan(entryTop(tester, 'figures')));
      expect(tester.takeAnnouncements(), isNotEmpty);
    });

    testWidgets('"Reihenfolge zurücksetzen" brings back the default order', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const Scaffold(body: OverviewCustomizeMenu()), db: db),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewCustomizeMenu)),
      );
      await open(tester);
      MenuItemButton reset() => tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('overview-customize-reset-order')),
      );
      expect(reset().onPressed, isNull);

      await tester.runAsync(
        () => container
            .read(overviewPrefsProvider.notifier)
            .setBlockOrder(
              overviewMoveBlockTo(
                kOverviewDefaultBlockOrder,
                OverviewBlock.community,
                target: OverviewBlock.figures,
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(reset().onPressed, isNotNull);
      await tester.runAsync(
        () => container
            .read(overviewPrefsProvider.notifier)
            .setBlockSide(OverviewBlock.figures, side: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('overview-customize-reset-order')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(overviewPrefsProvider).blockOrder,
        kOverviewDefaultBlockOrder,
      );
      final stored = await tester.runAsync(
        () => db.readAppSetting('overview_block_order'),
      );
      expect(overviewBlockOrderFromStored(stored), kOverviewDefaultBlockOrder);
      final side = await tester.runAsync(
        () => db.readAppSetting('overview_side_blocks'),
      );
      expect(overviewSideBlocksFromStored(side), kOverviewDefaultSideBlocks);
    });
  });
}
