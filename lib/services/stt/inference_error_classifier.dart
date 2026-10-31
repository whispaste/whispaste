/// Pure, dependency-free HTTP-error classifier for inference responses.
///
/// Maps a non-success HTTP response from the local `whisper-server` inference
/// endpoint into a structured [InferenceFailure] value object — with a
/// status-class [InferenceFailureKind], a stable Sentry [fingerprint] drawn
/// from the W1 inference inventory in
/// [`crash_fingerprints.dart`](../../core/logging/crash_fingerprints.dart),
/// a PII-redacted body excerpt capped at 200 chars, and the request-context
/// extras the caller passes in.
///
/// The classifier is intentionally:
/// - Pure: no I/O, no async, no closures over external state.
/// - Logger-free: it never calls `AppLogger` or `CrashReporter`. The caller
///   decides whether to surface or capture the [InferenceFailure].
/// - Total: every status code (including negative or non-HTTP values) maps
///   to a [InferenceFailure]; the function never throws.
///
/// Out of scope for this module:
/// - Call-site wiring (see Issue 04 of the W1 sprint).
/// - Pre-flight validation (see [`inference_request_validator.dart`]).
/// - Sentry capture / breadcrumb logging.
library;

import 'package:whispaste/core/logging/crash_fingerprints.dart';

/// Closed set of inference-failure status classes.
///
/// Mirrors the HTTP-status mapping documented in Issue 02 of the
/// `wartung-2026-05` sprint:
///
/// | statusCode | kind                                |
/// |------------|-------------------------------------|
/// | 400        | [clientBadRequest]                  |
/// | 413        | [payloadTooLarge]                   |
/// | 415        | [unsupportedMedia]                  |
/// | 500..599   | [serverInternal]                    |
/// | anything else | [unknown]                        |
enum InferenceFailureKind {
  /// HTTP 400 — server understood the HTTP frame but rejected the request
  /// semantically (malformed multipart, invalid prompt, bad sampling params).
  clientBadRequest,

  /// HTTP 413 — WAV payload exceeded the server's accepted upload size.
  payloadTooLarge,

  /// HTTP 415 — audio container/codec not supported by the running server
  /// build.
  unsupportedMedia,

  /// HTTP 5xx — server-side failure (model crash, OOM, internal panic). The
  /// server stayed up long enough to answer with a status, unlike the
  /// process-exit fingerprints in [sttExitOther] & co.
  serverInternal,

  /// Any other status (unexpected 4xx, 3xx, 2xx-on-error-path, negative).
  unknown,
}

/// Immutable carrier for the six request-context fields the caller mirrors
/// into [InferenceFailure.extras].
///
/// Field names match the snake_case keys placed into the extras map by
/// [InferenceErrorClassifier.classify].
class InferenceRequestContext {
  const InferenceRequestContext({
    required this.wavSizeBytes,
    required this.audioDurationMs,
    required this.language,
    required this.modelId,
    required this.promptLength,
    required this.vocabLength,
  });

  /// Size in bytes of the WAV payload that was POSTed.
  final int wavSizeBytes;

  /// Duration of the audio in milliseconds (derived client-side from the WAV
  /// header before transport).
  final int audioDurationMs;

  /// Language tag passed to the server (e.g. `'de'`, `'en'`, `'auto'`).
  final String language;

  /// Identifier of the model in use (typically the `ggml-*.bin` filename).
  final String modelId;

  /// Length in characters of the optional prompt biasing string.
  final int promptLength;

  /// Length in characters of the optional custom-vocabulary blob.
  final int vocabLength;
}

/// Immutable failure value returned by [InferenceErrorClassifier.classify].
///
/// `==` and `hashCode` compare by field — two failures with the same
/// status-class, fingerprint, redacted body, and extras are equal.
class InferenceFailure {
  const InferenceFailure({
    required this.kind,
    required this.fingerprint,
    required this.redactedBody,
    required this.extras,
  });

  /// Status class derived from the HTTP status code.
  final InferenceFailureKind kind;

  /// Sentry fingerprint constant for this failure. Drawn from the W1
  /// inference inventory in
  /// [`crash_fingerprints.dart`](../../core/logging/crash_fingerprints.dart).
  /// Never an inline string literal.
  final String fingerprint;

  /// PII-bereinigter Auszug aus dem Response-Body, gekappt auf maximal 200
  /// Zeichen. Pfad-ähnliche Tokens (Unix `/…`, Windows `C:\…`, UNC `\\…\…`)
  /// werden vor dem Truncation-Schritt durch das Literal `<path>` ersetzt.
  final String redactedBody;

  /// Spiegelung aller sechs Felder aus [InferenceRequestContext] mit
  /// snake_case-Schlüsseln. Wird vom Aufrufer als Sentry-Extras verschickt.
  final Map<String, Object?> extras;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InferenceFailure) return false;
    return kind == other.kind &&
        fingerprint == other.fingerprint &&
        redactedBody == other.redactedBody &&
        _mapEquals(extras, other.extras);
  }

  @override
  int get hashCode => Object.hash(
    kind,
    fingerprint,
    redactedBody,
    // Fold map into a single hash so equal maps hash equally regardless of
    // iteration order. Keys are a small fixed set, so this is cheap.
    Object.hashAllUnordered(
      extras.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'InferenceFailure(kind: $kind, fingerprint: $fingerprint, '
      'redactedBody: ${redactedBody.length} chars, extras: $extras)';
}

/// Pure HTTP-error classifier. All methods are static and side-effect free.
abstract final class InferenceErrorClassifier {
  /// Classifies a non-success HTTP response from `whisper-server` into a
  /// structured [InferenceFailure].
  ///
  /// - [statusCode]: HTTP status integer from the response.
  /// - [responseBody]: raw response body string (may be empty).
  /// - [context]: request-time context that is mirrored into
  ///   [InferenceFailure.extras] with snake_case keys.
  ///
  /// Mapping (first match wins):
  ///
  /// | statusCode | kind                                | fingerprint                  |
  /// |------------|-------------------------------------|------------------------------|
  /// | 400        | [InferenceFailureKind.clientBadRequest] | [inferenceBadRequest]    |
  /// | 413        | [InferenceFailureKind.payloadTooLarge]  | [inferencePayloadTooLarge] |
  /// | 415        | [InferenceFailureKind.unsupportedMedia] | [inferenceUnsupportedMedia] |
  /// | 500..599   | [InferenceFailureKind.serverInternal]   | [inferenceServerError]    |
  /// | else       | [InferenceFailureKind.unknown]          | [inferenceUnknownStatus]  |
  ///
  /// PII redaction: every path-like token in [responseBody] (Unix `/…`,
  /// Windows drive `[A-Za-z]:\…`, UNC `\\…\…`) is replaced with the literal
  /// `<path>` **before** the body is truncated to 200 characters. This
  /// guarantees that a path-bearing tail is still visible (as `<path>`) in
  /// the redacted excerpt even when the raw 200-char prefix would have cut
  /// the path off entirely.
  ///
  /// Never throws — every input produces a valid [InferenceFailure].
  static InferenceFailure classify({
    required int statusCode,
    required String responseBody,
    required InferenceRequestContext context,
  }) {
    final (kind, fingerprint) = _mapStatus(statusCode);
    final redacted = _truncate(_redactPaths(responseBody), _maxBodyChars);
    return InferenceFailure(
      kind: kind,
      fingerprint: fingerprint,
      redactedBody: redacted,
      extras: _extrasFromContext(context),
    );
  }

  static (InferenceFailureKind, String) _mapStatus(int statusCode) {
    return switch (statusCode) {
      400 => (InferenceFailureKind.clientBadRequest, inferenceBadRequest),
      413 => (InferenceFailureKind.payloadTooLarge, inferencePayloadTooLarge),
      415 => (InferenceFailureKind.unsupportedMedia, inferenceUnsupportedMedia),
      >= 500 && <= 599 => (
        InferenceFailureKind.serverInternal,
        inferenceServerError,
      ),
      _ => (InferenceFailureKind.unknown, inferenceUnknownStatus),
    };
  }

  static Map<String, Object?> _extrasFromContext(
    InferenceRequestContext context,
  ) {
    return <String, Object?>{
      'wav_size_bytes': context.wavSizeBytes,
      'audio_duration_ms': context.audioDurationMs,
      'language': context.language,
      'model_id': context.modelId,
      'prompt_length': context.promptLength,
      'vocab_length': context.vocabLength,
    };
  }

  /// Replaces path-like tokens with the literal `<path>`.
  ///
  /// Three flavours, ordered so longer alternatives match first inside the
  /// regex (alternation is left-to-right; UNC must precede the Windows
  /// drive-letter form, which must precede the Unix form to avoid partial
  /// matches consuming the wrong prefix):
  ///
  /// 1. UNC paths: `\\host\share\…` — host + at least one `\segment` group.
  /// 2. Windows drive-letter paths: `C:\Users\…`.
  /// 3. Unix absolute paths: `/usr/bin/…`.
  ///
  /// Segments use a conservative character class — alphanumerics, dot,
  /// underscore, dash — so neighbouring punctuation (closing parens, commas,
  /// quotes) does not get swallowed into the redacted token, and stray
  /// slashes inside English sentences ("and/or") do not match.
  static String _redactPaths(String body) {
    if (body.isEmpty) return body;
    return body.replaceAll(_pathPattern, _pathPlaceholder);
  }

  static String _truncate(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    return s.substring(0, maxChars);
  }

  // ---------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------

  /// Hard cap on the redacted-body excerpt length, in chars. The cap is
  /// applied after PII redaction so a path-bearing tail that would have
  /// been truncated raw still surfaces as `<path>` in the slice.
  static const int _maxBodyChars = 200;

  /// Placeholder substituted for every matched path-like token.
  static const String _pathPlaceholder = '<path>';

  /// Combined alternation. Order matters: UNC > Windows-drive > Unix so the
  /// longer prefixes (`\\host\...`) match before their shorter cousins
  /// (`\host` would otherwise never get a chance).
  ///
  /// All three flavours use the same conservative segment character class
  /// (`[A-Za-z0-9._\-]`) so neighbouring punctuation (parens, commas,
  /// quotes) is not consumed and "and/or" style false positives do not
  /// match.
  ///
  /// - UNC: `\\` + host + at least one `\segment`. Requires at least one
  ///   segment beyond the host so a stray `\\foo` literal in log output
  ///   does not match a meaningless path.
  /// - Windows drive: `[A-Za-z]:\` + zero-or-more `\segment` groups.
  /// - Unix: `/segment` + zero-or-more `/segment` groups.
  static final RegExp _pathPattern = RegExp(
    r'\\\\[A-Za-z0-9._\-]+(?:\\[A-Za-z0-9._\-]+)+'
    r'|[A-Za-z]:\\(?:[A-Za-z0-9._\-]+(?:\\[A-Za-z0-9._\-]+)*)?'
    r'|/[A-Za-z0-9._\-]+(?:/[A-Za-z0-9._\-]+)*',
  );
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
