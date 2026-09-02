/// Tests for [WpListSkeleton] and — more importantly — for the calibration of
/// the two `rowHeight` values its callers pass in.
///
/// A skeleton is only worth showing when its bars reserve the space the real
/// rows will occupy. The old hard-coded 52 (history) and 64 (notes) reserved
/// well under half a row, so the list visibly re-flowed the moment the stream
/// emitted. The band assertions below measure the *real* tiles and fail if
/// they drift away from the constants in `history_page.dart` /
/// `notes_page.dart` — which is the signal to re-tune those constants.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/widgets/wp_list_skeleton.dart';

import '../fixtures/test_helpers.dart';

/// Mirrors `_historySkeletonRowHeight` in `lib/features/history/history_page.dart`.
const _historySkeletonRowHeight = 128.0;

/// Mirrors `_notesSkeletonRowHeight` in `lib/features/notes/notes_page.dart`.
const _notesSkeletonRowHeight = 104.0;

/// Width of the list column at its default split-view size.
const _listWidth = 340.0;

/// A dictated entry / note as it usually looks: a title line plus enough body
/// for the two-line preview both tiles cap at.
const _populatedContent =
    'Erste Zeile mit einem Titel\n'
    'Das hier ist ein laengerer Vorschautext, der ueber zwei Zeilen laeuft '
    'und danach noch weiter geht, damit die Vorschau wirklich zweizeilig '
    'umbricht und nicht kuerzer bleibt.';

HistoryEntry _entry() => HistoryEntry(
  id: 'h1',
  content: _populatedContent,
  title: 'Erste Zeile mit einem Titel',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 30.0,
  processingDurationSec: 1.0,
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

Note _note() => Note(
  id: 'n1',
  content: _populatedContent,
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  isQuickNote: false,
  deletedAt: null,
);

/// Pumps [child] at [_listWidth] with an unbounded height so the tile reports
/// its intrinsic height instead of being stretched by the Scaffold.
Future<Size> _measure(WidgetTester tester, Widget child, Finder of) async {
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(
        child: SizedBox(width: _listWidth, child: child),
      ),
    ),
  );
  return tester.getSize(of);
}

void main() {
  group('WpListSkeleton', () {
    testWidgets('renders `count` bars at exactly `rowHeight`', (tester) async {
      await tester.pumpWidget(
        makeTestable(const WpListSkeleton(rowHeight: 96, count: 4)),
      );

      final bars = find.descendant(
        of: find.byType(WpListSkeleton),
        matching: find.byType(Container),
      );
      expect(bars, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(bars.at(i)).height, 96);
      }
    });

    testWidgets('honours the default count of six', (tester) async {
      await tester.pumpWidget(
        makeTestable(const WpListSkeleton(rowHeight: 48)),
      );
      expect(
        find.descendant(
          of: find.byType(WpListSkeleton),
          matching: find.byType(Container),
        ),
        findsNWidgets(6),
      );
    });
  });

  group('skeleton calibration', () {
    testWidgets('history bar matches a populated HistoryEntryRow', (
      tester,
    ) async {
      final size = await _measure(
        tester,
        HistoryEntryRow(
          entry: _entry(),
          isSelected: false,
          onTap: () {},
          onCopy: () {},
          onDuplicate: () {},
          onPin: () {},
          onDelete: () {},
        ),
        find.byType(HistoryEntryRow),
      );

      expect(
        (size.height - _historySkeletonRowHeight).abs(),
        lessThanOrEqualTo(8),
        reason:
            'HistoryEntryRow now measures ${size.height} dp — re-tune '
            '_historySkeletonRowHeight in history_page.dart.',
      );
    });

    testWidgets('notes bar matches a populated NotesListTile', (tester) async {
      final size = await _measure(
        tester,
        NotesListTile(
          note: _note(),
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
        ),
        find.byType(NotesListTile),
      );

      expect(
        (size.height - _notesSkeletonRowHeight).abs(),
        lessThanOrEqualTo(8),
        reason:
            'NotesListTile now measures ${size.height} dp — re-tune '
            '_notesSkeletonRowHeight in notes_page.dart.',
      );
    });
  });
}
