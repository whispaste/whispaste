/// Every decision button of a suggestion row exposes an accessible name that
/// contains the suggestion (#820), in every app language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  for (final locale in L10n.supportedLocales) {
    testWidgets(
      'suggestion buttons name the suggestion (${locale.languageCode})',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const Scaffold(body: DictionarySuggestionsTab()),
            locale: locale,
            overrides: [
              pendingCorrectionCandidatesProvider.overrideWith(
                (ref) => Future.value(const [
                  CorrectionCandidate(
                    id: 'c1',
                    sourceText: 'teh',
                    targetText: 'the',
                    occurrenceCount: 2,
                  ),
                ]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        for (final id in ['replace', 'term', 'reject']) {
          final button = find.byKey(ValueKey('dictionary-suggestion-$id-c1'));
          expect(button, findsOneWidget);
          final label = tester.getSemantics(button).label;
          expect(label, contains('teh'));
          expect(label, contains('the'));
        }
      },
    );
  }
}
