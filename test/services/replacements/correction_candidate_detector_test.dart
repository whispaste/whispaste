import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';

void main() {
  group('normalizeCorrectionKey', () {
    test('ignores case and whitespace runs', () {
      expect(
        normalizeCorrectionKey('Foo  Bar', 'Baz'),
        normalizeCorrectionKey('foo bar', 'baz'),
      );
    });

    test('keeps "a b" -> "c" apart from "a" -> "b c"', () {
      expect(
        normalizeCorrectionKey('a b', 'c'),
        isNot(normalizeCorrectionKey('a', 'b c')),
      );
    });
  });

  group('extractCorrectionCandidates', () {
    test('a single misspelled word yields one word-level pair', () {
      final pairs = extractCorrectionCandidates(
        before: 'We deploy Kubernetis tomorrow.',
        after: 'We deploy Kubernetes tomorrow.',
      );

      expect(pairs, [
        const CorrectionCandidatePair(
          sourceText: 'Kubernetis',
          targetText: 'Kubernetes',
        ),
      ]);
    });

    test('case-only change yields nothing', () {
      expect(
        extractCorrectionCandidates(
          before: 'hello world',
          after: 'Hello world',
        ),
        isEmpty,
      );
    });

    test('punctuation-only change yields nothing', () {
      expect(
        extractCorrectionCandidates(
          before: 'see Kubernetes here',
          after: 'see Kubernetes here.',
        ),
        isEmpty,
      );
    });

    test('a rewrite of more than four changed words is dropped', () {
      expect(
        extractCorrectionCandidates(
          before: 'alpha bravo charlie delta echo foxtrot',
          after: 'one two three four five six',
        ),
        isEmpty,
      );
    });

    test('a pure insertion has nothing to replace', () {
      expect(
        extractCorrectionCandidates(
          before: 'the meeting ends',
          after: 'the big meeting ends',
        ),
        isEmpty,
      );
    });

    test('a pair of stop words only is dropped', () {
      expect(
        extractCorrectionCandidates(
          before: 'das ist gut',
          after: 'die ist gut',
        ),
        isEmpty,
      );
    });

    test('a pure number as source is dropped, a number as target is kept', () {
      expect(
        extractCorrectionCandidates(
          before: 'Platz 1 frei',
          after: 'Platz 2 frei',
        ),
        isEmpty,
      );
      expect(
        extractCorrectionCandidates(before: 'drei Teile', after: '3 Teile'),
        [const CorrectionCandidatePair(sourceText: 'drei', targetText: '3')],
      );
    });

    test('a phrase longer than the limit is dropped', () {
      final long = 'a' * (correctionMaxPhraseChars + 1);
      expect(
        extractCorrectionCandidates(before: 'x $long y', after: 'x zz y'),
        isEmpty,
      );
    });

    test('unspaced CJK text is dropped', () {
      expect(
        extractCorrectionCandidates(before: '你好世界吗', after: '你好地界吗'),
        isEmpty,
      );
    });

    test('empty input yields nothing', () {
      expect(extractCorrectionCandidates(before: '', after: ''), isEmpty);
      expect(
        extractCorrectionCandidates(before: '', after: 'hallo welt'),
        isEmpty,
      );
    });

    test('at most two candidates, names and technical terms first', () {
      final pairs = extractCorrectionCandidates(
        before: 'alpha gamma wispaste theta delta kappa',
        after: 'beta gamma WhisPaste theta epsilon kappa',
      );

      expect(pairs, hasLength(correctionMaxCandidatesPerCorrection));
      expect(pairs.first.targetText, 'WhisPaste');
    });

    test(
      'a typo fixed to a stop word is kept, a stop word replaced is not',
      () {
        expect(
          extractCorrectionCandidates(before: 'teh cat', after: 'the cat'),
          [const CorrectionCandidatePair(sourceText: 'teh', targetText: 'the')],
        );
        expect(
          extractCorrectionCandidates(before: 'the cat', after: 'teh cat'),
          isEmpty,
        );
      },
    );

    test('Unicode words are compared and kept', () {
      expect(
        extractCorrectionCandidates(
          before: 'Die Grüße kommen',
          after: 'Die Grüsse kommen',
        ),
        [
          const CorrectionCandidatePair(
            sourceText: 'Grüße',
            targetText: 'Grüsse',
          ),
        ],
      );
    });
  });

  group('isDuplicateCorrectionCandidate', () {
    const pair = CorrectionCandidatePair(
      sourceText: 'teh',
      targetText: 'Kubernetes',
    );

    test('a source that is already a trigger is a duplicate', () {
      expect(
        isDuplicateCorrectionCandidate(
          pair,
          existingTriggers: {'teh'},
          existingTerms: const {},
        ),
        isTrue,
      );
    });

    test('a target that is already a term is a duplicate, case ignored', () {
      expect(
        isDuplicateCorrectionCandidate(
          pair,
          existingTriggers: const {},
          existingTerms: {'kubernetes'},
        ),
        isTrue,
      );
    });

    test('an unrelated pair is not a duplicate', () {
      expect(
        isDuplicateCorrectionCandidate(
          pair,
          existingTriggers: {'other'},
          existingTerms: {'other'},
        ),
        isFalse,
      );
    });
  });

  group('applyCorrectionCandidate', () {
    const pair = CorrectionCandidatePair(sourceText: 'teh', targetText: 'the');
    final t0 = DateTime(2026, 1, 1);

    test('the first occurrence is pending and not yet a candidate', () {
      final outcome = applyCorrectionCandidate(pair, t0, null);

      expect(outcome.observation.occurrenceCount, 1);
      expect(outcome.observation.status, CorrectionObservationStatus.pending);
      expect(outcome.becameCandidate, isFalse);
      expect(isCorrectionCandidate(outcome.observation), isFalse);
    });

    test('the second occurrence crosses the threshold exactly once', () {
      final first = applyCorrectionCandidate(pair, t0, null);
      final second = applyCorrectionCandidate(pair, t0, first.observation);
      final third = applyCorrectionCandidate(pair, t0, second.observation);

      expect(second.becameCandidate, isTrue);
      expect(isCorrectionCandidate(second.observation), isTrue);
      expect(third.becameCandidate, isFalse);
      expect(third.observation.occurrenceCount, 3);
    });

    test('an occurrence exactly at the decay window still counts', () {
      final first = applyCorrectionCandidate(pair, t0, null);
      final second = applyCorrectionCandidate(
        pair,
        t0.add(correctionDecayWindow),
        first.observation,
      );

      expect(second.becameCandidate, isTrue);
    });

    test('an observation older than the decay window starts again at 1', () {
      final first = applyCorrectionCandidate(pair, t0, null);
      final later = applyCorrectionCandidate(
        pair,
        t0.add(correctionDecayWindow + const Duration(days: 1)),
        first.observation,
      );

      expect(later.observation.occurrenceCount, 1);
      expect(later.becameCandidate, isFalse);
    });

    test('an accepted observation is returned unchanged', () {
      final accepted = CorrectionObservation(
        sourceText: 'teh',
        targetText: 'the',
        occurrenceCount: 2,
        status: CorrectionObservationStatus.accepted,
        lastSeenAt: t0,
      );

      final outcome = applyCorrectionCandidate(pair, t0, accepted);

      expect(outcome.observation, accepted);
      expect(outcome.becameCandidate, isFalse);
    });

    test('a rejected observation never comes back as a candidate', () {
      final rejected = CorrectionObservation(
        sourceText: 'teh',
        targetText: 'the',
        occurrenceCount: 2,
        status: CorrectionObservationStatus.rejected,
        lastSeenAt: t0,
      );

      final outcome = applyCorrectionCandidate(
        pair,
        t0.add(const Duration(days: 365)),
        rejected,
      );

      expect(outcome.observation.status, CorrectionObservationStatus.rejected);
      expect(isCorrectionCandidate(outcome.observation), isFalse);
    });
  });
}
