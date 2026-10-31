import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/page_shell.dart';
import '../fixtures/test_helpers.dart';

void main() {
  group('WpPageShell', () {
    testWidgets('scrollable mode wraps content in SingleChildScrollView', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const WpPageShell(child: Text('Hello'))),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('fixed mode uses Padding without scroll', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpPageShell(scrollable: false, child: Text('Fixed')),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Fixed'), findsOneWidget);
    });

    testWidgets('header stays outside the scroll view', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            width: 600,
            height: 400,
            child: WpPageShell(header: Text('Sticky'), child: Text('Body')),
          ),
        ),
      );

      expect(find.text('Sticky'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('Sticky'),
        ),
        findsNothing,
        reason:
            'a scrolled header would not be sticky, and content deep-links '
            'rely on the shell owning the single scrollable',
      );
    });

    testWidgets('header shares the padding but drops its bottom inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            width: 600,
            height: 400,
            child: WpPageShell(header: Text('Sticky'), child: Text('Body')),
          ),
        ),
      );

      final headerPadding = tester.widget<Padding>(
        find
            .ancestor(of: find.text('Sticky'), matching: find.byType(Padding))
            .first,
      );
      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final contentPadding = scrollView.padding! as EdgeInsets;

      expect(
        headerPadding.padding,
        EdgeInsets.fromLTRB(
          contentPadding.left,
          contentPadding.top,
          contentPadding.right,
          0,
        ),
        reason: 'the content below carries its own top inset',
      );
    });
  });

  group('WpTwoPanel', () {
    testWidgets('shows side-by-side when wide', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            width: 800,
            height: 200,
            child: WpTwoPanel(
              breakpoint: 500,
              left: Text('Left'),
              right: Text('Right'),
            ),
          ),
        ),
      );

      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
      // Expect a Row for side-by-side layout
      final rows = tester.widgetList<Row>(find.byType(Row));
      expect(rows, isNotEmpty);
    });

    testWidgets('stacks vertically when narrow', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            width: 300,
            height: 400,
            child: WpTwoPanel(
              breakpoint: 500,
              left: Text('Top'),
              right: Text('Bottom'),
            ),
          ),
        ),
      );

      expect(find.text('Top'), findsOneWidget);
      expect(find.text('Bottom'), findsOneWidget);
      // Expect a Column for stacked layout
      final columns = tester.widgetList<Column>(find.byType(Column));
      expect(columns, isNotEmpty);
    });
  });
}
