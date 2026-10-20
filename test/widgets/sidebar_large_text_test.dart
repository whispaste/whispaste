/// Large-text resilience test for [WpSidebar] — the desktop analogue of an
/// accessibility-text-size simulator check (no simctl on Flutter desktop).
///
/// Renders the REAL production rail (six working areas via [wpNavItems], plus
/// the pinned Help and Settings entries) under an enlarged text scale and verifies nothing
/// overflows or crashes.
///
/// Locale: German — the pinned settings button's "Einstellungen" (13 chars)
/// is the longest label across EN/DE/HE sidebar entries overall; among the
/// working-area labels in this locale, the longest are close behind EN's
/// "Replacements" (12).
/// Still a strong worst-case locale for tooltip width.
///
/// Scale: 1.5 — strictly harsher than the 1.3 baseline; Windows' system
/// "Text size" slider commonly reaches 150%, so passing at 1.5 covers the
/// realistic desktop range (and implies 1.3 passes too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart'
    show wpHelpNavItem, wpNavDividerAfterIds, wpNavItems, wpSettingsNavItem;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/sidebar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  Widget buildScaledShell() => makeTestable(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.5)),
        child: Row(
          children: [
            WpSidebar(
              items: wpNavItems(L10n.of(context)),
              dividerAfterIds: wpNavDividerAfterIds,
              activeId: 'history',
              onItemTap: (_) {},
              bottomItems: [
                wpHelpNavItem(L10n.of(context)),
                wpSettingsNavItem(L10n.of(context)),
              ],
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    ),
    locale: const Locale('de'),
  );

  group('WpSidebar large text (de, 1.5x)', () {
    testWidgets('renders all 8 rail entries without overflow', (tester) async {
      await tester.pumpWidget(buildScaledShell());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final l10n = await L10n.delegate.load(const Locale('de'));
      final expectedTooltips = [
        for (final item in wpNavItems(l10n)) item.label,
        l10n.navHelp,
        l10n.navSettings,
      ];
      expect(
        expectedTooltips,
        hasLength(8),
      ); // 6 working areas + Help + Settings
      for (final label in expectedTooltips) {
        expect(
          find.byTooltip(label),
          findsOneWidget,
          reason: 'Sidebar entry "$label" should render at 1.5x text scale',
        );
      }
    });

    testWidgets('longest tooltip label opens without overflow', (tester) async {
      await tester.pumpWidget(buildScaledShell());
      await tester.pumpAndSettle();

      final l10n = await L10n.delegate.load(const Locale('de'));
      // navReplacements ("Wörterbuch") is one of the working-area labels; the
      // pinned Settings entry ("Einstellungen", 13 chars) is the longest rail
      // label and is covered by the test above.
      await tester.longPress(find.byTooltip(l10n.navReplacements));
      await tester.pump(const Duration(milliseconds: 500));

      // The visible label and the opened tooltip both carry the text.
      expect(find.text(l10n.navReplacements), findsWidgets);
      expect(tester.takeException(), isNull);

      // Let the tooltip timer expire so no pending timers leak.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}
