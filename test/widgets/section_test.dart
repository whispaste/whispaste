import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/section.dart';

import '../fixtures/test_helpers.dart';

Future<void> _pump(WidgetTester tester, {required bool expanded}) {
  return tester.pumpWidget(
    makeTestable(
      WpSection(
        title: 'Advanced',
        collapsible: true,
        initiallyExpanded: expanded,
        child: const SizedBox(),
      ),
    ),
  );
}

void main() {
  group('WpSection (collapsible)', () {
    testWidgets('initially expanded opens the content', (tester) async {
      await _pump(tester, expanded: true);

      expect(tester.widget<Align>(find.byType(Align).last).heightFactor, 1.0);
    });

    testWidgets('initially collapsed closes the content', (tester) async {
      await _pump(tester, expanded: false);

      expect(tester.widget<Align>(find.byType(Align).last).heightFactor, 0.0);
    });

    testWidgets('tapping the header toggles the collapsed state', (
      tester,
    ) async {
      await _pump(tester, expanded: false);

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(tester.widget<Align>(find.byType(Align).last).heightFactor, 1.0);

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(tester.widget<Align>(find.byType(Align).last).heightFactor, 0.0);
    });
  });

  // #1917: the trailing controls merged into the heading node, so the four
  // analytics period chips reached assistive tech as one heading.
  testWidgets('trailing controls stay their own nodes, outside the heading', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        WpSection(
          title: 'Overview',
          testId: 'section-heading',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                identifier: 'chip-a',
                button: true,
                selected: true,
                onTap: () {},
                child: const Text('7 days'),
              ),
              Semantics(
                identifier: 'chip-b',
                button: true,
                selected: false,
                onTap: () {},
                child: const Text('All'),
              ),
            ],
          ),
          child: const SizedBox(),
        ),
      ),
    );

    final heading = tester
        .getSemantics(find.bySemanticsIdentifier('section-heading'))
        .getSemanticsData();
    expect(heading.label, 'Overview');
    expect(heading.flagsCollection.isHeader, isTrue);
    for (final (id, label) in [('chip-a', '7 days'), ('chip-b', 'All')]) {
      final chip = tester
          .getSemantics(find.bySemanticsIdentifier(id))
          .getSemanticsData();
      expect(chip.label, label);
      expect(chip.flagsCollection.isButton, isTrue);
    }
    handle.dispose();
  });
}
