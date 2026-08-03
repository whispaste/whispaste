/// Large-text resilience test for [WpSidebar] — the desktop analogue of an
/// accessibility-text-size simulator check (no simctl on Flutter desktop).
///
/// Renders the REAL production nav items (all 7, via [wpNavItems]) plus the
/// pinned settings button under an enlarged text scale and verifies nothing
/// overflows or crashes.
///
/// Locale: German — the longest translations across EN/DE/HE (e.g.
/// "Sprach-Shortcuts" 16 chars vs EN "Voice Shortcuts" 15; "Einstellungen"
/// 13 chars vs EN "Settings" 8), so it is the worst case for tooltip width.
///
/// Scale: 1.5 — strictly harsher than the 1.3 baseline; Windows' system
/// "Text size" slider commonly reaches 150%, so passing at 1.5 covers the
/// realistic desktop range (and implies 1.3 passes too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart' show wpNavDividerAfterIds, wpNavItems;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/sidebar_settings_button.dart';

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
                WpSidebarSettingsButton(isActive: false, onTap: () {}),
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
    testWidgets('renders all 7 nav items + settings without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(buildScaledShell());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final l10n = await L10n.delegate.load(const Locale('de'));
      final expectedTooltips = [
        for (final item in wpNavItems(l10n)) item.label,
        l10n.navSettings,
      ];
      expect(expectedTooltips, hasLength(8)); // 7 nav items + settings
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
      // navReplacements ("Sprach-Shortcuts") is the longest label in the
      // longest locale — the worst case for a scaled tooltip.
      await tester.longPress(find.byTooltip(l10n.navReplacements));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(l10n.navReplacements), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Let the tooltip timer expire so no pending timers leak.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}
