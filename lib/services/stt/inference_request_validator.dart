/// Pure, dependency-free pre-flight validator for inference requests.
///
/// Rejects an audio payload deterministically before it is shipped to the
/// whisper-server via Multipart-POST when the request is obviously unfit
/// for inference (empty/invalid WAV, unsupported language, prompt too
/// long). Never throws. No logger, no crash reporter, no I/O. Caller
/// resolves [ValidationReject.userMessageKey] to a localized toast.
///
/// Out of scope for this module: call-site wiring, ARB lookups, Sentry
/// fingerprinting. Pre-flight rejects stay breadcrumbs only — they are
/// expected user input issues, not crashes.
library;

import 'dart:typed_data';

/// Closed set of pre-flight reject reasons.
///
/// Each value maps to exactly one stable `userMessageKey` string ID
/// (see [ValidationReject.userMessageKey]).
enum InferenceRejectReason {
  /// `wavBytes` is empty.
  empty,

  /// `wavBytes` is non-empty but lacks the RIFF/WAVE magic bytes that
  /// every WAV file must start with (12 bytes minimum).
  invalidWav,

  /// `language` is neither `'auto'` nor a member of the supplied
  /// `supportedLanguages` set.
  unsupportedLanguage,

  /// `prompt.length` exceeds `promptCharLimit`.
  promptTooLong,
}

/// Outcome of [InferenceRequestValidator.validate].
///
/// Sealed — exactly two cases:
/// - [ValidationOk]: request is fit for transport.
/// - [ValidationReject]: request must be rejected; carries [reason] and
///   the localization key the caller should surface.
sealed class ValidationResult {
  const ValidationResult();
}

/// Singleton sentinel: the request passed all pre-flight checks.
///
/// Always the same instance — use `identical(a, b)` or `a is ValidationOk`
/// to detect.
class ValidationOk extends ValidationResult {
  const ValidationOk._();

  /// The single shared instance returned by every accepting call.
  static const ValidationOk instance = ValidationOk._();

  @override
  String toString() => 'ValidationOk';
}

/// The request was rejected.
///
/// [reason] is the structured cause; [userMessageKey] is a stable
/// string-ID (e.g. `stt.reject.empty`) the caller resolves through its
/// own localization layer — no ARB lookups happen here.
class ValidationReject extends ValidationResult {
  const ValidationReject(this.reason, this.userMessageKey);

  final InferenceRejectReason reason;
  final String userMessageKey;

  @override
  String toString() => 'ValidationReject($reason, $userMessageKey)';
}

// ---------------------------------------------------------------------------
// Stable string IDs — one per reject reason. Kept as a private table so the
// validator stays the single source of truth. Caller resolves via i18n.
// ---------------------------------------------------------------------------

const String _keyEmpty = 'stt.reject.empty';
const String _keyInvalidWav = 'stt.reject.invalid_wav';
const String _keyUnsupportedLanguage = 'stt.reject.unsupported_language';
const String _keyPromptTooLong = 'stt.reject.prompt_too_long';

// WAV RIFF/WAVE magic bytes — RFC 2361 / Microsoft RIFF spec.
//   Offset 0..3 : 'R' 'I' 'F' 'F'
//   Offset 8..11: 'W' 'A' 'V' 'E'
const int _byteR = 0x52;
const int _byteI = 0x49;
const int _byteF = 0x46;
const int _byteW = 0x57;
const int _byteA = 0x41;
const int _byteV = 0x56;
const int _byteE = 0x45;
const int _wavHeaderMinLength = 12;

/// Pure pre-flight validator. All methods are static and side-effect free.
abstract final class InferenceRequestValidator {
  /// Validates an inference request before it is shipped to the
  /// whisper-server.
  ///
  /// Reject rules (first match wins):
  /// 1. `wavBytes.isEmpty` → [InferenceRejectReason.empty].
  /// 2. Missing RIFF magic (offset 0..3) or WAVE marker (offset 8..11)
  ///    → [InferenceRejectReason.invalidWav]. Also covers payloads
  ///    shorter than 12 bytes.
  /// 3. `language != 'auto' && !supportedLanguages.contains(language)`
  ///    → [InferenceRejectReason.unsupportedLanguage].
  /// 4. `prompt != null && prompt.length > promptCharLimit`
  ///    → [InferenceRejectReason.promptTooLong].
  ///
  /// Otherwise returns [ValidationOk.instance].
  ///
  /// Never throws — even on `wavBytes.length < 12`.
  static ValidationResult validate({
    required Uint8List wavBytes,
    required String language,
    String? prompt,
    required Set<String> supportedLanguages,
    required int promptCharLimit,
  }) {
    // Rule 1: empty payload.
    if (wavBytes.isEmpty) {
      return const ValidationReject(InferenceRejectReason.empty, _keyEmpty);
    }

    // Rule 2: WAV header sanity (RIFF .... WAVE).
    if (!_hasRiffWaveHeader(wavBytes)) {
      return const ValidationReject(
        InferenceRejectReason.invalidWav,
        _keyInvalidWav,
      );
    }

    // Rule 3: language whitelist (with 'auto' bypass).
    if (language != 'auto' && !supportedLanguages.contains(language)) {
      return const ValidationReject(
        InferenceRejectReason.unsupportedLanguage,
        _keyUnsupportedLanguage,
      );
    }

    // Rule 4: prompt length cap. null and '' are always fine.
    if (prompt != null && prompt.length > promptCharLimit) {
      return const ValidationReject(
        InferenceRejectReason.promptTooLong,
        _keyPromptTooLong,
      );
    }

    return ValidationOk.instance;
  }

  /// Checks for the WAV RIFF/WAVE magic. Safe for any length, including
  /// payloads shorter than 12 bytes (returns `false`).
  static bool _hasRiffWaveHeader(Uint8List bytes) {
    if (bytes.length < _wavHeaderMinLength) return false;
    return bytes[0] == _byteR &&
        bytes[1] == _byteI &&
        bytes[2] == _byteF &&
        bytes[3] == _byteF &&
        bytes[8] == _byteW &&
        bytes[9] == _byteA &&
        bytes[10] == _byteV &&
        bytes[11] == _byteE;
  }
}
