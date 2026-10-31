/// A second tap on a suggestion decision while the first one is still being
/// saved does not decide it again (UIA-DIC-13).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import '../../fixtures/test_helpers.dart';

class _SlowLearningService extends CorrectionLearningService {
  _SlowLearningService(this.gate);

  final Completer<void> gate;
  int commits = 0;

  @override
  Future<int> commit({
    required List<String> shownIds,
    required List<String> acceptedIds,
    required HistoryDatabase db,
  }) async {
    commits++;
    await gate.future;
    return 0;
  }
}

void main() {
  testWidgets('a second reject tap during the save is ignored (UIA-DIC-13)', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    final gate = Completer<void>();
    final service = _SlowLearningService(gate);

    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: DictionarySuggestionsTab()),
        locale: const Locale('en'),
        overrides: [
          correctionLearningServiceProvider.overrideWithValue(service),
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) => Future.value(const [
              CorrectionCandidate(
                id: 'c1',
                sourceText: 'foo',
                targetText: 'bar',
                occurrenceCount: 3,
              ),
            ]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final reject = find.byKey(
      const ValueKey('dictionary-suggestion-reject-c1'),
    );
    await tester.tap(reject);
    await tester.pump();
    await tester.tap(reject, warnIfMissed: false);
    await tester.pump();

    expect(service.commits, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(l10n.dictionarySuggestionRejected), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
