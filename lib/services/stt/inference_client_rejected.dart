/// Exception thrown by the STT inference pipeline when the pre-flight
/// [`InferenceRequestValidator`](inference_request_validator.dart)
/// rejects a request before the multipart-POST is even attempted.
///
/// The orchestrator catches this exception, maps [userMessageKey] to a
/// localized toast via [`recording_behavior.dart`](../../widgets/recording_behavior.dart),
/// and never escalates it to Sentry — pre-flight rejects are expected
/// user-input issues, not crashes. The notifier emits a single Sentry
/// breadcrumb in category `stt` before throwing so the path is still
/// visible if a later capture happens to fire in the same session.
library;

/// Carries the validator's stable string ID up to the orchestrator.
///
/// The key (e.g. `stt.reject.empty`) is resolved to a localized toast by
/// the recording behavior widget; no toast string is materialized here.
class InferenceClientRejected implements Exception {
  const InferenceClientRejected(this.userMessageKey);

  /// Stable string ID from `InferenceRequestValidator` — exactly one of
  /// `stt.reject.empty`, `stt.reject.invalid_wav`,
  /// `stt.reject.unsupported_language`, `stt.reject.prompt_too_long`.
  final String userMessageKey;

  @override
  String toString() => 'InferenceClientRejected($userMessageKey)';
}
