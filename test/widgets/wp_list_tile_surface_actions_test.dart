/// Padding of [WpListTileSurface] when it carries an actions slot.
///
/// The actions slot's 48 px box sets a single-line row's height. Multi-line
/// content must still keep the envelope's normal padding to the divider
/// (panel) and symmetric padding top and bottom (card).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_list_tile_surface.dart';

import '../fixtures/test_helpers.dart';

const _contentKey = ValueKey('surface-test-content');

Widget _surface(WpListTileVariant variant) => SizedBox(
  width: 400,
  child: WpListTileSurface(
    variant: variant,
    actions: const SizedBox(width: 48, height: 48),
    child: const Column(
      key: _contentKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20, child: Text('first line')),
        SizedBox(height: 20, child: Text('second line')),
      ],
    ),
  ),
);

void main() {
  testWidgets('panel: two-line content keeps padding to the divider', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(_surface(WpListTileVariant.panel)));
    final surface = tester.getRect(find.byType(WpListTileSurface));
    final content = tester.getRect(find.byKey(_contentKey));
    final divider = tester.getRect(
      find.byKey(const ValueKey('wp-list-tile-divider')),
    );

    expect(
      content.top - surface.top,
      greaterThanOrEqualTo(WpListTileSurface.panelVerticalPadding),
      reason: 'top padding above the content',
    );
    expect(
      divider.top - content.bottom,
      greaterThanOrEqualTo(WpListTileSurface.panelVerticalPadding),
      reason: 'bottom padding between the content and the divider',
    );
  });

  testWidgets('card: two-line content keeps symmetric padding', (tester) async {
    await tester.pumpWidget(makeTestable(_surface(WpListTileVariant.card)));
    final surface = tester.getRect(find.byType(WpListTileSurface));
    final content = tester.getRect(find.byKey(_contentKey));

    final top = content.top - surface.top;
    final bottom = surface.bottom - content.bottom;
    expect(top, greaterThanOrEqualTo(8), reason: 'top padding');
    expect(bottom, greaterThanOrEqualTo(8), reason: 'bottom padding');
    expect(
      (top - bottom).abs(),
      lessThan(0.5),
      reason: 'top and bottom padding are equal',
    );
  });
}
