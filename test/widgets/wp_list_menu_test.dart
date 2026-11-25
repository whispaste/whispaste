import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/searchable_list_page.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('grouped menu dispatches only the chosen enabled action', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWpListMenu(context, [
              WpListMenuAction(
                itemKey: const ValueKey('view'),
                label: 'List',
                icon: Icons.list,
                checked: true,
                onSelected: () => selected.add('view'),
              ),
              WpListMenuAction(
                itemKey: const ValueKey('sort'),
                label: 'Oldest',
                icon: Icons.sort,
                dividerBefore: true,
                onSelected: () => selected.add('sort'),
              ),
              WpListMenuAction(
                itemKey: const ValueKey('disabled'),
                label: 'Unavailable',
                icon: Icons.block,
                enabled: false,
                onSelected: () => selected.add('disabled'),
              ),
            ]),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unavailable'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.tap(find.text('Oldest'));
    await tester.pumpAndSettle();
    expect(selected, ['sort']);
    expect(find.text('Oldest'), findsNothing);
  });
}
