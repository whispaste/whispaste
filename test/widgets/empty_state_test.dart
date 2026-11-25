import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/empty_state.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpEmptyState', () {
    testWidgets('action button is not shown when actionLabel is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(icon: LucideIcons.plus, title: 'Empty'),
        ),
      );

      expect(find.byType(WpButton), findsNothing);
    });

    testWidgets('action button fires callback on tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        makeTestable(
          WpEmptyState(
            icon: LucideIcons.plus,
            title: 'Empty',
            actionLabel: 'Add Item',
            onAction: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(WpButton));
      expect(tapped, isTrue);
    });
  });

  // #1845: on the Windows test laptop the example chips under the action sat
  // below the fold at both window sizes. With a footer the state drops its
  // illustration early enough that the footer stays in view.
  testWidgets('the footer stays in view in a mid-height pane', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 600,
            height: 480,
            child: WpEmptyState(
              icon: LucideIcons.fileText,
              title: 'No snippets yet',
              hint: 'Save text you type often and insert it while dictating.',
              actionLabel: 'New snippet',
              onAction: () {},
              footer: const SizedBox(
                key: ValueKey('footer'),
                width: 300,
                height: 130,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final footer = tester.getRect(find.byKey(const ValueKey('footer')));
    expect(footer.bottom, lessThanOrEqualTo(480));
  });
}
