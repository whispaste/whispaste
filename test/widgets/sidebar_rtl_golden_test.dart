/// RTL golden test for [WpSidebar].
///
/// Verifies that the active-item accent indicator bar is positioned on the
/// *right* side of the icon pill when the app locale is Hebrew (RTL).
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
    const WpNavItem(
      id: 'settings',
      icon: LucideIcons.settings,
      label: 'Settings',
    ),
    const WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
  ];

  group('WpSidebar RTL golden', () {
    testWidgets('active indicator appears on the reading-start side (he)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapForRtlGolden(
          WpSidebar(items: testItems, activeId: 'history', onItemTap: (_) {}),
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
