import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/transcript_hygiene.dart';

void main() {
  group('collapseRepeatedSentences', () {
    test('a short interjection repeated three times is speech and stays', () {
      expect(collapseRepeatedSentences('Ja. Ja. Ja.'), 'Ja. Ja. Ja.');
      expect(
        collapseRepeatedSentences('Ja. Ja. Ja. Dann ist gut.'),
        'Ja. Ja. Ja. Dann ist gut.',
      );
      expect(
        collapseRepeatedSentences('Okay. Okay. Okay. Dann passt es.'),
        'Okay. Okay. Okay. Dann passt es.',
      );
    });

    test('a long sentence repeated in a loop keeps two copies', () {
      expect(
        collapseRepeatedSentences(
          'Ich glaube das ist so. Ich glaube das ist so. '
          'Ich glaube das ist so. Ich glaube das ist so.',
        ),
        'Ich glaube das ist so. Ich glaube das ist so.',
      );
    });

    test('four words are enough to collapse', () {
      expect(
        collapseRepeatedSentences(
          'Nein das stimmt sicher. Nein das stimmt sicher. Nein das stimmt sicher.',
        ),
        'Nein das stimmt sicher. Nein das stimmt sicher.',
      );
    });

    test('three words under 20 characters do not collapse', () {
      const text = 'So ist es. So ist es. So ist es.';
      expect(collapseRepeatedSentences(text), text);
    });

    test('text without a loop comes back unchanged, whitespace included', () {
      const text = 'Hallo.\n\nWie geht es dir heute? Gut!';
      expect(collapseRepeatedSentences(text), text);
    });
  });

  group('stripNonSpeechMarkers', () {
    test('bracket tags go and the spacing is tidied', () {
      expect(
        stripNonSpeechMarkers('[Musik]  Hallo   [Pause] Welt'),
        'Hallo Welt',
      );
    });

    test('round brackets are dictated text and stay', () {
      expect(stripNonSpeechMarkers('Das war (ein Witz)'), 'Das war (ein Witz)');
    });
  });

  group('applyTranscriptHygiene', () {
    test('a transcript that is only a sound annotation becomes empty', () {
      expect(applyTranscriptHygiene('[Musik]'), '');
      expect(applyTranscriptHygiene('(Musik)'), '');
      expect(applyTranscriptHygiene('  [BLANK_AUDIO]  '), '');
    });

    test('a normal dictation is returned as it is', () {
      expect(applyTranscriptHygiene('Hallo Welt'), 'Hallo Welt');
    });

    test('a bracket tag inside a dictation is dropped, the rest kept', () {
      expect(applyTranscriptHygiene('[Applause] Hallo Welt'), 'Hallo Welt');
    });

    test('applying it twice changes nothing', () {
      const samples = [
        '[Musik] Ich glaube das ist so. Ich glaube das ist so. '
            'Ich glaube das ist so. Ich glaube das ist so.',
        'Ja. Ja. Ja. Dann ist gut.',
        '  Hallo [Pause]  Welt  ',
        '[Musik]',
        'Das war (ein Witz)',
      ];
      for (final sample in samples) {
        final once = applyTranscriptHygiene(sample);
        expect(applyTranscriptHygiene(once), once, reason: sample);
      }
    });
  });
}
