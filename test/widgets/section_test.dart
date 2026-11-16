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
}
