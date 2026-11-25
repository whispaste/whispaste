// The start-up problems of the history database reach the user as app notices
// (#602).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/settings/data_key/data_key_flows.dart';
import 'package:whispaste/features/startup/history_startup_notice.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';

Widget _host({List overrides = const []}) => makeTestable(
  Builder(
    builder: (context) => Column(
      children: [
        const WpAppErrorSlot(),
        TextButton(
          key: const ValueKey('show'),
          onPressed: () => showHistoryStartupProblems(context),
          child: const Text('show'),
        ),
      ],
    ),
  ),
  locale: const Locale('en'),
  overrides: overrides,
);

void main() {
  setUp(takeHistoryStartupProblems);
  tearDown(takeHistoryStartupProblems);

  testWidgets(
    'a failed move and a failed copy each leave a notice that stays',
    (tester) async {
      noteHistoryStartupProblem(HistoryStartupProblem.moveFailed);
      noteHistoryStartupProblem(HistoryStartupProblem.backupFailed);
      await tester.pumpWidget(_host());
      await tester.tap(find.byKey(const ValueKey('show')));
      await tester.pumpAndSettle();

      final move = find.byKey(
        const ValueKey('page-notice-history-move-failed'),
      );
      final backup = find.byKey(
        const ValueKey('page-notice-history-backup-failed'),
      );
      expect(move, findsOneWidget);
      expect(backup, findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(move, findsOneWidget);
    },
  );

  testWidgets('without a problem nothing is shown', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('show')));
    await tester.pumpAndSettle();
    expect(find.byType(WpAppErrorSlot), findsOneWidget);
    expect(
      find.byKey(const ValueKey('page-notice-history-move-failed')),
      findsNothing,
    );
  });

  // #1023: a lost data key started the app empty; the notice says so, stays,
  // and offers the restore dialog that brings the old history back.
  testWidgets('a lost key leaves a notice with the restore dialog', (
    tester,
  ) async {
    var restores = 0;
    noteHistoryStartupProblem(HistoryStartupProblem.keyLostStartedEmpty);
    await tester.pumpWidget(
      _host(
        overrides: [
          dataKeyRestoreFlowProvider.overrideWithValue((context) async {
            restores++;
          }),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('show')));
    await tester.pumpAndSettle();

    final notice = find.byKey(const ValueKey('page-notice-history-key-lost'));
    expect(notice, findsOneWidget);
    expect(
      find.textContaining('starts with empty data', findRichText: true),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 60));
    expect(notice, findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('history-key-lost-restore'));
    await tester.pumpAndSettle();
    expect(restores, 1);
  });

  testWidgets('a restored history says where the interim one went', (
    tester,
  ) async {
    noteHistoryStartupProblem(HistoryStartupProblem.setAsideHistoryRestored);
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('show')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('page-notice-history-set-aside-restored')),
      findsOneWidget,
    );
    expect(
      find.textContaining('history_set_aside', findRichText: true),
      findsOneWidget,
    );
  });
}
