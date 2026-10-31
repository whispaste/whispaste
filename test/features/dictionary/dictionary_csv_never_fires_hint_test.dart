/// CSV import preview: a row whose trigger is a single punctuation mark (such
/// as `?`) never fires. The preview counts those rows and says so, but the
/// import stays allowed and writes them like any other row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_preview_page.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';

import '../../fixtures/test_helpers.dart';

const _hintKey = ValueKey('dictionary-csv-preview-never-fires');

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<void> pumpPreview(
    WidgetTester tester,
    List<ReplacementCsvRow> rows,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        DictionaryCsvPreviewPage(
          result: ReplacementCsvParseResult(rows: rows, errors: const []),
          existing: const [],
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one never-firing row is named, and still imported', (
    tester,
  ) async {
    await pumpPreview(tester, const [
      ReplacementCsvRow(triggers: ['?'], replacement: 'Question'),
      ReplacementCsvRow(triggers: ['alpha'], replacement: 'A'),
    ]);

    expect(find.byKey(_hintKey), findsOneWidget);
    expect(find.text(l10n.dictionaryCsvNeverFiresCount(1)), findsOneWidget);
    expect(find.text(l10n.dictionaryCsvPreviewAddCount(2)), findsOneWidget);
  });

  testWidgets('several never-firing rows are counted together', (tester) async {
    await pumpPreview(tester, const [
      ReplacementCsvRow(triggers: ['?'], replacement: 'Question'),
      ReplacementCsvRow(triggers: ['!', 'alpha'], replacement: 'Bang'),
      ReplacementCsvRow(triggers: ['...'], replacement: 'Ellipsis'),
    ]);

    expect(find.text(l10n.dictionaryCsvNeverFiresCount(2)), findsOneWidget);
  });

  testWidgets('a file without such triggers shows no hint', (tester) async {
    await pumpPreview(tester, const [
      ReplacementCsvRow(triggers: ['->'], replacement: 'arrow'),
      ReplacementCsvRow(triggers: ['alpha'], replacement: 'A'),
    ]);

    expect(find.byKey(_hintKey), findsNothing);
  });
}
