import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/transcript_hallucination_filter.dart';

void main() {
  group('isKnownHallucinationPhrase', () {
    test(
      'matches a known closing phrase regardless of case and punctuation',
      () {
        expect(isKnownHallucinationPhrase('Thanks for watching!'), isTrue);
        expect(
          isKnownHallucinationPhrase('  thank you for watching. '),
          isTrue,
        );
        expect(isKnownHallucinationPhrase('Danke fürs Zuschauen!'), isTrue);
        expect(
          isKnownHallucinationPhrase('Untertitel der Amara.org-Community'),
          isTrue,
        );
      },
    );

    test('does not match when the phrase is only part of the transcript', () {
      expect(
        isKnownHallucinationPhrase('Ich sage gerade thanks for watching.'),
        isFalse,
      );
    });

    test('does not match ordinary short dictation', () {
      expect(isKnownHallucinationPhrase('Vielen Dank.'), isFalse);
      expect(isKnownHallucinationPhrase('Thank you.'), isFalse);
    });

    test('does not match an empty transcript', () {
      expect(isKnownHallucinationPhrase(''), isFalse);
      expect(isKnownHallucinationPhrase('   '), isFalse);
    });
  });

  group('isNonSpeechTranscript', () {
    test('a lone sound annotation in round brackets is not speech', () {
      for (final text in [
        '(Musik)',
        '(music)',
        '( Applaus )',
        '(Applause).',
        '(музыка)',
        '(מוזיקה)',
        '[Musik]',
      ]) {
        expect(isNonSpeechTranscript(text), isTrue, reason: text);
      }
    });

    test('known hallucination phrases are not speech', () {
      expect(isNonSpeechTranscript('Thank you for watching.'), isTrue);
    });

    test('dictated brackets and other bracketed text are kept', () {
      expect(isNonSpeechTranscript('Ich sage (Musik) laut.'), isFalse);
      expect(isNonSpeechTranscript('(siehe oben)'), isFalse);
      expect(isNonSpeechTranscript('(Musik) (Applaus)'), isFalse);
      expect(isNonSpeechTranscript('Musik'), isFalse);
      expect(isNonSpeechTranscript(''), isFalse);
    });
  });
}
