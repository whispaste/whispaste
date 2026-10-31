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
/// | [FeedbackRateLimitedServer] | HTTP 429 or a DB trigger 400 with a code from [feedbackRateLimitCodes] |
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
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Server contract
// ---------------------------------------------------------------------------

/// The longest `feedback_text` the anon insert policy accepts.
const kFeedbackTextMaxLength = 1000;

/// Version of the consent text shown next to the quote checkbox. The server
/// accepts only allowlisted versions and stamps the consent time itself
/// (migrations 20261020100000 and 20261020120000). Bump it with the text.
const String kFeedbackConsentTextVersion = 'feedback-quote-v2';

/// SHA-256 (hex) of the consent text per locale, per text version: label and
/// explanation joined by a newline. Never edit an existing entry. A changed
/// consent text gets a new version, a new entry here and the new version in
/// the server allowlist (guard test in feedback_consent_text_version_test).
const Map<String, Map<String, String>> kFeedbackConsentTextHashes = {
  'feedback-quote-v1': {
    'de': 'd1d22cc59d894df88ef99dbe59762c1d7d09dd719d9b84c601fad82e741d5bb5',
    'en': 'b2ace2ac775ac9023243fe862edf7387de7fc744aa58caf7d185de5bc3b284fb',
    'es': '2af78ad2c629f7c8b828f88df7744a0596a51a429bbe508df70e887848e9fe28',
    'he': '7445c43bc9395e2985ffb9081f1f0f9e29ad31751339f7708d75e3ef232f20a3',
    'pt': '9f2e107408e42b8f28e967fdf83f2a641b14c294106e6fec32b0bf5396709cb6',
    'ru': 'c251bd7dbb9bd9d8fde67896c6d6522801d592d860c310ee1f2afbc6d044e7d3',
  },
  'feedback-quote-v2': {
    'de': '9c56e8eac34585a8d0f36ab645db390d1049b2f72ecfab19689017afcc61a01f',
    'en': 'cd0ebcc4d40665101909f6782a25ee8478a934074bab6bce1ea050775bc1ef9b',
    'es': '24a3813fc4815558cd865461678c2c38fa8a0ecf54e9b5d8c1850fb68c139864',
    'he': '068180d1bc015ab88d0ebd946ac7d304eb793dadced035f79eac78c1ee6174ea',
    'pt': '7b29be82f25975c775ece4c469afc7b57d0be07fb36c57ea0a9eb08b1042b053',
    'ru': '11aca92a26b2f0e099aec437b410f08c9bc518dbe32a69f33cd5d76d584ec80d',
  },
};

/// Secret for one consent, kept on the device. The server only stores its
/// SHA-256 (withdraw_token_hash) and can withdraw with the secret, but cannot
/// read it back: anon has no SELECT on user_feedback.
String newConsentToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Lowercase hex SHA-256 of [token], as stored in withdraw_token_hash.
String consentTokenHash(String token) =>
    sha256.convert(utf8.encode(token)).toString();

// ---------------------------------------------------------------------------
// FeedbackPayload
// ---------------------------------------------------------------------------

/// Immutable data object passed to [FeedbackSubmissionService.submit].
final class FeedbackPayload {
  const FeedbackPayload({
    this.rating,
    required this.feedbackText,
    required this.category,
    required this.appVersion,
    required this.deviceIdHash,
    required this.locale,
    this.contactEmail,
    this.contactLocale,
    this.publishConsent = false,
    this.withdrawTokenHash,
  });

  /// The star rating, 1 to 5. The feedback form requires it; the onboarding
  /// contact panel asks for none and sends `null` (server accepts NULL since
  /// 20261025120000_feedback_rating_optional).
  final int? rating;
  final String feedbackText;
  final String category;
  final String appVersion;
  final String deviceIdHash;
  final String locale;

  /// Optional, user-volunteered — only used to follow up on this specific
  /// feedback. `null` when the user left the field empty; never sent as an
  /// empty string (the server CHECK constraint requires either NULL or a
  /// valid-looking address).
  final String? contactEmail;

  /// Optional language the user prefers to be contacted in (e.g. `'de'`),
  /// distinct from [locale] (the app UI language at submit time).
  final String? contactLocale;

  /// Explicit opt-in to show this text anonymously as a website quote.
  /// Defaults to `false`; the server shows nothing without it.
  final bool publishConsent;

  /// SHA-256 of the consent secret (see [newConsentToken]). Sent only with
  /// [publishConsent]; the secret itself never leaves the device.
  final String? withdrawTokenHash;

  Map<String, Object?> toJson() => {
    'rating': rating,
    'feedback_text': feedbackText,
    'category': category,
    'app_version': appVersion,
    'device_id_hash': deviceIdHash,
    'locale': locale,
    if (contactEmail != null) 'contact_email': contactEmail,
    if (contactLocale != null) 'contact_locale': contactLocale,
    'publish_consent': publishConsent,
    if (publishConsent) 'consent_text_version': kFeedbackConsentTextVersion,
    if (publishConsent && withdrawTokenHash != null)
      'withdraw_token_hash': withdrawTokenHash,
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

/// Server-side rate limit: HTTP 429 or a DB trigger 400 whose message is one
/// of [feedbackRateLimitCodes].
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

/// Supabase URL — injected at build time via `--dart-define`.
const _envSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);

/// Supabase publishable key — injected at build time via `--dart-define`.
/// Public key (replaces legacy anon key), safe for client-side use.
/// RLS enforces all access control server-side.
const _envSupabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

/// Result of one withdrawal request.
enum WithdrawalOutcome {
  /// The server answered 2xx.
  confirmed,

  /// Offline, timed out, 5xx or any other 4xx: try again later.
  retry,

  /// 400, 409, 410 or 422: final, retrying cannot help.
  rejected,
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

  /// The service as the app builds it: configured by `--dart-define`. The
  /// caller owns [client] and closes it.
  factory FeedbackSubmissionService.fromEnvironment(http.Client client) =>
      FeedbackSubmissionService(
        client: client,
        supabaseUrl: _envSupabaseUrl,
        supabasePublishableKey: _envSupabasePublishableKey,
      );

  static final _log = AppLogger('FeedbackSubmissionService');

  /// HTTP statuses that make a withdrawal final.
  static const _finalWithdrawalStatuses = {400, 409, 410, 422};

  /// Cap on the response body slice captured in the Sentry event. Keeps the
  /// payload small even when the server returns an HTML error page.
  static const _maxCapturedBodyChars = 500;

  final http.Client _client;
  final String _supabaseUrl;
  final String _supabasePublishableKey;
  final Duration _timeout;
  final BreadcrumbSinkFn _breadcrumbSink;
  final MessageSinkFn _messageSink;

  /// True when a backend URL and key were injected at build time.
  bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty;

  /// Withdraws the website-quote consent that belongs to [token]. Never
  /// throws. The server answers the same way whether or not a row matched.
  ///
  /// 2xx confirms. Only 400, 409, 410 and 422 are final: the request itself
  /// is wrong. Everything else (5xx, 401, 403, 404 and other 4xx, timeouts,
  /// network errors) is retried, because one systemic fault such as a
  /// rotated key or a renamed function must not end every withdrawal. Only
  /// the status code is logged, never the secret.
  Future<WithdrawalOutcome> withdrawPublishConsent(String token) async {
    if (token.isEmpty || !isConfigured) return WithdrawalOutcome.retry;
    try {
      final response = await _client
          .post(
            Uri.parse(
              '$_supabaseUrl/rest/v1/rpc/withdraw_feedback_publish_consent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'apikey': _supabasePublishableKey,
              'Authorization': 'Bearer $_supabasePublishableKey',
              'User-Agent': appUserAgent,
            },
            body: jsonEncode({'p_token': token}),
          )
          .timeout(_timeout);
      final status = response.statusCode;
      _log.info('Consent withdrawal answered HTTP $status');
      if (status >= 200 && status < 300) return WithdrawalOutcome.confirmed;
      final outcome = _finalWithdrawalStatuses.contains(status)
          ? WithdrawalOutcome.rejected
          : WithdrawalOutcome.retry;
      _breadcrumbSink(
        Breadcrumb(
          message: 'feedback_withdraw',
          category: 'feedback',
          level: SentryLevel.warning,
          data: {
            'result': outcome == WithdrawalOutcome.rejected
                ? 'rejected'
                : 'retry',
            'status': status,
          },
        ),
      );
      return outcome;
    } on Object catch (e) {
      _log.warning('Consent withdrawal failed: ${e.runtimeType}');
      return WithdrawalOutcome.retry;
    }
  }

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
      if (response.statusCode == 400 && isRateLimitBody(response.body)) {
        _log.info('Feedback rate-limited by DB trigger');
        _emitBreadcrumb('rate_limited_server');
        return const FeedbackRateLimitedServer();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = errorBodyWithoutRowData(response.body);
        _log.warning('Feedback submission error: ${response.statusCode} $body');
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
          body: body,
        );
        return FeedbackServerError(response.statusCode, body);
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

/// Error codes the feedback triggers raise when a rate limit is hit.
///
/// `rate_limited` is the original per-device trigger; the hardened triggers
/// raise `ip_rate_limit_exceeded` and `device_rate_limit_exceeded`
/// (migration 20260421_fix_security_advisor_findings.sql).
const feedbackRateLimitCodes = {
  'rate_limited',
  'ip_rate_limit_exceeded',
  'device_rate_limit_exceeded',
};

/// Whether a PostgREST error [body] carries one of [feedbackRateLimitCodes].
///
/// Matches the code exactly, not as a substring: the message is either the
/// bare code or the code followed by `:` and a human-readable reason.
@visibleForTesting
bool isRateLimitBody(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return false;
  }
  if (decoded is! Map<String, dynamic>) return false;
  final message = decoded['message'];
  if (message is! String) return false;
  final code = message.split(':').first.trim();
  return feedbackRateLimitCodes.contains(code);
}

/// [body] of a failed insert without the submitted values. A PostgREST
/// error carries the rejected row in `details`
/// (`Failing row contains (…, <feedback text>, <email>)`) and sometimes in
/// `hint`; only `code` and
/// `message` name the cause. Other bodies (proxy or gateway pages) are kept.
@visibleForTesting
String errorBodyWithoutRowData(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return body; // a proxy or gateway page, not a PostgREST error
  }
  if (decoded is Map<String, Object?> && decoded.containsKey('code')) {
    return jsonEncode({'code': decoded['code'], 'message': decoded['message']});
  }
  return body;
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

/// The app-wide feedback service with one shared HTTP client, closed when
/// the provider container is disposed.
final feedbackSubmissionServiceProvider = Provider<FeedbackSubmissionService>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return FeedbackSubmissionService.fromEnvironment(client);
});
