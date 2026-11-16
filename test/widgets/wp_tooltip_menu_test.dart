import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';

/// Tooltip and popup menu under the real WhisPaste theme, as the app uses them.
Widget _host(Widget trigger) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: wpThemeFor(wpLightColors),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: Center(child: trigger)),
);

void main() {
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  testWidgets(
    'popup menu opens, shows all items and a tap fires the callback',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        _host(
          PopupMenuButton<String>(
            key: const ValueKey('menu-trigger'),
            icon: const Icon(LucideIcons.ellipsis),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'pin', child: Text('Pin to top')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: WpColors.error)),
              ),
            ],
            onSelected: (value) => selected = value,
          ),
        ),
      );

      expect(find.text('Rename'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('menu-trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Pin to top'));
      await tester.pumpAndSettle();

      expect(selected, 'pin');
      expect(find.text('Pin to top'), findsNothing, reason: 'menu closes');
    },
  );

  testWidgets('tooltip shows its message when made visible', (tester) async {
    final tooltipKey = GlobalKey<TooltipState>();
    await tester.pumpWidget(
      _host(
        Tooltip(
          key: tooltipKey,
          message: 'Copy transcript',
          showDuration: const Duration(seconds: 30),
          child: const IconButton(
            icon: Icon(LucideIcons.copy),
            onPressed: null,
          ),
        ),
      ),
    );

    expect(find.text('Copy transcript'), findsNothing);

    tooltipKey.currentState!.ensureTooltipVisible();
    await tester.pumpAndSettle();

    expect(find.text('Copy transcript'), findsOneWidget);

    // Drain the tooltip's show timer so nothing is left pending.
    await tester.pumpAndSettle(const Duration(seconds: 40));
  });
}
