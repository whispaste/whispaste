/// Dictionary CSV export reports a failed write instead of failing silently
/// (UIA-DIC-09).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_actions.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('a failed write shows an error toast', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => writeReplacementsCsv(
                context,
                '/nonexistent-whispaste-b3/woerterbuch.csv',
                '',
                0,
              ),
              child: const Text('export'),
            ),
          ),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.tap(find.text('export'));
    // Real file I/O does not complete under the fake clock of testWidgets:
    // pump until the failure notice has appeared, bounded.
    final notice = find.text('Die CSV-Datei konnte nicht gespeichert werden.');
    for (var i = 0; i < 200 && notice.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      find.text('Die CSV-Datei konnte nicht gespeichert werden.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 11));
  });
}
