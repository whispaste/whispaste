/// A failed decision on a suggestion is shown to the user and the list is
/// reloaded, so it reflects what is really stored (reliability-decide-2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_notice.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';

class _FailingLearningService extends CorrectionLearningService {
  @override
  Future<CorrectionCommitResult> commit({
    required Map<String, CorrectionDecision> decisions,
    required HistoryDatabase db,
    Future<void> Function(List<String> terms)? saveTerms,
  }) async => throw StateError('disk full');
}

void main() {
  testWidgets('a failing decision shows an error and reloads the list', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    var loads = 0;

    await tester.pumpWidget(
      makeTestable(
        const Scaffold(
          body: Column(
            children: [
              WpPageNoticeSlot(page: dictionaryNoticePage),
              Expanded(child: DictionarySuggestionsTab()),
            ],
          ),
        ),
        locale: const Locale('en'),
        overrides: [
          correctionLearningServiceProvider.overrideWithValue(
            _FailingLearningService(),
          ),
          pendingCorrectionCandidatesProvider.overrideWith((ref) {
            loads++;
            return Future.value(const [
              CorrectionCandidate(
                id: 'c1',
                sourceText: 'foo',
                targetText: 'bar',
                occurrenceCount: 3,
              ),
            ]);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);

    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestion-reject-c1')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.dictionarySuggestionFailed), findsOneWidget);
    expect(find.text(l10n.dictionarySuggestionRejected), findsNothing);
    expect(loads, 2);
    // The suggestion is still offered and can be decided again.
    expect(
      find.byKey(const ValueKey('dictionary-suggestion-reject-c1')),
      findsOneWidget,
    );

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
