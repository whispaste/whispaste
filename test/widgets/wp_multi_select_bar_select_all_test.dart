// #1858: the multi-select bar leads with a "select all" box that reads
// none / some / all of the current list and offers no action before a tick.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_multi_select_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
  test('selectAllState is false, partial (null) or true', () {
    expect(selectAllState(0, 5), isFalse);
    expect(selectAllState(2, 5), isNull);
    expect(selectAllState(5, 5), isTrue);
    // A selection larger than the filtered list still reads "all".
    expect(selectAllState(7, 5), isTrue);
    expect(selectAllState(0, 0), isFalse);
    expect(selectAllState(3, null), isNull);
  });

  Future<int> pumpBar(
    WidgetTester tester,
    int selected, {
    int total = 4,
  }) async {
    var taps = 0;
    await tester.pumpWidget(
      makeTestable(
        Scaffold(
          body: SizedBox(
            width: 900,
            child: WpMultiSelectBar(
              idPrefix: 't',
              selectedCount: selected,
              totalCount: total,
              isTrashView: false,
              isArchiveView: false,
              onCancelSelection: () {},
              onSelectAll: () => taps++,
              onDelete: selected > 0 ? () {} : null,
            ),
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('t-select-all')));
    await tester.pump();
    return taps;
  }

  Checkbox box(WidgetTester tester) => tester.widget<Checkbox>(
    find.descendant(
      of: find.byKey(const ValueKey('t-select-all')),
      matching: find.byType(Checkbox),
    ),
  );

  testWidgets('with nothing ticked the box is empty and Delete is absent', (
    tester,
  ) async {
    expect(await pumpBar(tester, 0), 1);
    expect(box(tester).value, isFalse);
    expect(box(tester).tristate, isTrue);
    expect(find.byKey(const ValueKey('t-delete')), findsNothing);
  });

  testWidgets('a partial selection shows the dash, a full one the tick', (
    tester,
  ) async {
    await pumpBar(tester, 2);
    expect(box(tester).value, isNull);
    expect(find.byKey(const ValueKey('t-delete')), findsOneWidget);
    await pumpBar(tester, 4);
    expect(box(tester).value, isTrue);
  });
}
