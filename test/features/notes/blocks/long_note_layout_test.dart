import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/blocks/block_document.dart';
import 'package:whispaste/features/notes/blocks/long_note_layout.dart';

void main() {
  group('PrefixSums', () {
    test('sums, updates and finds positions', () {
      final sums = PrefixSums([3, 0, 5, 2]);
      expect(sums.total, 10);
      expect(sums.sumBefore(2), 3);
      expect(sums.indexAt(0), 0);
      expect(sums.indexAt(2.9), 0);
      expect(sums.indexAt(3), 2, reason: 'zero-sized entry is skipped');
      expect(sums.indexAt(8), 3);
      expect(sums.indexAt(99), 3, reason: 'clamped to the last entry');
      sums.set(1, 4);
      expect(sums.sumBefore(2), 7);
      expect(sums.indexAt(5), 1);
    });

    test('matches a naive sum on a large list', () {
      final values = [for (var i = 0; i < 1000; i++) (i % 7).toDouble()];
      final sums = PrefixSums(values);
      var naive = 0.0;
      for (var i = 0; i < values.length; i++) {
        expect(sums.sumBefore(i), naive);
        naive += values[i];
      }
    });
  });

  group('NoteRows', () {
    test('rows cover the text without the separators', () {
      const text = '\n\n# Title\n\nFirst para\nsecond line\n\n- item\n';
      final rows = NoteRows.of(text);
      expect(rows.length, 3);
      expect(rows.leading, 2);
      final texts = [
        for (var r = 0; r < rows.length; r++)
          text.substring(rows.startOf(r), rows.endOf(r)),
      ];
      expect(texts, ['# Title', 'First para\nsecond line', '- item']);
      expect(rows.headingLevelOf(0), 1);
      expect(rows.lineBreaksOf(1), 1);
    });

    test('rowOf maps every offset, separators to the row before', () {
      const text = 'One\n\nTwo\n\nThree';
      final rows = NoteRows.of(text);
      expect(rows.rowOf(0), 0);
      expect(rows.rowOf(3), 0);
      expect(rows.rowOf(4), 0, reason: 'inside the separator');
      expect(rows.rowOf(5), 1);
      expect(rows.rowOf(text.length), 2);
    });

    test('a giant paragraph is split for display only', () {
      const sentence = 'This is a sentence of the giant paragraph. ';
      final text = List.filled(200, sentence).join();
      final rows = NoteRows.of(text);
      expect(rows.length, greaterThan(1));
      expect(rows.blockCount, 1);
      final joined = StringBuffer();
      for (var r = 0; r < rows.length; r++) {
        expect(
          rows.lengthOf(r),
          lessThanOrEqualTo(BlockDocument.softSplitChars),
        );
        joined.write(text.substring(rows.startOf(r), rows.endOf(r)));
      }
      expect(joined.toString(), text, reason: 'source text unchanged');
      // Every row but the first starts after a sentence end.
      for (var r = 1; r < rows.length; r++) {
        expect(text.substring(rows.startOf(r) - 2, rows.startOf(r)), '. ');
      }
    });

    test('resize moves later rows without a re-parse', () {
      final rows = NoteRows.of('One\n\nTwo');
      rows.resize(0, 6);
      expect(rows.startOf(1), 8);
      expect(rows.rowOf(7), 0); // The separator belongs to the preceding row.
      expect(rows.rowOf(8), 1);
    });

    test('empty and blank texts have one row for the caret', () {
      expect(NoteRows.of('').length, 1);
      final blank = NoteRows.of('\n\n');
      expect(blank.length, 1);
      expect(blank.startOf(0), 2);
      expect(blank.endOf(0), 2);
    });
  });

  group('HeightIndex', () {
    const key = LayoutKey(width: 600, textScale: 1, devicePixelRatio: 2);
    NoteRows rowsOf(int n) =>
        NoteRows.of(List.generate(n, (i) => 'Paragraph $i').join('\n\n'));

    test('measured heights replace estimates', () {
      final rows = rowsOf(10);
      final index = HeightIndex()..ensureLayout(key, rows, 16);
      final estimated = index.heightOf(3);
      expect(index.measure(3, estimated + 40), isTrue);
      expect(index.isMeasured(3), isTrue);
      expect(
        index.offsetOf(4) - index.offsetOf(3),
        closeTo(estimated + 40, 1e-9),
      );
      expect(index.measure(3, estimated + 40.2), isFalse);
    });

    test('anchor is row plus offset and survives a new layout', () {
      final rows = rowsOf(100);
      final index = HeightIndex()..ensureLayout(key, rows, 16);
      final anchor = index.anchorAt(index.offsetOf(40) + 5);
      expect(anchor, const HeightAnchor(40, 5));
      // Narrower window: every height changes, the anchor still names row 40.
      expect(
        index.ensureLayout(
          const LayoutKey(width: 200, textScale: 1, devicePixelRatio: 2),
          rows,
          16,
        ),
        isTrue,
      );
      expect(index.anchorAt(index.offsetFor(anchor)).row, 40);
    });

    test('zoom, width and text scale invalidate measurements', () {
      final rows = rowsOf(5);
      final index = HeightIndex()..ensureLayout(key, rows, 16);
      index.measure(1, 99);
      expect(index.ensureLayout(key, rows, 16), isFalse);
      for (final changed in const [
        LayoutKey(width: 601, textScale: 1, devicePixelRatio: 2),
        LayoutKey(width: 601, textScale: 1.3, devicePixelRatio: 2),
        LayoutKey(width: 601, textScale: 1.3, devicePixelRatio: 1),
      ]) {
        index.measure(1, 99);
        expect(index.ensureLayout(changed, rows, 16), isTrue);
        expect(index.isMeasured(1), isFalse);
      }
    });

    test('rebase keeps heights of unchanged rows at both ends', () {
      final old = rowsOf(10);
      final index = HeightIndex()..ensureLayout(key, old, 16);
      index
        ..measure(0, 70)
        ..measure(9, 90);
      // A paragraph inserted in the middle.
      final text = List.generate(10, (i) => 'Paragraph $i').toList()
        ..insert(5, 'New one');
      final fresh = NoteRows.of(text.join('\n\n'));
      index.rebase(old, fresh, 16);
      expect(index.length, 11);
      expect(index.heightOf(0), 70);
      expect(index.heightOf(10), 90);
      expect(index.isMeasured(5), isFalse);
    });

    test('jump offsets on a 100,000-word note come from the index', () {
      final text = List.generate(
        5000,
        (i) =>
            i % 50 == 0 ? '## Heading $i' : List.filled(20, 'word').join(' '),
      ).join('\n\n');
      final rows = NoteRows.of(text);
      final index = HeightIndex()..ensureLayout(key, rows, 16);
      final target = rows.firstRowOfBlock(4950);
      final offset = index.offsetOf(target);
      expect(index.anchorAt(offset).row, target);
      expect(rows.headingLevelOf(target), 2);
    });
  });

  group('LongNoteLimits', () {
    test('hysteresis between entering and leaving long mode', () {
      expect(LongNoteLimits.useLongMode(29999, currentlyLong: false), isFalse);
      expect(LongNoteLimits.useLongMode(30000, currentlyLong: false), isTrue);
      expect(LongNoteLimits.useLongMode(25000, currentlyLong: true), isTrue);
      expect(LongNoteLimits.useLongMode(23999, currentlyLong: true), isFalse);
    });
  });

  group('splitOffset', () {
    const text = 'One\n\nTwo\n\nThree\n\nFour';

    test('cuts at the block boundary at or before the caret', () {
      expect(splitOffset(text, caret: 12), text.indexOf('Three'));
      expect(splitOffset(text, caret: 10), text.indexOf('Three'));
      expect(splitOffset(text, caret: 1), text.indexOf('Two'));
    });

    test('without caret cuts near the middle', () {
      expect(splitOffset(text), text.indexOf('Three'));
    });

    test('a single block is cut softly after a sentence', () {
      const one = 'First sentence here. Second one there. Third.';
      final cut = splitOffset(one)!;
      expect(one.substring(0, cut), 'First sentence here. ');
    });

    test('nothing to split', () {
      expect(splitOffset(''), isNull);
      expect(splitOffset('word'), isNull);
    });
  });
}
