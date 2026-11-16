import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/text_comparison.dart';

void main() {
  group('diffWords', () {
    test('marks added and removed words inside a sentence', () {
      final r = diffWords('the quick brown fox', 'the slow brown fox jumps');
      expect(r.coarse, isFalse);
      expect(r.spans, const [
        DiffSpan(DiffKind.same, 'the'),
        DiffSpan(DiffKind.removed, 'quick'),
        DiffSpan(DiffKind.added, 'slow'),
        DiffSpan(DiffKind.same, 'brown fox'),
        DiffSpan(DiffKind.added, 'jumps'),
      ]);
    });

    test('empty and identical texts', () {
      expect(diffWords('', '').spans, isEmpty);
      expect(diffWords('a b', 'a  b').spans, const [
        DiffSpan(DiffKind.same, 'a b'),
      ]);
      expect(diffWords('', 'a b').spans, const [
        DiffSpan(DiffKind.added, 'a b'),
      ]);
      expect(diffWords('a b', '').spans, const [
        DiffSpan(DiffKind.removed, 'a b'),
      ]);
    });

    test('falls back to one removed and one added block above the limit', () {
      final a = List.generate(2500, (i) => 'a$i').join(' ');
      final b = List.generate(2500, (i) => 'b$i').join(' ');
      final r = diffWords(a, b);
      expect(r.coarse, isTrue);
      expect(r.spans.map((s) => s.kind), [DiffKind.removed, DiffKind.added]);
    });
  });

  group('splitSections', () {
    test('sections concatenate back to the text', () {
      for (final t in [
        '',
        'one',
        'one\n\ntwo\n\n\nthree\n',
        '\n\nlead',
        List.generate(3000, (i) => 'w$i').join(' '),
      ]) {
        expect(splitSections(t).join(), t);
      }
    });

    test('a long paragraph is cut and an insertion keeps later cuts', () {
      final words = List.generate(3000, (i) => 'w$i');
      final a = splitSections(words.join(' '));
      final edited = [...words]..insert(10, 'extra');
      final b = splitSections(edited.join(' '));
      expect(a.length, greaterThan(5));
      final aTrim = a.map((s) => s.trim()).toSet();
      final same = b.where((s) => aTrim.contains(s.trim())).length;
      expect(same, greaterThanOrEqualTo(b.length - 2));
    });
  });

  group('compareTexts', () {
    test('identical and empty texts have no hunks', () {
      expect(compareTexts('', '').identical, isTrue);
      expect(compareTexts('a\n\nb', 'a\n\nb').identical, isTrue);
      expect(compareTexts('a b', 'a   b').identical, isTrue);
    });

    test('only the changed paragraph gets a word diff', () {
      final c = compareTexts('one two\n\nthree four', 'one two\n\nthree five');
      expect(c.hunks, hasLength(1));
      expect(c.hunks.single.spans, const [
        DiffSpan(DiffKind.same, 'three'),
        DiffSpan(DiffKind.removed, 'four'),
        DiffSpan(DiffKind.added, 'five'),
      ]);
      expect(c.hunks.single.addedWords, 1);
      expect(c.hunks.single.removedWords, 1);
      expect(c.unchangedSections, 1);
    });

    test('takeOver brings back one paragraph and leaves the rest', () {
      const old = 'a one\n\nb two\n\nc three';
      const now = 'a ONE\n\nb two\n\nc THREE';
      final c = compareTexts(old, now);
      expect(c.hunks, hasLength(2));
      expect(c.takeOver(0), 'a one\n\nb two\n\nc THREE');
      expect(c.takeOver(1), 'a ONE\n\nb two\n\nc three');
    });

    test('takeOver of a paragraph only in the old text inserts it', () {
      final c = compareTexts('a\n\nb\n\nc', 'a\n\nc');
      expect(c.hunks.single.onlyInOld, isTrue);
      expect(c.takeOver(0), 'a\n\nb\n\nc');
      final tail = compareTexts('a\n\nb', 'a');
      expect(tail.takeOver(0), 'a\n\nb');
    });

    test('takeOver of a paragraph only in the current text removes it', () {
      final c = compareTexts('a\n\nc', 'a\n\nb\n\nc');
      expect(c.hunks.single.onlyInCurrent, isTrue);
      expect(c.takeOver(0), 'a\n\nc');
    });

    test('taking over every hunk gives back the old words', () {
      const old = 'x y z\n\nm n\n\no p';
      const now = 'x q z\n\nextra\n\no p r';
      var text = now;
      var c = compareTexts(old, text);
      while (!c.identical) {
        text = c.takeOver(0);
        c = compareTexts(old, text);
      }
      expect(text.split(RegExp(r'\s+')), old.split(RegExp(r'\s+')));
    });

    test('a 20,000 word dictation without blank lines compares exactly', () {
      final words = List.generate(20000, (i) => 'w${i * 7 % 1013}x$i');
      final edited = [...words]
        ..[150] = 'changed'
        ..removeAt(9000)
        ..insert(15000, 'inserted');
      final c = compareTexts(words.join(' '), edited.join(' '));
      expect(c.hunks, isNotEmpty);
      expect(c.hunks.every((h) => !h.coarse), isTrue);
      final added = c.hunks.fold(0, (n, h) => n + h.addedWords);
      final removed = c.hunks.fold(0, (n, h) => n + h.removedWords);
      expect(added, 2);
      expect(removed, 2);
    });
  });
}
