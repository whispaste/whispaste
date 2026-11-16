import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_word_diff.dart';

void main() {
  group('diffCorrectionWords', () {
    test('one changed word yields one hunk', () {
      expect(diffCorrectionWords('a Kubernetis b', 'a Kubernetes b'), [
        const CorrectionHunk(
          sourceWords: ['Kubernetis'],
          targetWords: ['Kubernetes'],
        ),
      ]);
    });

    test('identical texts change nothing', () {
      expect(diffCorrectionWords('same text', 'same text'), isEmpty);
    });

    test('case and punctuation alone do not count as changed words', () {
      expect(diffCorrectionWords('hallo welt', 'Hallo Welt!'), isEmpty);
      expect(diffCorrectionWords('wort', 'wort —'), isEmpty);
    });

    test('a text too large to compare returns null', () {
      final before = List.generate(600, (i) => 'x$i').join(' ');
      final after = List.generate(600, (i) => 'y$i').join(' ');

      expect(diffCorrectionWords(before, after), isNull);
    });

    test('a long text with one change keeps exactly one hunk', () {
      final words = List.generate(2000, (i) => 'w$i');
      final before = words.join(' ');
      words[1000] = 'changed';
      final after = words.join(' ');

      expect(diffCorrectionWords(before, after), [
        const CorrectionHunk(sourceWords: ['w1000'], targetWords: ['changed']),
      ]);
    });

    test('empty texts produce no hunk', () {
      expect(diffCorrectionWords('', ''), isEmpty);
    });

    test('Hebrew and Cyrillic words are compared like any other', () {
      expect(diffCorrectionWords('שלום עולם', 'שלם עולם'), [
        const CorrectionHunk(sourceWords: ['שלום'], targetWords: ['שלם']),
      ]);
      expect(diffCorrectionWords('привет мир', 'привед мир'), [
        const CorrectionHunk(sourceWords: ['привет'], targetWords: ['привед']),
      ]);
    });
  });

  group('extractCorrectionCandidates over the word diff', () {
    test('mixed-language text keeps only the changed word', () {
      expect(
        extractCorrectionCandidates(
          before: 'Das Meeting ist in Berlin, see you soon',
          after: 'Das Meeting ist in Berlin, see you later',
        ),
        [
          const CorrectionCandidatePair(
            sourceText: 'soon',
            targetText: 'later',
          ),
        ],
      );
    });

    test('a single character change is not dropped by the diff', () {
      expect(extractCorrectionCandidates(before: 'ein Ort', after: 'ein Oft'), [
        const CorrectionCandidatePair(sourceText: 'Ort', targetText: 'Oft'),
      ]);
    });
  });
}
