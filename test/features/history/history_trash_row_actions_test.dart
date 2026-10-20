// UIA-HIS-09: trashed rows offer restore and permanent delete, nothing else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry() => HistoryEntry(
  id: 'trash-1',
  content: 'Trashed content',
  title: 'Trashed title',
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
    'a trashed row offers restore and permanent delete (UIA-HIS-09)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: _entry(),
            isSelected: false,
            isFocused: true,
            isTrashView: true,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onRestore: () {},
            onDuplicate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip(l10n.historyRestore), findsOneWidget);
      expect(find.byTooltip(l10n.historyDeleteForever), findsOneWidget);
      expect(find.byTooltip(l10n.historyPinToTop), findsNothing);
      expect(find.byTooltip(l10n.actionDuplicate), findsNothing);
      expect(find.byTooltip(l10n.actionDelete), findsNothing);
    },
  );
}
