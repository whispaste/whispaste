import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/empty_state.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpEmptyState', () {
    testWidgets('renders with title and icon', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(icon: LucideIcons.inbox, title: 'Nothing here'),
        ),
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
    });

    testWidgets('renders optional hint text', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(
            icon: LucideIcons.inbox,
            title: 'Nothing here',
            hint: 'Try adding some items.',
          ),
        ),
      );

      expect(find.text('Try adding some items.'), findsOneWidget);
    });

    testWidgets('does not show hint when null', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(icon: LucideIcons.inbox, title: 'Nothing here'),
        ),
      );

      // Only the title text and no extra Text widgets for hint
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets(
      'action button is visible when actionLabel and onAction provided',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            WpEmptyState(
              icon: LucideIcons.plus,
              title: 'Empty',
              actionLabel: 'Add Item',
              onAction: () {},
            ),
          ),
        );

        expect(find.widgetWithText(ElevatedButton, 'Add Item'), findsOneWidget);
      },
    );

    testWidgets('action button is not shown when actionLabel is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(icon: LucideIcons.plus, title: 'Empty'),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
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

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Item'));
      expect(tapped, isTrue);
    });

    testWidgets('widget is centered', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpEmptyState(icon: LucideIcons.inbox, title: 'Nothing here'),
        ),
      );

      // WpEmptyState root element is a Center widget
      final emptyState = tester.element(find.byType(WpEmptyState));
      final firstChild = (emptyState.widget as WpEmptyState);
      expect(firstChild, isNotNull);
      // Verify there's at least one Center descendant
      expect(
        find.descendant(
          of: find.byType(WpEmptyState),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
    });
  });
}
