// UIA-HIS-11: "Retry" in the error state reloads the view that failed, not
// only the all-entries list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry() => HistoryEntry(
  id: 'retry-1',
  content: 'Recovered content',
  title: 'Recovered title',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 10.0,
  processingDurationSec: 0.5,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: DateTime(2026, 4, 15),
  titleEdited: false,
  colorSlot: 0,
);

void main() {
  testWidgets(
    'retry in the trash reloads the trash, not the all list (UIA-HIS-11)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      var trashLoads = 0;
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          locale: const Locale('en'),
          overrides: [
            historyEntriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            archivedEntriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            trashEntriesProvider.overrideWith((ref) {
              trashLoads++;
              return trashLoads == 1
                  ? Stream<List<HistoryEntry>>.error(StateError('trash broke'))
                  : Stream.value([_entry()]);
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPage)),
      );
      container.read(historyFilterProvider.notifier).set(HistoryFilter.trash);
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorGeneric), findsOneWidget);
      await tester.tap(find.text(l10n.actionRetry));
      await tester.pumpAndSettle();

      expect(trashLoads, 2);
      expect(find.text(l10n.errorGeneric), findsNothing);
      expect(find.text('Recovered title'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
