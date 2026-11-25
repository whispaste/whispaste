import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/overview/overview_rows.dart';

import '../../fixtures/test_helpers.dart';

/// #1970: a list card moved into the narrow side column shows its rows in
/// two lines, so nothing overflows there, also at text size 2.0.
void main() {
  Widget row(double width, double scale) => makeTestable(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: OverviewRow(
                time: '12:34',
                leading: const SizedBox(width: 40, height: 40),
                text: 'A dictated sentence that is long enough to wrap',
                subtitle: 'Notes',
                onOpen: () {},
                actions: const [
                  SizedBox(key: ValueKey('a1'), width: 48, height: 48),
                  SizedBox(key: ValueKey('a2'), width: 48, height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('side column width at text size $scale: two lines', (
      tester,
    ) async {
      await tester.pumpWidget(row(296, scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('12:34 · Notes'), findsOneWidget);
      // The actions sit below the text.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('a1'))).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.text('A dictated sentence that is long enough to wrap'),
              )
              .dy,
        ),
      );
    });
  }

  testWidgets('main column width keeps the one-line row', (tester) async {
    await tester.pumpWidget(row(700, 1.0));
    await tester.pumpAndSettle();
    expect(find.text('12:34'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
  });
}
