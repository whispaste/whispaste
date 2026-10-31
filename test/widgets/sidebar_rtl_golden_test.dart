/// RTL golden test for [WpSidebar].
///
/// Verifies that the active-item accent indicator bar is positioned on the
/// *right* side of the icon pill when the app locale is Hebrew (RTL) — and
/// that the same holds for the bottom-pinned entry and the attention dot,
/// both of which are rendered by the very same widget as the items above.
/// The pinned entry used to be a hand-copied second implementation with a
/// non-directional `Positioned(left: 0)`; it is in this golden precisely so
/// that regression cannot come back unseen.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/widgets/sidebar.dart';

import '../fixtures/rtl_golden_harness.dart';

void main() {
  final testItems = [
    const WpNavItem(id: 'history', icon: LucideIcons.clock, label: 'History'),
    // Not 'settings' — that id now belongs to the bottom-pinned entry below,
    // and two rows answering to the same id would both light up at once.
    const WpNavItem(
      id: 'analytics',
      icon: LucideIcons.chartNoAxesColumn,
      label: 'Analytics',
    ),
    const WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
  ];

  group('WpSidebar RTL golden', () {
    testWidgets('active indicator appears on the reading-start side (he)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapForRtlGolden(
          WpSidebar(
            items: testItems,
            activeId: 'history',
            onItemTap: (_) {},
            bottomItems: const [
              WpNavItem(
                id: 'settings',
                icon: LucideIcons.settings,
                label: 'Settings',
                badgeHint: 'Update available: v9.9.9',
              ),
            ],
          ),
          size: const Size(72, 600),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(WpSidebar),
        matchesGoldenFile('goldens/sidebar_rtl_he_dark.png'),
      );
    });
  });
}
