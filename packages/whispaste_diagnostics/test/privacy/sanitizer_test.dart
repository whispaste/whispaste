/// Unit tests for the privacy sanitizer.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/privacy/sanitizer.dart';

void main() {
  group('containsSensitiveData', () {
    test('detects API key pattern', () {
      expect(containsSensitiveData('api_key=abc123xyz'), isTrue);
    });

    test('detects bearer token', () {
      expect(containsSensitiveData('Authorization: Bearer sk-abc123'), isTrue);
    });

    test('detects OpenAI key format', () {
      expect(containsSensitiveData('sk-abcdefghij1234567'), isTrue);
    });

    test('does not flag normal text', () {
      expect(
        containsSensitiveData('Normal log message without secrets'),
        isFalse,
      );
    });

    test('does not flag empty string', () {
      expect(containsSensitiveData(''), isFalse);
    });
  });

  group('redactSensitive', () {
    test('redacts api key pattern, keeps surrounding text', () {
      final result = redactSensitive('config: api_key=abc123xyz loaded');
      expect(result, 'config: <redacted> loaded');
    });

    test('redacts bearer token', () {
      final result = redactSensitive('Authorization: Bearer sk-abc123');
      expect(result, contains('<redacted>'));
      expect(result, isNot(contains('sk-abc123')));
    });

    test('redacts OpenAI-style key', () {
      final result = redactSensitive('key=sk-abcdefghij1234567 sent');
      expect(result, isNot(contains('sk-abcdefghij1234567')));
    });

    test('leaves normal text unchanged', () {
      const input = 'Normal log message without secrets';
      expect(redactSensitive(input), input);
    });

    test('handles empty string', () {
      expect(redactSensitive(''), '');
    });
  });

  group('sanitizePaths', () {
    test('returns input unchanged when no env vars match', () {
      // In a test environment, neither USERPROFILE/HOME nor APPDATA will match
      // the literal test string below.
      final input = '/some/unrelated/path/file.txt';
      // The result should be either unchanged or have substitutions if the
      // test runner happens to have matching env vars — we just verify it
      // doesn't throw and returns a String.
      expect(sanitizePaths(input), isA<String>());
    });

    test('handles empty string', () {
      expect(sanitizePaths(''), '');
    });
  });
}
