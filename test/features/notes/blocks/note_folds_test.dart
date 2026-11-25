// Folding heading sections of a long note (#1344): which rows a fold hides,
// how folds survive an edit, and that hidden rows take no room in the
// height index. A fold never touches the text.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/blocks/long_note_layout.dart';
import 'package:whispaste/features/notes/blocks/note_folds.dart';

const _doc =
    'Intro\n\n'
    '# A\n\n'
    'a1\n\n'
    '## A.1\n\n'
    'a11\n\n'
    '## A.2\n\n'
    'a21\n\n'
    '# B\n\n'
    'b1\n\n'
    '# C';

// Rows: 0 Intro, 1 # A, 2 a1, 3 ## A.1, 4 a11, 5 ## A.2, 6 a21, 7 # B,
// 8 b1, 9 # C.

void main() {
  group('NoteSections', () {
    test('a section runs to the next heading of its level or higher', () {
      final s = NoteSections.of(NoteRows.of(_doc));
      expect(s.count, 5);
      expect(
        [for (var i = 0; i < s.count; i++) s.headingRow(i)],
        [1, 3, 5, 7, 9],
      );
      expect([for (var i = 0; i < s.count; i++) s.endOf(i)], [7, 5, 7, 9, 10]);
      expect(s.isFoldable(4), isFalse, reason: 'last heading has no body');
      expect(s.foldable, {0, 1, 2, 3});
    });

    test('hidden rows: a nested fold hides with its parent', () {
      final rows = NoteRows.of(_doc);
      final s = NoteSections.of(rows);
      List<int> hidden(Set<int> folded) {
        final mask = s.hiddenRows(folded, rows.length);
        return [
          for (var r = 0; r < mask.length; r++)
            if (mask[r]) r,
        ];
      }

      expect(hidden({}), isEmpty);
      expect(hidden({1}), [4]);
      expect(hidden({0}), [2, 3, 4, 5, 6]);
      expect(hidden({0, 1}), [2, 3, 4, 5, 6]);
      expect(hidden({3}), [8]);
      expect(hidden({4}), isEmpty, reason: 'nothing to fold under # C');
    });

    test('finds the section at a row and the folds around it', () {
      final s = NoteSections.of(NoteRows.of(_doc));
      expect(s.innermostAt(0), isNull, reason: 'before the first heading');
      expect(s.innermostAt(1), 0);
      expect(s.innermostAt(4), 1);
      expect(s.innermostAt(6), 2);
      expect(s.innermostAt(9), isNull, reason: '# C has no body');
      expect(s.outermostAround(4), 0);
      expect(s.outermostAround(1), isNull);
      expect(s.foldedAround(4, {0, 1, 3}), {0, 1});
      expect(s.sectionOfHeadingRow(5), 2);
      expect(s.sectionOfHeadingRow(4), isNull);
      expect(s.valid([0, 4, 9, -1]), {0});
    });
  });

  group('carryFolds', () {
    Set<int> carry(Set<int> folded, String before, String after) => carryFolds(
      folded: folded,
      oldText: before,
      oldRows: NoteRows.of(before),
      newText: after,
      newRows: NoteRows.of(after),
    );

    test('a new heading above shifts the ordinals', () {
      const after = '# New\n\nx\n\n$_doc';
      expect(carry({1, 3}, _doc, after), {2, 4});
    });

    test('typing inside a folded body keeps the fold', () {
      final after = _doc.replaceFirst('a11', 'a11 und mehr');
      expect(carry({1}, _doc, after), {1});
    });

    test('a blank line inserted right before a folded heading keeps it', () {
      final at = _doc.indexOf('# B');
      final after = '${_doc.substring(0, at)}\n${_doc.substring(at)}';
      expect(carry({3}, _doc, after), {3});
    });

    test('a heading that is no heading any more loses its fold', () {
      final after = _doc.replaceFirst('## A.1', 'A.1');
      expect(carry({1, 3}, _doc, after), {2});
    });
  });

  group('HeightIndex hides rows', () {
    test('hidden rows take no room and keep their height', () {
      final rows = NoteRows.of(_doc);
      final index = HeightIndex();
      const key = LayoutKey(width: 400, textScale: 1, devicePixelRatio: 1);
      index.ensureLayout(key, rows, 16);
      for (var r = 0; r < rows.length; r++) {
        index.measure(r, 10);
      }
      expect(index.offsetOf(7), moreOrLessEquals(70));
      final mask = NoteSections.of(rows).hiddenRows({0}, rows.length);
      index.setHidden(mask);
      expect(index.heightOf(4), 0);
      expect(
        index.offsetOf(7),
        moreOrLessEquals(20),
        reason: 'rows 2–6 are folded away',
      );
      expect(index.anchorAt(20).row, 7, reason: 'hidden rows are skipped');
      // A row measured while hidden comes back with that height.
      index.measure(4, 30);
      expect(index.heightOf(4), 0);
      index.setHidden(List.filled(rows.length, false));
      expect(index.heightOf(4), 30);
      expect(index.offsetOf(7), moreOrLessEquals(90));
    });

    test('a new layout keeps the folds of a mask that fits', () {
      final rows = NoteRows.of(_doc);
      final index = HeightIndex();
      index.setHidden(NoteSections.of(rows).hiddenRows({3}, rows.length));
      index.ensureLayout(
        const LayoutKey(width: 400, textScale: 1, devicePixelRatio: 1),
        rows,
        16,
      );
      expect(index.heightOf(8), 0);
      expect(index.heightOf(7), greaterThan(0));
    });
  });
}
