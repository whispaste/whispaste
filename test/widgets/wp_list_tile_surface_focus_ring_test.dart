/// The keyboard cursor of a list row is the app's focus ring, in both row
/// variants and also on the open (selected) row (#1902): the tint alone was
/// about 1.03:1, and the selected look hid it completely.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

import '../fixtures/test_helpers.dart';

Future<bool> _ringed(
  WidgetTester tester, {
  required WpListTileVariant variant,
  required bool focused,
  required bool selected,
}) async {
  await tester.pumpWidget(
    makeTestable(
      WpListTileSurface(
        variant: variant,
        isFocused: focused,
        isSelected: selected,
        child: const SizedBox(height: 40, width: 200),
      ),
    ),
  );
  return tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(WpListTileSurface),
          matching: find.byType(CustomPaint),
        ),
      )
      .any((p) => p.foregroundPainter is WpFocusRingPainter);
}

void main() {
  for (final variant in WpListTileVariant.values) {
    testWidgets('$variant: the cursor row shows the focus ring', (
      tester,
    ) async {
      expect(
        await _ringed(tester, variant: variant, focused: true, selected: false),
        isTrue,
      );
      expect(
        await _ringed(tester, variant: variant, focused: true, selected: true),
        isTrue,
        reason: 'the open row must not hide the cursor',
      );
      expect(
        await _ringed(tester, variant: variant, focused: false, selected: true),
        isFalse,
        reason: 'selection alone is no focus',
      );
    });
  }
}
