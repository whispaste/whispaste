import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_row_tile.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

Widget _host(SidePanelRow row) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: WpSidePanelRowTile(
            row: row,
            leadingIcon: LucideIcons.mic,
            kindLabel: 'Transcriptions',
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a title-only row is at least the 48 px touch target', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SidePanelRow(id: 'a', title: 'Short')));

    final height = tester.getSize(find.byType(WpListTileSurface)).height;
    expect(height, greaterThanOrEqualTo(WpLayout.minTouchTarget));
  });

  testWidgets('a row with a subtitle is at least the 48 px touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const SidePanelRow(id: 'b', title: 'Title', subtitle: 'Subtitle')),
    );

    final height = tester.getSize(find.byType(WpListTileSurface)).height;
    expect(height, greaterThanOrEqualTo(WpLayout.minTouchTarget));
  });

  testWidgets('the 48 px minimum holds at a doubled text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _host(
          const SidePanelRow(id: 'c', title: 'Title', subtitle: 'Subtitle'),
        ),
      ),
    );

    final height = tester.getSize(find.byType(WpListTileSurface)).height;
    expect(height, greaterThanOrEqualTo(WpLayout.minTouchTarget));
  });
}
