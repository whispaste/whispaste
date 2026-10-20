import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/tokens.dart' show WpSpacing;
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

import '../fixtures/test_helpers.dart';

final _label = find.text('Row label');
final _divider = find.byKey(const ValueKey('wp-list-tile-divider'));

BoxDecoration _rowDecoration(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(WpListTileSurface),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return box.decoration! as BoxDecoration;
}

Future<void> _pumpPanelRow(
  WidgetTester tester, {
  bool selected = false,
  bool hovered = false,
}) async {
  await tester.pumpWidget(
    makeTestable(
      WpListTileSurface(
        variant: WpListTileVariant.panel,
        isSelected: selected,
        isHovered: hovered,
        child: const SizedBox(width: 200, child: Text('Row label')),
      ),
    ),
  );
  // Rows animate fill, border and padding; let the state change finish.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('label does not move between resting, hover and selected', (
    tester,
  ) async {
    await _pumpPanelRow(tester);
    final resting = tester.getTopLeft(_label);

    await _pumpPanelRow(tester, hovered: true);
    expect(tester.getTopLeft(_label), resting, reason: 'hover');

    await _pumpPanelRow(tester, selected: true);
    expect(tester.getTopLeft(_label), resting, reason: 'selected');
  });

  testWidgets('label inset is padding 16 plus the border in every state', (
    tester,
  ) async {
    for (final selected in [false, true]) {
      await _pumpPanelRow(tester, selected: selected);
      final rowLeft = tester.getTopLeft(find.byType(AnimatedContainer)).dx;
      expect(
        tester.getTopLeft(_label).dx - rowLeft,
        WpListTileSurface.borderWidth + WpSpacing.md,
        reason: 'selected: $selected',
      );
    }
  });

  testWidgets('resting row is flat: no fill, no visible border', (
    tester,
  ) async {
    await _pumpPanelRow(tester);
    final decoration = _rowDecoration(tester);

    expect(decoration.color!.a, 0, reason: 'resting fill is transparent');
    final border = decoration.border! as Border;
    expect(border.top.color.a, 0, reason: 'resting edge is transparent');
  });

  testWidgets('resting row shows a borderSubtle divider at the text start', (
    tester,
  ) async {
    await _pumpPanelRow(tester);

    expect(_divider, findsOneWidget);
    expect(tester.getTopLeft(_divider).dx, tester.getTopLeft(_label).dx);
    expect(tester.widget<Container>(_divider).color, WpColors.borderSubtle);
  });

  testWidgets('hover is a fill without a border', (tester) async {
    await _pumpPanelRow(tester, hovered: true);
    final decoration = _rowDecoration(tester);

    expect(decoration.color, WpColors.hover);
    expect((decoration.border! as Border).top.color.a, 0);
  });

  testWidgets('selected row is a white card with a controlEdge border', (
    tester,
  ) async {
    await _pumpPanelRow(tester, selected: true);
    final decoration = _rowDecoration(tester);

    expect(decoration.color, WpColors.surfaceElevated);
    final border = decoration.border! as Border;
    // UIA-FND-13 V2: the selected edge is the 3:1 control edge, not a lift.
    expect(border.top.color, WpColors.controlEdge);
    expect(
      (tester.widget<Container>(_divider).color!).a,
      0,
      reason: 'the card edge replaces the rule',
    );
  });

  testWidgets('selected row has radius 8', (tester) async {
    await _pumpPanelRow(tester, selected: true);
    expect(
      _rowDecoration(tester).borderRadius,
      BorderRadius.circular(WpRadiusTokens.control),
    );
    expect(WpRadiusTokens.control, 8);
  });

  testWidgets('selected row paints no shadow; its edge carries the state', (
    tester,
  ) async {
    await _pumpPanelRow(tester, selected: true);
    expect(_rowDecoration(tester).boxShadow, isNull);
  });

  testWidgets('resting row paints no shadow', (tester) async {
    await _pumpPanelRow(tester);
    expect(_rowDecoration(tester).boxShadow, isNull);
  });
}
