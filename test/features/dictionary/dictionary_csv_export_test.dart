/// Dictionary CSV export reports a failed write instead of failing silently
/// (UIA-DIC-09).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_actions.dart';
import 'package:whispaste/features/dictionary/dictionary_notice.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/pump_until.dart';

void main() {
  testWidgets('a failed write shows a standing error notice', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Column(
            children: [
              const WpPageNoticeSlot(page: dictionaryNoticePage),
              TextButton(
                onPressed: () => writeReplacementsCsv(
                  context,
                  '/nonexistent-whispaste-b3/woerterbuch.csv',
                  '',
                  0,
                ),
                child: const Text('export'),
              ),
            ],
          ),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.tap(find.text('export'));
    // Real file I/O does not complete under the fake clock of testWidgets:
    // real event-loop turns until the failure notice has appeared, bounded,
    // no fixed wait (#1491).
    final notice = find.byKey(const ValueKey('page-notice-export-failed'));
    await pumpUntil(
      tester,
      () => notice.evaluate().isNotEmpty,
      what: 'the export failure notice',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-notice-export-failed')),
      findsOneWidget,
    );
    // It stays: no timer takes it away.
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.byKey(const ValueKey('page-notice-export-failed')),
      findsOneWidget,
    );
  });
}
