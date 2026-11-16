/// Load states of the correction suggestions (UIA-DIC-02, #321): while the
/// list loads and when it fails, the tab does not claim "no suggestions"; a
/// failed load names the next step and can be retried.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('while loading, the tab shows the loading rows, not empty', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    final pending = Completer<List<CorrectionCandidate>>();
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: DictionarySuggestionsTab()),
        locale: const Locale('en'),
        overrides: [
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) => pending.future,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('dictionary-suggestions-loading')),
      findsOneWidget,
    );
    expect(find.text(l10n.dictionarySuggestionsEmpty), findsNothing);

    pending.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text(l10n.dictionarySuggestionsEmpty), findsOneWidget);
  });

  testWidgets('a failed load says what to do and retries on request', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    var calls = 0;
    await tester.pumpWidget(
      makeTestable(
        const Scaffold(body: DictionarySuggestionsTab()),
        locale: const Locale('en'),
        overrides: [
          pendingCorrectionCandidatesProvider.overrideWith((ref) {
            calls++;
            return calls == 1
                ? Future.error(StateError('db locked'))
                : Future.value(const <CorrectionCandidate>[]);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.dictionarySuggestionsLoadFailed), findsOneWidget);
    expect(find.text(l10n.dictionarySuggestionsLoadFailedNext), findsOneWidget);
    expect(find.text(l10n.dictionarySuggestionsEmpty), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestions-retry')),
    );
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text(l10n.dictionarySuggestionsLoadFailed), findsNothing);
    expect(find.text(l10n.dictionarySuggestionsEmpty), findsOneWidget);
  });
}
