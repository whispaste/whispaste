import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';
import 'package:whispaste/widgets/wp_row_action.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpRowAction — semantics and keyboard', () {
    testWidgets('exposes its tooltip as the semantics label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRowAction(
            icon: LucideIcons.copy,
            tooltip: 'Copy text',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Copy text'), findsOneWidget);
    });

    testWidgets(
      'is focusable via Tab, activates on Enter, shows a focus ring',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: WpRowAction(
                icon: LucideIcons.star,
                tooltip: 'Pin to top',
                onTap: () => taps++,
              ),
            ),
          ),
        );

        expect(
          find.byType(WpFocusRing),
          findsOneWidget,
          reason:
              'focus must be drawn by WpFocusRing — one highlight per state',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(taps, 1);
      },
    );
  });

  group('WpRowActions — reveal without reflow', () {
    Widget group({required bool visible, bool dense = false}) => Center(
      child: SizedBox(
        width: 200,
        child: Row(
          children: [
            const Expanded(child: Text('Title')),
            WpRowActions(
              visible: visible,
              dense: dense,
              children: [
                WpRowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copy',
                  onTap: () {},
                  dense: dense,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    testWidgets('renders no action button while hidden', (tester) async {
      await tester.pumpWidget(makeTestable(group(visible: false)));
      await tester.pumpAndSettle();
      expect(find.byType(WpRowAction), findsNothing);
    });

    testWidgets('stays revealed while one of its actions holds focus', (
      tester,
    ) async {
      // Revealed by hover first, then the pointer state drops away while a
      // button still owns keyboard focus — the group must not collapse.
      await tester.pumpWidget(makeTestable(group(visible: true)));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byType(WpRowAction), findsOneWidget);

      await tester.pumpWidget(makeTestable(group(visible: false)));
      await tester.pumpAndSettle();

      expect(
        find.byType(WpRowAction),
        findsOneWidget,
        reason: 'collapsing under a focused button would strand the focus',
      );
    });
  });

  // #1845: on Windows, Tab from the list jumped straight to Delete, skipping
  // Copy and Star; Shift+Tab walked them all. Forward order must match.
  testWidgets('Tab reveals the hidden actions and walks them in order', (
    tester,
  ) async {
    Widget action(String name) => WpRowAction(
      key: ValueKey(name),
      icon: LucideIcons.copy,
      tooltip: name,
      onTap: () {},
      dense: true,
    );
    await tester.pumpWidget(
      makeTestable(
        Center(
          child: SizedBox(
            width: 300,
            child: Row(
              children: [
                const Expanded(child: TextField(key: ValueKey('list'))),
                WpRowActions(
                  visible: false,
                  dense: true,
                  children: [action('copy'), action('star'), action('trash')],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list')));
    await tester.pumpAndSettle();

    final order = <String>[];
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final ctx = FocusManager.instance.primaryFocus!.context!;
      final hit = ['copy', 'star', 'trash'].where(
        (n) => find
            .ancestor(
              of: find.byElementPredicate((e) => e == ctx),
              matching: find.byKey(ValueKey(n)),
            )
            .evaluate()
            .isNotEmpty,
      );
      order.add(hit.isEmpty ? '?' : hit.first);
    }
    expect(order, ['copy', 'star', 'trash']);
  });
}
