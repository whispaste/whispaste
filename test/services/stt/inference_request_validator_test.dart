/// Unit tests for inference_request_validator.dart — pure function, no DI.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/inference_request_validator.dart';

/// Helper: build a minimal but valid 44-byte WAV RIFF/WAVE header with no
/// audio payload. The validator only checks the magic bytes, not any other
/// header field — keeping this helper deterministic and self-contained.
Uint8List _validWavHeader({int totalLength = 44}) {
  final bytes = Uint8List(totalLength);
  // 'RIFF' at offset 0..3
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  // chunk size at 4..7 — irrelevant for the validator, leave as 0
  // 'WAVE' at offset 8..11
  bytes[8] = 0x57; // W
  bytes[9] = 0x41; // A
  bytes[10] = 0x56; // V
  bytes[11] = 0x45; // E
  return bytes;
}

/// Helper: header that starts with 'XXXX' but has 'WAVE' at offset 8.
/// Used to verify that the validator checks RIFF magic, not only WAVE.
Uint8List _bogusRiffButWave() {
  final bytes = Uint8List(44);
  bytes[0] = 0x58; // X
  bytes[1] = 0x58; // X
  bytes[2] = 0x58; // X
  bytes[3] = 0x58; // X
  bytes[8] = 0x57; // W
  bytes[9] = 0x41; // A
  bytes[10] = 0x56; // V
  bytes[11] = 0x45; // E
  return bytes;
}

/// Helper: header that has 'RIFF' at offset 0 but garbage at 8..11.
Uint8List _riffButBogusWave() {
  final bytes = Uint8List(44);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  bytes[8] = 0x59; // Y
  bytes[9] = 0x59; // Y
  bytes[10] = 0x59; // Y
  bytes[11] = 0x59; // Y
  return bytes;
}

void main() {
  group('InferenceRequestValidator.validate', () {
    test('happy path: valid WAV + supported lang + short prompt → ok', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: 'hallo',
        supportedLanguages: const {'de', 'en'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationOk>());
    });

    test('reject: empty wavBytes → Reject(empty)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: Uint8List(0),
        language: 'de',
        prompt: null,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      final reject = result as ValidationReject;
      expect(reject.reason, InferenceRejectReason.empty);
      expect(reject.userMessageKey, 'stt.reject.empty');
    });

    test('reject: missing RIFF magic → Reject(invalidWav)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _bogusRiffButWave(),
        language: 'de',
        prompt: null,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      expect(
        (result as ValidationReject).reason,
        InferenceRejectReason.invalidWav,
      );
      expect(result.userMessageKey, 'stt.reject.invalid_wav');
    });

    test('reject: missing WAVE marker → Reject(invalidWav)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _riffButBogusWave(),
        language: 'de',
        prompt: null,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      expect(
        (result as ValidationReject).reason,
        InferenceRejectReason.invalidWav,
      );
    });

    test('reject: language not in set → Reject(unsupportedLanguage)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'jp',
        prompt: null,
        supportedLanguages: const {'de', 'en'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      expect(
        (result as ValidationReject).reason,
        InferenceRejectReason.unsupportedLanguage,
      );
      expect(result.userMessageKey, 'stt.reject.unsupported_language');
    });

    test('reject: prompt longer than limit → Reject(promptTooLong)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: 'x' * 101,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      expect(
        (result as ValidationReject).reason,
        InferenceRejectReason.promptTooLong,
      );
      expect(result.userMessageKey, 'stt.reject.prompt_too_long');
    });

    test("language 'auto' passes even when not in supportedLanguages set", () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'auto',
        prompt: null,
        supportedLanguages: const {'de', 'en'}, // no 'auto'
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationOk>());
    });

    test('prompt == null → ok regardless of limit', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: null,
        supportedLanguages: const {'de'},
        promptCharLimit: 0,
      );
      expect(result, isA<ValidationOk>());
    });

    test('prompt == "" → ok regardless of limit', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: '',
        supportedLanguages: const {'de'},
        promptCharLimit: 0,
      );
      expect(result, isA<ValidationOk>());
    });

    test('prompt.length == promptCharLimit → ok (boundary)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: 'x' * 100,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationOk>());
    });

    test('prompt.length == promptCharLimit + 1 → Reject(promptTooLong)', () {
      final result = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: 'x' * 101,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      expect(result, isA<ValidationReject>());
      expect(
        (result as ValidationReject).reason,
        InferenceRejectReason.promptTooLong,
      );
    });

    test('does not throw on bytes < 12 (shorter than RIFF/WAVE header)', () {
      // Should classify as invalidWav, never throw RangeError.
      for (var len = 1; len < 12; len++) {
        final bytes = Uint8List(len);
        // Even if we put 'RIFF' in there, WAVE marker is out of range.
        if (len >= 4) {
          bytes[0] = 0x52;
          bytes[1] = 0x49;
          bytes[2] = 0x46;
          bytes[3] = 0x46;
        }
        final result = InferenceRequestValidator.validate(
          wavBytes: bytes,
          language: 'de',
          prompt: null,
          supportedLanguages: const {'de'},
          promptCharLimit: 100,
        );
        expect(result, isA<ValidationReject>(), reason: 'len=$len');
        expect(
          (result as ValidationReject).reason,
          InferenceRejectReason.invalidWav,
          reason: 'len=$len',
        );
      }
    });

    test(
      'order: empty bytes AND unsupported language → Reject(empty), not unsupportedLanguage',
      () {
        final result = InferenceRequestValidator.validate(
          wavBytes: Uint8List(0),
          language: 'jp',
          prompt: null,
          supportedLanguages: const {'de', 'en'},
          promptCharLimit: 100,
        );
        expect(result, isA<ValidationReject>());
        expect(
          (result as ValidationReject).reason,
          InferenceRejectReason.empty,
        );
      },
    );

    test(
      'order: invalid WAV AND unsupported language → Reject(invalidWav)',
      () {
        final result = InferenceRequestValidator.validate(
          wavBytes: _bogusRiffButWave(),
          language: 'jp',
          prompt: null,
          supportedLanguages: const {'de'},
          promptCharLimit: 100,
        );
        expect(result, isA<ValidationReject>());
        expect(
          (result as ValidationReject).reason,
          InferenceRejectReason.invalidWav,
        );
      },
    );

    test(
      'order: unsupported language AND prompt too long → Reject(unsupportedLanguage)',
      () {
        final result = InferenceRequestValidator.validate(
          wavBytes: _validWavHeader(),
          language: 'jp',
          prompt: 'x' * 200,
          supportedLanguages: const {'de'},
          promptCharLimit: 100,
        );
        expect(result, isA<ValidationReject>());
        expect(
          (result as ValidationReject).reason,
          InferenceRejectReason.unsupportedLanguage,
        );
      },
    );

    test('InferenceRejectReason has exactly four cases', () {
      expect(InferenceRejectReason.values.length, 4);
    });

    test('ValidationOk is a singleton', () {
      final a = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'de',
        prompt: null,
        supportedLanguages: const {'de'},
        promptCharLimit: 100,
      );
      final b = InferenceRequestValidator.validate(
        wavBytes: _validWavHeader(),
        language: 'en',
        prompt: '',
        supportedLanguages: const {'en'},
        promptCharLimit: 50,
      );
      expect(a, same(b));
      expect(a, isA<ValidationOk>());
    });
  });
}
