/// 9.10: mapping of whisper's detected language id and the mismatch rule
/// behind the wrong-language hint. Pure Dart, no dylib needed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_language_probe.dart';

void main() {
  group('detectedLanguageCode', () {
    test('maps a valid id through the code lookup', () {
      final codes = {0: 'en', 3: 'de'};
      expect(detectedLanguageCode(3, (id) => codes[id]), 'de');
    });

    test('negative id means unknown and never calls the lookup', () {
      var called = false;
      expect(
        detectedLanguageCode(-1, (id) {
          called = true;
          return 'en';
        }),
        isNull,
      );
      expect(called, isFalse);
    });

    test('missing or blank code means unknown', () {
      expect(detectedLanguageCode(7, (_) => null), isNull);
      expect(detectedLanguageCode(7, (_) => '   '), isNull);
    });

    test('trims the code returned by the lookup', () {
      expect(detectedLanguageCode(1, (_) => ' fr '), 'fr');
    });
  });

  group('isLanguageMismatch', () {
    test('fires on a clear mismatch with enough words', () {
      expect(
        isLanguageMismatch(configured: 'de', detected: 'en', wordCount: 8),
        isTrue,
      );
    });

    test('never fires on automatic detection', () {
      expect(
        isLanguageMismatch(configured: 'auto', detected: 'en', wordCount: 20),
        isFalse,
      );
      expect(
        isLanguageMismatch(configured: '', detected: 'en', wordCount: 20),
        isFalse,
      );
    });

    test('stays silent when the detected language is unknown', () {
      expect(
        isLanguageMismatch(configured: 'de', detected: null, wordCount: 20),
        isFalse,
      );
      expect(
        isLanguageMismatch(configured: 'de', detected: '', wordCount: 20),
        isFalse,
      );
    });

    test('stays silent on short transcripts', () {
      expect(
        isLanguageMismatch(configured: 'de', detected: 'en', wordCount: 4),
        isFalse,
      );
      expect(
        isLanguageMismatch(
          configured: 'de',
          detected: 'en',
          wordCount: 2,
          minWords: 2,
        ),
        isTrue,
      );
    });

    test('compares codes case-insensitively', () {
      expect(
        isLanguageMismatch(configured: 'DE', detected: 'de', wordCount: 20),
        isFalse,
      );
    });

    test('no hint when detected equals configured', () {
      expect(
        isLanguageMismatch(configured: 'es', detected: 'es', wordCount: 20),
        isFalse,
      );
    });
  });
}
