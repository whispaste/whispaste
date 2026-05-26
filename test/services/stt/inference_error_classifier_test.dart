/// Unit tests for inference_error_classifier.dart — pure function, no DI.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/services/stt/inference_error_classifier.dart';

/// Helper: build a context with sensible defaults so individual tests only
/// override the fields they care about. Keeps test bodies focused on the
/// status-code / body assertions instead of context plumbing.
InferenceRequestContext _ctx({
  int wavSizeBytes = 12345,
  int audioDurationMs = 2000,
  String language = 'de',
  String modelId = 'ggml-base.bin',
  int promptLength = 0,
  int vocabLength = 0,
}) {
  return InferenceRequestContext(
    wavSizeBytes: wavSizeBytes,
    audioDurationMs: audioDurationMs,
    language: language,
    modelId: modelId,
    promptLength: promptLength,
    vocabLength: vocabLength,
  );
}

void main() {
  group('InferenceErrorClassifier.classify — kind/fingerprint mapping', () {
    test('400 → clientBadRequest / inferenceBadRequest', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 400,
        responseBody: 'bad request',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.clientBadRequest);
      expect(f.fingerprint, inferenceBadRequest);
    });

    test('413 → payloadTooLarge / inferencePayloadTooLarge', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 413,
        responseBody: 'too big',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.payloadTooLarge);
      expect(f.fingerprint, inferencePayloadTooLarge);
    });

    test('415 → unsupportedMedia / inferenceUnsupportedMedia', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 415,
        responseBody: 'unsupported',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.unsupportedMedia);
      expect(f.fingerprint, inferenceUnsupportedMedia);
    });

    test('500 → serverInternal / inferenceServerError', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: 'internal',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.serverInternal);
      expect(f.fingerprint, inferenceServerError);
    });

    test('503 → serverInternal / inferenceServerError (5xx range)', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 503,
        responseBody: 'unavailable',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.serverInternal);
      expect(f.fingerprint, inferenceServerError);
    });

    test('418 (unknown 4xx) → unknown / inferenceUnknownStatus', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 418,
        responseBody: "I'm a teapot",
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.unknown);
      expect(f.fingerprint, inferenceUnknownStatus);
    });

    test('5xx boundaries: 500 and 599 both map to serverInternal', () {
      final f500 = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: '',
        context: _ctx(),
      );
      final f599 = InferenceErrorClassifier.classify(
        statusCode: 599,
        responseBody: '',
        context: _ctx(),
      );
      expect(f500.kind, InferenceFailureKind.serverInternal);
      expect(f599.kind, InferenceFailureKind.serverInternal);
    });

    test('600 (above 5xx) → unknown / inferenceUnknownStatus', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 600,
        responseBody: '',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.unknown);
      expect(f.fingerprint, inferenceUnknownStatus);
    });

    test(
      '200 (unexpected success path) → unknown / inferenceUnknownStatus',
      () {
        // Caller only invokes classifier on non-success; defensive mapping.
        final f = InferenceErrorClassifier.classify(
          statusCode: 200,
          responseBody: 'ok',
          context: _ctx(),
        );
        expect(f.kind, InferenceFailureKind.unknown);
        expect(f.fingerprint, inferenceUnknownStatus);
      },
    );
  });

  group('InferenceErrorClassifier.classify — PII redaction', () {
    test('Unix absolute path is replaced by <path>', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody:
            'error opening /Users/silvio/Documents/audio.wav for reading',
        context: _ctx(),
      );
      expect(f.redactedBody, 'error opening <path> for reading');
    });

    test('Windows drive-letter path is replaced by <path>', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody:
            r'error opening C:\Users\silvio\Documents\audio.wav for reading',
        context: _ctx(),
      );
      expect(f.redactedBody, 'error opening <path> for reading');
    });

    test('Windows UNC path is replaced by <path>', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: r'error opening \\server\share\audio.wav for reading',
        context: _ctx(),
      );
      expect(f.redactedBody, 'error opening <path> for reading');
    });

    test('multiple paths in the same body are all replaced', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody:
            r'cannot copy /tmp/a.wav to C:\dest\b.wav (via \\nas\share\x.wav)',
        context: _ctx(),
      );
      expect(f.redactedBody, 'cannot copy <path> to <path> (via <path>)');
    });

    test('body without any path stays unchanged', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 400,
        responseBody: 'malformed multipart boundary',
        context: _ctx(),
      );
      expect(f.redactedBody, 'malformed multipart boundary');
    });
  });

  group('InferenceErrorClassifier.classify — truncation', () {
    test('body > 200 chars is truncated to exactly 200 chars', () {
      final body = 'a' * 1024;
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: body,
        context: _ctx(),
      );
      expect(f.redactedBody.length, 200);
      expect(f.redactedBody, 'a' * 200);
    });

    test('body of 50 chars is returned unchanged (no padding)', () {
      const body = 'short error message here';
      expect(body.length, lessThan(200));
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: body,
        context: _ctx(),
      );
      expect(f.redactedBody, body);
      expect(f.redactedBody.length, body.length);
    });

    test('body of exactly 200 chars is unchanged', () {
      final body = 'b' * 200;
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: body,
        context: _ctx(),
      );
      expect(f.redactedBody, body);
      expect(f.redactedBody.length, 200);
    });

    test(
      'redaction happens BEFORE truncation — long prefix + path at end gets redacted',
      () {
        // Build a body whose first 200 chars do NOT contain the path, but
        // after redaction the slice does include the redacted `<path>` literal.
        //
        // Strategy: 199 leading 'x' chars + Unix path at the end (length 30+).
        // Pre-redaction length: 199 + 30 = 229 → simple truncation would cut
        // the path off entirely.
        // Post-redaction: 199 'x' + '<path>' = 205 → truncated to 200, but
        // crucially the truncated tail must STILL show `<path>` because the
        // redaction shrinks the body BEFORE the 200-char slice.
        //
        // We can verify this by checking the redacted body contains '<path>'
        // even though a raw 200-char slice of the original would not.
        final body = '${'x' * 199}/Users/silvio/Documents/audio.wav';
        // Sanity: substring(0, 200) of the raw body would be 199 x + '/'.
        expect(body.substring(0, 200), '${'x' * 199}/');

        final f = InferenceErrorClassifier.classify(
          statusCode: 500,
          responseBody: body,
          context: _ctx(),
        );
        expect(f.redactedBody.length, 200);
        // After redaction body is "xxx...x<path>" (205 chars); first 200 chars
        // = 199 x + '<'. The presence of '<' (from '<path>') at position 199
        // proves redaction ran BEFORE truncation: a raw 200-char slice of the
        // un-redacted body would have '/' at position 199, not '<'.
        expect(f.redactedBody, '${'x' * 199}<');
        expect(f.redactedBody[199], '<');
      },
    );
  });

  group('InferenceErrorClassifier.classify — extras', () {
    test(
      'all six context fields are mirrored into extras (snake_case keys)',
      () {
        final f = InferenceErrorClassifier.classify(
          statusCode: 500,
          responseBody: '',
          context: const InferenceRequestContext(
            wavSizeBytes: 32768,
            audioDurationMs: 4321,
            language: 'en',
            modelId: 'ggml-large-v3.bin',
            promptLength: 17,
            vocabLength: 5,
          ),
        );
        expect(f.extras, {
          'wav_size_bytes': 32768,
          'audio_duration_ms': 4321,
          'language': 'en',
          'model_id': 'ggml-large-v3.bin',
          'prompt_length': 17,
          'vocab_length': 5,
        });
        // Exact set, no extra keys.
        expect(f.extras.keys.length, 6);
      },
    );
  });

  group('InferenceErrorClassifier.classify — robustness', () {
    test('empty body classifies without throwing', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: 500,
        responseBody: '',
        context: _ctx(),
      );
      expect(f.redactedBody, '');
      expect(f.kind, InferenceFailureKind.serverInternal);
    });

    test('negative status code maps to unknown', () {
      final f = InferenceErrorClassifier.classify(
        statusCode: -1,
        responseBody: '',
        context: _ctx(),
      );
      expect(f.kind, InferenceFailureKind.unknown);
      expect(f.fingerprint, inferenceUnknownStatus);
    });

    test('InferenceFailureKind has exactly five cases', () {
      expect(InferenceFailureKind.values.length, 5);
    });

    test('value equality on InferenceFailure', () {
      final a = InferenceErrorClassifier.classify(
        statusCode: 400,
        responseBody: 'x',
        context: _ctx(),
      );
      final b = InferenceErrorClassifier.classify(
        statusCode: 400,
        responseBody: 'x',
        context: _ctx(),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
