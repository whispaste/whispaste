import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/sorting/list_sort.dart';
import 'package:whispaste/widgets/wp_sort_menu_button.dart';

/// The sort control is reached by testID only: picking an entry reports the
/// chosen field, and the direction entry toggles the reversed flag.
void main() {
  Future<({List<ListSortField> fields, List<bool> reversals})> pumpControl(
    WidgetTester tester, {
    ListSort current = const ListSort(ListSortField.trigger),
  }) async {
    final fields = <ListSortField>[];
    final reversals = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WpSortMenuButton<ListSortField>(
              testId: 'list-sort',
              tooltip: 'Sort',
              options: const [
                WpSortOption(
                  value: ListSortField.trigger,
                  id: 'trigger',
                  label: 'Trigger',
                  icon: LucideIcons.arrowRightLeft,
                ),
                WpSortOption(
                  value: ListSortField.result,
                  id: 'result',
                  label: 'Result',
                  icon: LucideIcons.textCursorInput,
                ),
              ],
              current: current.field,
              onChanged: fields.add,
              reversed: current.reversed,
              reverseLabel: 'Reverse',
              onReversedChanged: reversals.add,
            ),
          ),
        ),
      ),
    );
    return (fields: fields, reversals: reversals);
  }

  testWidgets('choosing a field by testID reports it', (tester) async {
    final out = await pumpControl(tester);

    await tester.tap(find.byKey(const ValueKey('list-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-sort-result')));
    await tester.pumpAndSettle();

    expect(out.fields, [ListSortField.result]);
    expect(out.reversals, isEmpty);
  });

  testWidgets('the reverse entry reports the flipped direction', (
    tester,
  ) async {
    final out = await pumpControl(
      tester,
      current: const ListSort(ListSortField.trigger),
    );

    await tester.tap(find.byKey(const ValueKey('list-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-sort-reverse')));
    await tester.pumpAndSettle();

    expect(out.reversals, [true]);
    expect(out.fields, isEmpty);
  });
}
