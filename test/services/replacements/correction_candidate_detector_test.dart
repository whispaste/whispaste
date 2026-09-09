import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';

CorrectionSignal _signal(
  String source,
  String target, {
  DateTime? at,
  CorrectionSignalSource source_ = CorrectionSignalSource.voiceCommand,
}) => CorrectionSignal(
  sourceText: source,
  targetText: target,
  timestamp: at ?? DateTime(2026, 1, 1),
  source: source_,
);

void main() {
  group('normalizeCorrectionKey', () {
    test('is case-insensitive', () {
      expect(
        normalizeCorrectionKey('Teh', 'The'),
        normalizeCorrectionKey('teh', 'the'),
      );
    });

    test('differs when either side differs', () {
      expect(
        normalizeCorrectionKey('teh', 'the'),
        isNot(normalizeCorrectionKey('teh', 'them')),
      );
      expect(
        normalizeCorrectionKey('teh', 'the'),
        isNot(normalizeCorrectionKey('hte', 'the')),
      );
    });

    test('collapses whitespace differences', () {
      expect(
        normalizeCorrectionKey('foo  bar', 'baz'),
        normalizeCorrectionKey('foo bar', 'baz'),
      );
    });
  });

  group('applyCorrectionSignal — threshold behavior', () {
    test('a single observation does not become a candidate', () {
      final outcome = applyCorrectionSignal(_signal('teh', 'the'), null);

      expect(outcome.observation.occurrenceCount, 1);
      expect(outcome.observation.status, CorrectionObservationStatus.pending);
      expect(outcome.becameCandidate, isFalse);
      expect(isCorrectionCandidate(outcome.observation), isFalse);
    });

    test(
      'the second observation of the same correction becomes a candidate',
      () {
        final first = applyCorrectionSignal(_signal('teh', 'the'), null);
        final second = applyCorrectionSignal(
          _signal('teh', 'the'),
          first.observation,
        );

        expect(second.observation.occurrenceCount, 2);
        expect(second.becameCandidate, isTrue);
        expect(isCorrectionCandidate(second.observation), isTrue);
      },
    );

    test('becameCandidate is only true on the crossing observation', () {
      var observation = applyCorrectionSignal(
        _signal('teh', 'the'),
        null,
      ).observation;
      observation = applyCorrectionSignal(
        _signal('teh', 'the'),
        observation,
      ).observation; // -> candidate here
      final third = applyCorrectionSignal(_signal('teh', 'the'), observation);

      expect(third.observation.occurrenceCount, 3);
      expect(third.becameCandidate, isFalse);
      expect(isCorrectionCandidate(third.observation), isTrue);
    });

    test('tracks the most recent original-case text', () {
      final first = applyCorrectionSignal(_signal('Teh', 'The'), null);
      final second = applyCorrectionSignal(
        _signal('TEH', 'THE'),
        first.observation,
      );

      expect(second.observation.sourceText, 'TEH');
      expect(second.observation.targetText, 'THE');
    });
  });

  group('applyCorrectionSignal — rejected/accepted are frozen', () {
    test('a rejected observation is never re-counted toward candidacy', () {
      const rejected = CorrectionObservation(
        sourceText: 'teh',
        targetText: 'the',
        occurrenceCount: 5,
        status: CorrectionObservationStatus.rejected,
      );

      final outcome = applyCorrectionSignal(_signal('teh', 'the'), rejected);

      expect(outcome.observation, rejected);
      expect(outcome.becameCandidate, isFalse);
      expect(isCorrectionCandidate(outcome.observation), isFalse);
    });

    test('an accepted observation is left untouched by further repeats', () {
      const accepted = CorrectionObservation(
        sourceText: 'teh',
        targetText: 'the',
        occurrenceCount: 2,
        status: CorrectionObservationStatus.accepted,
      );

      final outcome = applyCorrectionSignal(_signal('teh', 'the'), accepted);

      expect(outcome.observation, accepted);
      expect(outcome.becameCandidate, isFalse);
    });
  });
}
