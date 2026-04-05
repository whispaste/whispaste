import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/sidebar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  final testItems = [
    const WpNavItem(id: 'home', icon: LucideIcons.house, label: 'Home'),
    const WpNavItem(id: 'settings', icon: LucideIcons.settings, label: 'Settings'),
    const WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
  ];

  group('WpSidebar', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpSidebar(
            items: testItems,
            activeId: 'home',
            onItemTap: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('shows expected number of navigation icons', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpSidebar(
            items: testItems,
            activeId: 'home',
            onItemTap: (_) {},
          ),
        ),
      );

      // Each nav item has a Tooltip with the item label
      for (final item in testItems) {
        expect(
          find.byTooltip(item.label),
          findsOneWidget,
          reason: 'Nav item "${item.label}" should have a Tooltip',
        );
      }
    });

    testWidgets('tapping a nav item calls the selection callback',
        (tester) async {
      String? tappedId;

      await tester.pumpWidget(
        makeTestable(
          WpSidebar(
            items: testItems,
            activeId: 'home',
            onItemTap: (id) => tappedId = id,
          ),
        ),
      );

      // Tap the settings icon via its Tooltip
      await tester.tap(find.byTooltip('Settings'));
      expect(tappedId, 'settings');
    });

    testWidgets('tapping a different nav item reports correct id',
        (tester) async {
      String? tappedId;

      await tester.pumpWidget(
        makeTestable(
          WpSidebar(
            items: testItems,
            activeId: 'home',
            onItemTap: (id) => tappedId = id,
          ),
        ),
      );

      await tester.tap(find.byTooltip('About'));
      expect(tappedId, 'about');
    });

    testWidgets('WpNavItem data class stores id, icon, and label', (_) async {
      const item = WpNavItem(
        id: 'test',
        icon: LucideIcons.star,
        label: 'Test',
      );
      expect(item.id, 'test');
      expect(item.icon, LucideIcons.star);
      expect(item.label, 'Test');
    });
  });
}
