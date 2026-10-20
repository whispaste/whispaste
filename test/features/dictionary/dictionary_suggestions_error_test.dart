/// A failed load of the correction suggestions is shown as an error, not as
/// the "no suggestions" empty state (UIA-DIC-02).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets(
    'a failed suggestions load shows the error, not the empty state',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        makeTestable(
          const Scaffold(body: DictionarySuggestionsTab()),
          locale: const Locale('en'),
          overrides: [
            pendingCorrectionCandidatesProvider.overrideWith(
              (ref) => Future.error(StateError('db locked')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorGeneric), findsOneWidget);
      expect(find.text(l10n.dictionarySuggestionsEmpty), findsNothing);
    },
  );
}
