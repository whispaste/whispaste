/// CSV import preview: each row that would be added can be unticked, and the
/// import button counts only the rows still ticked (UIA-DIC-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_csv_preview_page.dart';
import 'package:whispaste/services/dictionary/replacement_csv.dart';
import 'package:whispaste/services/dictionary/replacement_duplicates.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets(
    'unticking a row removes it from the import; duplicates have no box (UIA-DIC-12)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      const result = ReplacementCsvParseResult(
        rows: [
          ReplacementCsvRow(triggers: ['alpha'], replacement: 'A'),
          ReplacementCsvRow(triggers: ['beta'], replacement: 'B'),
          ReplacementCsvRow(triggers: ['MFG'], replacement: 'Manufacturing'),
        ],
        errors: [],
      );
      await tester.pumpWidget(
        makeTestable(
          DictionaryCsvPreviewPage(
            result: result,
            existingTriggerKeys: {normalizeTriggerKey('MFG')},
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.dictionaryCsvPreviewAddCount(2)), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dictionary-csv-preview-select-2')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('dictionary-csv-preview-select-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.dictionaryCsvPreviewAddCount(1)), findsOneWidget);
      expect(find.text(l10n.dictionaryCsvPreviewAddCount(2)), findsNothing);
    },
  );
}
