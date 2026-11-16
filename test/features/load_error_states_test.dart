/// A failed load is not an empty result (#1635): the notes of a recording and
/// the overview figures say that loading failed and offer to try again,
/// instead of showing nothing or zeros.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_notes_section.dart';
import 'package:whispaste/features/overview/overview_figures.dart';
import 'package:whispaste/features/overview/overview_providers.dart';

import '../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('notes that fail to load show an error with a retry', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      makeTestable(
        const HistoryNotesSection(entryId: 'e1'),
        locale: const Locale('en'),
        overrides: [
          entryNotesProvider('e1').overrideWith((ref) {
            loads++;
            return Stream.error(StateError('db gone'));
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyNotesLoadFailed), findsOneWidget);
    await tester.tap(find.text(l10n.actionRetry));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('overview figures that fail to load show no zeros', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const OverviewFigures(),
        locale: const Locale('en'),
        overrides: [
          overviewFiguresProvider.overrideWith(
            (ref, period) => Future.error(StateError('db gone')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.overviewFiguresLoadFailed), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-figure-words')), findsNothing);
  });
}
