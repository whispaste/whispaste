/// The sidebar shows the original brand artwork, never a re-typeset name:
/// the full word-and-image mark when expanded, the logo mark when compact,
/// each in the variant drawn for the frame's brightness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/sidebar.dart';

String? _assetOf(Image image) => switch (image.image) {
  final AssetImage a => a.assetName,
  _ => null,
};

Iterable<String?> _assets(WidgetTester tester) =>
    tester.widgetList<Image>(find.byType(Image)).map(_assetOf);

Future<void> _pump(
  WidgetTester tester, {
  required WpThemeColors colors,
  required bool compact,
}) async {
  WpColors.activate(colors);
  addTearDown(() => WpColors.activate(wpLightColors));
  await tester.pumpWidget(
    MaterialApp(
      theme: wpThemeFor(colors),
      home: Scaffold(
        body: Row(
          children: [
            WpSidebar(
              items: const [
                WpNavItem(id: 'home', icon: LucideIcons.house, label: 'Home'),
              ],
              activeId: 'home',
              onItemTap: (_) {},
              compact: compact,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('expanded light frame shows the light word-and-image mark', (
    tester,
  ) async {
    await _pump(tester, colors: wpLightColors, compact: false);
    expect(_assets(tester), contains('assets/icons/wordmark-light.png'));
    expect(find.text('Whis', findRichText: true), findsNothing);
    expect(find.bySemanticsLabel('WhisPaste'), findsOneWidget);
  });

  testWidgets('expanded dark frame shows the dark word-and-image mark', (
    tester,
  ) async {
    await _pump(tester, colors: wpDarkColors, compact: false);
    expect(_assets(tester), contains('assets/icons/wordmark-dark.png'));
  });

  testWidgets('compact rail shows the logo mark for the frame', (tester) async {
    await _pump(tester, colors: wpLightColors, compact: true);
    expect(_assets(tester), contains('assets/icons/logo-light.png'));
    expect(find.bySemanticsLabel('WhisPaste'), findsOneWidget);
  });
}
