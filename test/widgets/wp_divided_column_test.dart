// Guard for the one divider responsibility (#2050): a list of rows draws
// exactly one rule between two rows that show something, never two stacked
// rules and never a rule at its top or bottom edge, even when a row builds
// nothing (SizedBox.shrink) because it does not apply.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';
import 'package:whispaste/widgets/wp_row_divider.dart';

import '../fixtures/test_helpers.dart';

/// A row that decides at build time that it has nothing to show, like the GPU
/// check off Windows or a notice without a cause.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _row(String id) =>
    WpSettingsRow(rowId: id, title: id, trailing: const SizedBox(width: 1));

/// Top edges (global y) of the rules that are drawn, top to bottom.
List<double> _shownRules(WidgetTester tester) {
  final tops = <double>[];
  for (final e in find.byType(WpRowDivider).evaluate()) {
    final box = e.renderObject! as RenderBox;
    if (debugWpRowDividerShown(box)) {
      tops.add(box.localToGlobal(Offset.zero).dy);
    }
  }
  return tops..sort();
}

Future<void> _pumpGroup(WidgetTester tester, List<Widget> children) =>
    tester.pumpWidget(
      makeTestable(
        Center(
          child: SizedBox(
            width: 560,
            child: WpSettingsGroup(children: children),
          ),
        ),
      ),
    );

void main() {
  testWidgets('an empty row between two rows leaves one rule, not two', (
    tester,
  ) async {
    await _pumpGroup(tester, [
      _row('a'),
      const _EmptyRow(),
      const SizedBox(height: 8),
      const _EmptyRow(),
      _row('b'),
    ]);

    final rules = _shownRules(tester);
    expect(rules, hasLength(1));
    final a = tester.getRect(find.byKey(const ValueKey('settings-row-a')));
    final b = tester.getRect(find.byKey(const ValueKey('settings-row-b')));
    expect(rules.single, greaterThanOrEqualTo(a.bottom));
    expect(rules.single, lessThan(b.top));
  });

  testWidgets('no rule at the top or bottom edge around empty rows', (
    tester,
  ) async {
    await _pumpGroup(tester, [
      const _EmptyRow(),
      _row('a'),
      _row('b'),
      const _EmptyRow(),
    ]);

    expect(_shownRules(tester), hasLength(1));
  });

  testWidgets('a group whose rows are all empty draws no rule', (tester) async {
    await _pumpGroup(tester, [
      const _EmptyRow(),
      const _EmptyRow(),
      const _EmptyRow(),
    ]);

    expect(_shownRules(tester), isEmpty);
  });

  testWidgets('a detail of a row gets no rule in front of it', (tester) async {
    await _pumpGroup(tester, [
      _row('a'),
      const WpSettingsDetail(child: Text('detail')),
      _row('b'),
    ]);

    expect(_shownRules(tester), hasLength(1));
  });

  testWidgets('every shown rule has a row with height on both sides', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const Center(
          child: SizedBox(
            width: 400,
            child: WpDividedColumn(
              children: [
                _EmptyRow(),
                Text('one'),
                _EmptyRow(),
                _EmptyRow(),
                Text('two'),
                Text('three'),
                _EmptyRow(),
              ],
            ),
          ),
        ),
      ),
    );

    final rules = _shownRules(tester);
    expect(rules, hasLength(2));
    // Two rules never touch: a row with height always sits between them.
    expect(rules[1] - rules[0], greaterThan(1));
    final one = tester.getRect(find.text('one'));
    final three = tester.getRect(find.text('three'));
    expect(rules.first, greaterThanOrEqualTo(one.bottom));
    expect(rules.last, lessThan(three.top));
  });
}
