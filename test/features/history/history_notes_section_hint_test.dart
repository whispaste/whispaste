/// Widget tests for the voice-note discoverability hint wired into
/// [HistoryNotesSection] (issue 03, experience-perf-polish Cluster 2).
///
/// Verifies the shared [WpDiscoverabilityHint] component is actually used at
/// this call site: visible by default once the add-note input opens, and
/// permanently gone once the "seen" flag has been persisted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_notes_section.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'shows the voice-note prefix hint once the add-note input opens',
    (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryNotesSection(entryId: 'hint-test-entry'),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.historyAddNote));
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyVoiceNoteHint), findsOneWidget);

      // Drain any pending Drift/Riverpod cleanup timers before the test
      // framework tears down the widget tree, otherwise the framework's
      // `!timersPending` invariant fires from the in-memory DB's
      // `StreamQueryStore.markAsClosed` scheduling a zero-duration timer.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('stays hidden once the seen-flag is already persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'discoverability_hint_seen_voice_note_prefixes': true,
    });

    await tester.pumpWidget(
      makeTestable(
        const HistoryNotesSection(entryId: 'hint-test-entry'),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.historyAddNote));
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyVoiceNoteHint), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
