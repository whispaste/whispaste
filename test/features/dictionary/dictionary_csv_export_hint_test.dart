/// UIA-DIC-08: the CSV export is disabled while there is nothing to export,
/// and the reason is shown as visible text.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/widgets/searchable_list_page.dart';

import '../../fixtures/test_helpers.dart';

/// Starts with no replacements, so there is nothing to export. The first-run
/// sample data would otherwise fill the list.
class _EmptyReplacementsNotifier extends ReplacementsNotifier {
  @override
  Future<List<Replacement>> build() async => const [];
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('an empty replacement list explains why export is off', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: db,
        overrides: [
          replacementsProvider.overrideWith(_EmptyReplacementsNotifier.new),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dictionaryTabReplacements));
    await tester.pumpAndSettle();

    // Export lives in the overflow menu; the disabled row carries the reason.
    await tester.tap(find.byKey(const ValueKey('replacements-more')));
    await tester.pumpAndSettle();

    final exportItem = tester.widget<PopupMenuItem<WpListMenuAction>>(
      find.byKey(const ValueKey('dictionary-csv-export')),
    );
    expect(exportItem.enabled, isFalse);
    expect(find.text(l10n.dictionaryCsvExportEmpty), findsOneWidget);
  });
}
