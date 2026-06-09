/// Service that encapsulates the Supabase feedback POST.
///
/// Extracted from [FeedbackPage] so the result variants are explicit and
/// testable without touching the widget tree.  The service is intentionally
/// stateless — rate-limit storage lives in [SharedPreferences] and is managed
/// by the caller.
///
/// ## Result variants
///
/// | Variant | Meaning |
/// |---|---|
/// | [FeedbackSent] | HTTP 2xx — row written to Supabase |
/// | [FeedbackSkippedNotConfigured] | URL or key is empty — no HTTP call made |
/// | [FeedbackRateLimitedServer] | HTTP 429 or DB trigger 400 `rate_limited` |
/// | [FeedbackServerError] | Other non-2xx HTTP response |
/// | [FeedbackNetworkError] | Socket / timeout / other network failure |
///
/// ## Sentry telemetry
///
/// Every `submit()` emits exactly one breadcrumb with `category: "feedback"`
/// and a `result` data key. In addition, a [FeedbackServerError] result also
/// emits a Sentry `captureMessage('feedback_server_error', …)` with the HTTP
/// status code and a truncated response body so backend schema drift surfaces
/// within hours instead of weeks. Rate-limit and network errors are not
/// escalated — those are user-driven and expected. No PII is included.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// FeedbackPayload
// ---------------------------------------------------------------------------

/// Immutable data object passed to [FeedbackSubmissionService.submit].
final class FeedbackPayload {
  const FeedbackPayload({
    required this.rating,
    required this.feedbackText,
    required this.category,
    required this.appVersion,
    required this.deviceIdHash,
    required this.locale,
  });

  final int rating;
  final String feedbackText;
  final String category;
  final String appVersion;
  final String deviceIdHash;
  final String locale;

  Map<String, Object?> toJson() => {
    'rating': rating,
    'feedback_text': feedbackText,
    'category': category,
    'app_version': appVersion,
    'device_id_hash': deviceIdHash,
    'locale': locale,
  };
}

// ---------------------------------------------------------------------------
// FeedbackSubmissionResult — sealed ADT
// ---------------------------------------------------------------------------

/// The outcome of a [FeedbackSubmissionService.submit] call.
sealed class FeedbackSubmissionResult {
  const FeedbackSubmissionResult();
}

/// HTTP 2xx — row written successfully.
final class FeedbackSent extends FeedbackSubmissionResult {
  const FeedbackSent();
}

/// Supabase URL or publishable key is empty — POST skipped entirely.
final class FeedbackSkippedNotConfigured extends FeedbackSubmissionResult {
  const FeedbackSkippedNotConfigured();
}

/// Server-side rate limit: HTTP 429 or DB trigger 400 `rate_limited`.
final class FeedbackRateLimitedServer extends FeedbackSubmissionResult {
  const FeedbackRateLimitedServer();
}

/// Non-2xx HTTP response that is not a rate-limit.
final class FeedbackServerError extends FeedbackSubmissionResult {
  const FeedbackServerError(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// Socket exception, timeout, or other network-level failure.
final class FeedbackNetworkError extends FeedbackSubmissionResult {
  const FeedbackNetworkError(this.cause);
  final Object cause;
}

// ---------------------------------------------------------------------------
// FeedbackSubmissionService
// ---------------------------------------------------------------------------

/// Sends feedback payloads to Supabase PostgREST.
///
/// Construct with the Supabase [supabaseUrl] and [supabasePublishableKey]
/// injected at build time. An empty URL or key makes every call return
/// [FeedbackSkippedNotConfigured] without touching the network.
final class FeedbackSubmissionService {
  FeedbackSubmissionService({
    required this._client,
    required this._supabaseUrl,
    required this._supabasePublishableKey,
    this._timeout = const Duration(seconds: 15),
    BreadcrumbSinkFn? breadcrumbSink,
    MessageSinkFn? messageSink,
  }) : _breadcrumbSink = breadcrumbSink ?? _defaultBreadcrumbSink,
       _messageSink = messageSink ?? _defaultMessageSink;

  static final _log = AppLogger('FeedbackSubmissionService');

  /// Cap on the response body slice captured in the Sentry event. Keeps the
  /// payload small even when the server returns an HTML error page.
  static const _maxCapturedBodyChars = 500;

  final http.Client _client;
  final String _supabaseUrl;
  final String _supabasePublishableKey;
  final Duration _timeout;
  final BreadcrumbSinkFn _breadcrumbSink;
  final MessageSinkFn _messageSink;

  /// Submits [payload] and returns a [FeedbackSubmissionResult].
  ///
  /// Never throws; all errors are captured in the sealed result type.
  Future<FeedbackSubmissionResult> submit(FeedbackPayload payload) async {
    if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
      _log.info(
        'Supabase not configured — skipping feedback submission '
        '(rating=${payload.rating} category=${payload.category})',
      );
      _emitBreadcrumb('skipped_not_configured');
      return const FeedbackSkippedNotConfigured();
    }

    _log.info(
      'Submitting feedback: rating=${payload.rating} '
      'category=${payload.category} locale=${payload.locale}',
    );

    try {
      final response = await _client
          .post(
            Uri.parse('$_supabaseUrl/rest/v1/user_feedback'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': _supabasePublishableKey,
              'Authorization': 'Bearer $_supabasePublishableKey',
              'Prefer': 'return=minimal',
              'User-Agent': appUserAgent,
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(_timeout);

      if (response.statusCode == 429) {
        _log.info('Feedback rate-limited (429)');
        _emitBreadcrumb('rate_limited_server');
        return const FeedbackRateLimitedServer();
      }
      if (response.statusCode == 400 &&
          response.body.contains('rate_limited')) {
        _log.info('Feedback rate-limited by DB trigger');
        _emitBreadcrumb('rate_limited_server');
        return const FeedbackRateLimitedServer();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log.warning(
          'Feedback submission error: ${response.statusCode} ${response.body}',
        );
        _emitBreadcrumb('server_error');
        // Escalate to a Sentry event so a broken backend (schema drift, RLS
        // misconfig, missing column) surfaces within hours instead of weeks.
        // A breadcrumb alone disappears with the session if the run does not
        // also crash. Rate-limit and network errors are deliberately excluded:
        // they are expected, user-driven failure modes and would only add
        // noise to the Sentry inbox.
        _captureMessage(
          'feedback_server_error',
          statusCode: response.statusCode,
          body: response.body,
        );
        return FeedbackServerError(response.statusCode, response.body);
      }

      _log.info('Feedback submitted successfully');
      _emitBreadcrumb('sent');
      return const FeedbackSent();
    } on Exception catch (e) {
      _log.warning('Feedback network failure: $e');
      _emitBreadcrumb('network_error');
      return FeedbackNetworkError(e);
    }
  }

  void _emitBreadcrumb(String result) {
    _breadcrumbSink(
      Breadcrumb(
        message: 'feedback_submit',
        category: 'feedback',
        level: SentryLevel.info,
        data: {'result': result},
      ),
    );
  }

  void _captureMessage(
    String message, {
    required int statusCode,
    required String body,
  }) {
    final truncated = body.length > _maxCapturedBodyChars
        ? '${body.substring(0, _maxCapturedBodyChars)}…'
        : body;
    _messageSink(message, SentryLevel.warning, {
      'status_code': statusCode,
      'body': truncated,
    });
  }
}

// ---------------------------------------------------------------------------
// Sentry sinks — injectable in tests
// ---------------------------------------------------------------------------

typedef BreadcrumbSinkFn = void Function(Breadcrumb breadcrumb);

typedef MessageSinkFn =
    void Function(
      String message,
      SentryLevel level,
      Map<String, Object?> extras,
    );

void _defaultBreadcrumbSink(Breadcrumb breadcrumb) =>
    Sentry.addBreadcrumb(breadcrumb);

void _defaultMessageSink(
  String message,
  SentryLevel level,
  Map<String, Object?> extras,
) {
  Sentry.captureMessage(
    message,
    level: level,
    withScope: (scope) {
      // Use Contexts instead of the deprecated setExtra API. A single
      // structured context key keeps the response details grouped together
      // in the Sentry issue UI.
      scope.setContexts('feedback_response', extras);
    },
  );
}
