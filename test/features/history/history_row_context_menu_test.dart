/// Right-clicking a history row opens the same actions as its hover buttons
/// (UIA-HIS-32).
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({bool pinned = false}) => HistoryEntry(
  id: 'ctx-1',
  content: 'Some content',
  title: 'Context title',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 10.0,
  processingDurationSec: 0.5,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: pinned,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required HistoryEntry entry,
  bool isTrashView = false,
  VoidCallback? onCopy,
  VoidCallback? onPin,
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
  VoidCallback? onRestore,
}) async {
  await tester.pumpWidget(
    makeTestable(
      HistoryEntryRow(
        entry: entry,
        isSelected: false,
        isTrashView: isTrashView,
        onTap: () {},
        onCopy: onCopy ?? () {},
        onPin: onPin ?? () {},
        onDelete: onDelete ?? () {},
        onRestore: onRestore,
        onDuplicate: onDuplicate,
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'right-click on a row offers copy, pin, duplicate and delete (UIA-HIS-32)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      var copied = 0;
      await _pumpRow(
        tester,
        entry: _entry(),
        onCopy: () => copied++,
        onDuplicate: () {},
      );

      await tester.tap(
        find.byType(HistoryEntryRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyCopyText), findsOneWidget);
      expect(find.text(l10n.historyPinToTop), findsOneWidget);
      expect(find.text(l10n.actionDuplicate), findsOneWidget);
      expect(find.text(l10n.actionDelete), findsOneWidget);

      await tester.tap(find.text(l10n.historyCopyText));
      await tester.pumpAndSettle();
      expect(copied, 1);
    },
  );

  testWidgets(
    'right-click on a trashed row offers restore and delete forever (UIA-HIS-32)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      var restored = 0;
      await _pumpRow(
        tester,
        entry: _entry(),
        isTrashView: true,
        onRestore: () => restored++,
      );

      await tester.tap(
        find.byType(HistoryEntryRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyCopyText), findsNothing);
      expect(find.text(l10n.historyRestore), findsOneWidget);
      expect(find.text(l10n.historyDeleteForever), findsOneWidget);

      await tester.tap(find.text(l10n.historyRestore));
      await tester.pumpAndSettle();
      expect(restored, 1);
    },
  );
}
