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
}
