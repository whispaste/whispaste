// UIA-HIS-17: refining the search keeps the selection that is still visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry(String id, String content, DateTime ts) => HistoryEntry(
  id: id,
  content: content,
  title: content,
  timestamp: ts,
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
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

void main() {
  testWidgets(
    'a narrower search keeps the visible part of the selection (UIA-HIS-17)',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final l10n = await L10n.delegate.load(const Locale('en'));
      final entries = [
        _entry('a', 'Alpha note', DateTime(2026, 1, 3, 9)),
        _entry('b', 'Beta note', DateTime(2026, 1, 2, 9)),
        _entry('c', 'Gamma note', DateTime(2026, 1, 1, 9)),
      ];

      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          locale: const Locale('en'),
          overrides: [
            historyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
            archivedEntriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha note').first);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(primaryShortcutModifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(primaryShortcutModifier);
      await tester.pumpAndSettle();
      expect(find.text(l10n.historyItemsSelected(3)), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Alpha');
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyItemsSelected(1)), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
