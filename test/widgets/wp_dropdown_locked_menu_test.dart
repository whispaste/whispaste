/// Guard on the shared dropdown (#1156): a menu whose entries are all locked
/// never opens. Such a dropdown is disabled; one with a pickable entry opens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../fixtures/test_helpers.dart';

List<WpDropdownItem<String>> _items({required Set<String> locked}) => [
  for (final v in ['a', 'b', 'c'])
    WpDropdownItem<String>(
      value: v,
      label: v,
      enabled: !locked.contains(v),
      itemKey: ValueKey<String>('guard-item-$v'),
    ),
];

Future<void> _pump(
  WidgetTester tester,
  List<WpDropdownItem<String>> items,
  void Function(String?) onChanged,
) async {
  await tester.pumpWidget(
    makeTestable(
      Center(
        child: SizedBox(
          width: 200,
          child: WpDropdown<String>(
            key: const ValueKey('guard-dropdown'),
            value: 'a',
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('can open only with at least one pickable entry', () {
    expect(wpDropdownCanOpen(_items(locked: {})), isTrue);
    expect(wpDropdownCanOpen(_items(locked: {'a', 'b'})), isTrue);
    expect(wpDropdownCanOpen(_items(locked: {'a', 'b', 'c'})), isFalse);
    expect(wpDropdownCanOpen(<WpDropdownItem<String>>[]), isFalse);
  });

  testWidgets('all entries locked: tapping does not open a menu', (
    tester,
  ) async {
    await _pump(tester, _items(locked: {'a', 'b', 'c'}), (_) {});

    await tester.tap(find.byKey(const ValueKey('guard-dropdown')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guard-item-b')), findsNothing);
    final button = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(button.onChanged, isNull);
  });

  testWidgets('one pickable entry: the menu opens and picks it', (
    tester,
  ) async {
    String? picked;
    await _pump(tester, _items(locked: {'a', 'c'}), (v) => picked = v);

    await tester.tap(find.byKey(const ValueKey('guard-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guard-item-b')).last);
    await tester.pumpAndSettle();

    expect(picked, 'b');
  });
}
