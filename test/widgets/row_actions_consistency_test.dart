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
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_compact_view.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/widgets/wp_row_action.dart';

import '../fixtures/test_helpers.dart';

/// Narrowest the history list panel gets (`WpSplitView._minListWidth`).
const _minPanelWidth = 240.0;

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
  onDuplicate: () {},
  onPin: () {},
  onDelete: () {},
);

Widget _compactRow() => HistoryCompactRow(
  entry: _entry(),
  isSelected: false,
  onTap: () {},
  onCopy: () {},
  onDuplicate: () {},
  onPin: () {},
  onDelete: () {},
);

Widget _notesRow({bool isQuickNote = false}) => NotesListTile(
  note: _note(isQuickNote: isQuickNote),
  tags: const [],
  isTrashView: false,
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

    testWidgets('compact stays denser than the list view', (tester) async {
      await tester.pumpWidget(
        makeTestable(_panel(Column(children: [_historyRow(), _compactRow()]))),
      );
      await tester.pumpAndSettle();

      final listHeight = tester.getSize(find.byType(HistoryEntryRow)).height;
      final compactHeight = tester
          .getSize(find.byType(HistoryCompactRow))
          .height;
      expect(compactHeight * 2, lessThan(listHeight));
    });
  });

  group('revealing actions costs neither information nor layout', () {
    testWidgets('the list row keeps its timestamp while hovered', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_panel(_historyRow())));
      await tester.pumpAndSettle();
      expect(find.text('09:41'), findsOneWidget);

      await _hover(tester, find.byType(HistoryEntryRow));
      expect(
        find.text('09:41'),
        findsOneWidget,
        reason: 'actions must not take the timestamp\'s place',
      );
    });

    testWidgets('the list row does not change height while hovered', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_panel(_historyRow())));
      await tester.pumpAndSettle();
      final atRest = tester.getSize(find.byType(HistoryEntryRow)).height;

      await _hover(tester, find.byType(HistoryEntryRow));
      expect(tester.getSize(find.byType(HistoryEntryRow)).height, atRest);
    });

    testWidgets('the compact row does not change height while hovered', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_panel(_compactRow())));
      await tester.pumpAndSettle();
      final atRest = tester.getSize(find.byType(HistoryCompactRow)).height;

      await _hover(tester, find.byType(HistoryCompactRow));
      expect(tester.getSize(find.byType(HistoryCompactRow)).height, atRest);
    });
  });

  group('no overflow while the actions are revealed', () {
    // Each row is pinned to the narrowest panel it is actually expected to
    // survive. The list and notes rows hold the app's 240px minimum; the
    // compact row cannot, because its duration/language/time cluster is
    // fixed-width and, unlike the list row, it has no second line to move
    // anything to — three revealed actions plus that cluster need ~320px.
    // A 150% system font pushes every row one step up. Measured, not
    // guessed; the ticket records the compact-row limit as a known one.
    final rows = <(String, Type, Widget Function(), double)>[
      ('history list row', HistoryEntryRow, _historyRow, _minPanelWidth),
      ('history compact row', HistoryCompactRow, _compactRow, 320.0),
      ('notes row', NotesListTile, _notesRow, _minPanelWidth),
      // The notes row's tightest case: the quick-note mark is permanent, so
      // this row carries star + mark + title + date with no reveal left to
      // collapse (ticket 22).
      (
        'notes row (quick note)',
        NotesListTile,
        () => _notesRow(isQuickNote: true),
        _minPanelWidth,
      ),
    ];

    for (final (name, type, build, minWidth) in rows) {
      for (final (width, scale) in [(minWidth, 1.0), (360.0, 1.5)]) {
        testWidgets('$name at ${width.toInt()}px, textScaler $scale', (
          tester,
        ) async {
          await tester.pumpWidget(
            makeTestable(_panel(build(), width: width, scale: scale)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await _hover(tester, find.byType(type));
          expect(
            tester.takeException(),
            isNull,
            reason: 'revealing the actions must not overflow the row',
          );
        });
      }
    }
  });
}
