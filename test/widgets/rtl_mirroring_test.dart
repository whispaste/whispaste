// RTL handover (#1634): the segment indicator sits under the active segment
// and the list/detail split puts the list on the start side, in both text
// directions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_collection_split.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

Widget _host(TextDirection direction, Widget child, {double width = 300}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 600, child: child),
        ),
      ),
    ),
  );
}

Widget _selector(int active) => WpSegmentedSelector(
  borderColor: Colors.grey,
  surfaceColor: Colors.black,
  textSecondary: Colors.white,
  items: [
    for (var i = 0; i < 3; i++)
      WpSegmentItem(label: 'S$i', isActive: i == active, onTap: () {}),
  ],
);

Rect _indicatorRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(AnimatedPositionedDirectional),
    matching: find.byType(DecoratedBox),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    for (final active in [0, 2]) {
      testWidgets('segment indicator under active segment $active '
          '(${direction.name})', (tester) async {
        await tester.pumpWidget(_host(direction, _selector(active)));
        await tester.pumpAndSettle();

        final indicator = _indicatorRect(tester);
        final label = tester.getCenter(find.text('S$active'));
        expect(indicator.contains(label), isTrue);
      });
    }
  }

  testWidgets('RTL indicator follows a change of the active segment', (
    tester,
  ) async {
    await tester.pumpWidget(_host(TextDirection.rtl, _selector(0)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(TextDirection.rtl, _selector(1)));
    await tester.pumpAndSettle();

    expect(
      _indicatorRect(tester).contains(tester.getCenter(find.text('S1'))),
      isTrue,
    );
  });

  for (final direction in TextDirection.values) {
    testWidgets('collection split keeps the list on the start side '
        '(${direction.name})', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          direction,
          WpCollectionSplit<String>(
            selectedItem: 'a',
            idOf: (item) => item,
            listBuilder: (_, _) => const SizedBox.expand(key: Key('list')),
            detailBuilder: (_, _) => const SizedBox.expand(key: Key('detail')),
          ),
          width: 1200,
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byKey(const Key('list')));
      final detail = tester.getRect(find.byKey(const Key('detail')));
      if (direction == TextDirection.ltr) {
        expect(list.right, lessThanOrEqualTo(detail.left));
      } else {
        expect(detail.right, lessThanOrEqualTo(list.left));
      }
    });
  }
}
