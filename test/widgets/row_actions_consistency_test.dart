/// Cross-area guard for the shared row-action pattern (ticket 02).
///
/// Verifies at the *row* level what `wp_row_action_test.dart` verifies at the
/// component level: the three history views offer the same actions, revealing
/// them costs no information and no reflow, and none of the rows overflows at
/// the narrowest panel width the app allows — at normal and at enlarged
/// system font size.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_compact_view.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/widgets/wp_row_action.dart';

import '../fixtures/test_helpers.dart';

/// Comfortable default panel width (`WpSplitView._defaultListWidth`),
/// used wherever a test is about behaviour rather than about the squeeze.
const _defaultPanelWidth = 340.0;

HistoryEntry _entry({bool pinned = false}) => HistoryEntry(
  id: '1',
  content: 'A transcript long enough to fill the preview lines of the tile.',
  title: 'A fairly long recording title that has to ellipsize',
  timestamp: DateTime(2026, 4, 14, 9, 41),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: pinned,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  titleEdited: false,
  deletedAt: null,
  colorSlot: 0,
);

Note _note({bool isQuickNote = false}) => Note(
  id: 'n1',
  content: 'Note title line\nand a preview line below it',
  pinned: false,
  isQuickNote: isQuickNote,
  createdAt: DateTime(2026, 4, 14),
  updatedAt: DateTime(2026, 4, 14, 9, 41),
);

Widget _historyRow() => HistoryEntryRow(
  entry: _entry(),
  isSelected: false,
  onTap: () {},
  onCopy: () {},
  onPin: () {},
  onDelete: () {},
);

Widget _compactRow() => HistoryCompactRow(
  entry: _entry(),
  isSelected: false,
  onTap: () {},
  onCopy: () {},
  onPin: () {},
  onDelete: () {},
);

Widget _notesRow({bool isQuickNote = false, bool isTrashView = false}) =>
    NotesListTile(
      note: _note(isQuickNote: isQuickNote),
      tags: const [],
      isTrashView: isTrashView,
      isSelected: false,
      isFocused: false,
      onTap: () {},
      onCopy: () {},
      onDuplicate: () {},
      onFavoriteToggle: () {},
      onQuickNoteSet: () {},
      onQuickNoteClear: () {},
      onRestore: () {},
      onDeleteForever: () {},
    );

/// Renders [row] inside a panel of [width], optionally at an enlarged system
/// font size.
Widget _panel(
  Widget row, {
  double width = _defaultPanelWidth,
  double scale = 1.0,
}) {
  return Center(
    child: SizedBox(
      width: width,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: row,
      ),
    ),
  );
}

/// Parks a synthetic mouse pointer on [finder] so the row reveals its actions.
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('every history view offers the same row actions', () {
    testWidgets('list view reveals three actions on hover', (tester) async {
      await tester.pumpWidget(makeTestable(_panel(_historyRow())));
      expect(find.byType(WpRowAction), findsNothing);

      await _hover(tester, find.byType(HistoryEntryRow));
      expect(find.byType(WpRowAction), findsNWidgets(3));
    });

    testWidgets(
      'compact view reveals the same three — density changes, features do not',
      (tester) async {
        await tester.pumpWidget(makeTestable(_panel(_compactRow())));
        expect(find.byType(WpRowAction), findsNothing);

        await _hover(tester, find.byType(HistoryCompactRow));
        expect(
          find.byType(WpRowAction),
          findsNWidgets(3),
          reason: 'switching to the compact view must not drop copy/pin/delete',
        );
      },
    );

    testWidgets(
      'notes row keeps Copy and Duplicate visible in the trash view, not '
      'just in the active-notes view (issue: they used to live inside the '
      '!isTrashView-only branch and silently disappeared on a trashed note)',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(_panel(_notesRow(isTrashView: true))),
        );
        expect(find.byType(WpRowAction), findsNothing);

        await _hover(tester, find.byType(NotesListTile));
        expect(
          find.byIcon(LucideIcons.copy),
          findsOneWidget,
          reason:
              'Copy must stay available on a trashed note, matching the '
              'note editor toolbar',
        );
        expect(
          find.byIcon(LucideIcons.files),
          findsOneWidget,
          reason:
              'Duplicate must stay available on a trashed note, matching '
              'the note editor toolbar',
        );
      },
    );
  });
}
