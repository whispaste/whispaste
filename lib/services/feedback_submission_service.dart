/// Service that encapsulates the feedback POST to the WhisPaste API.
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
/// | [FeedbackSent] | HTTP 201 — row stored by the API |
/// | [FeedbackSkippedNotConfigured] | base URL is empty — no HTTP call made |
/// | [FeedbackRateLimitedServer] | HTTP 429 (`Retry-After`) |
/// | [FeedbackServerError] | Other non-2xx HTTP response |
/// | [FeedbackNetworkError] | Socket / timeout / other network failure |
///
/// ## Sentry telemetry
///
/// Every `submit()` emits exactly one breadcrumb with `category: "feedback"`
/// and a `result` data key. Only a critical failure, a 5xx answer, also
/// emits a Sentry `captureMessage('feedback_server_error', …)` with the HTTP
/// status code and the Problem Details fields `title`, `status` and `field`
/// (see [errorBodyForSentry]); any other body is replaced by its length, so
/// no echoed user text can reach Sentry. 4xx answers (validation), rate
/// limits and network errors stay breadcrumbs: they are user-driven and the
/// API logs them itself (#266).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/app_info.dart';
import '../core/app_urls.dart';
import '../core/logging/app_logger.dart';

// ---------------------------------------------------------------------------
// Server contract
// ---------------------------------------------------------------------------

/// Version of the consent text shown next to the quote checkbox. The server
/// accepts only allowlisted versions and stamps the consent time itself
/// (`POST /v1/feedback`). Bump it with the text.
const String kFeedbackConsentTextVersion = 'feedback-quote-v2';

/// SHA-256 (hex) of the consent text per locale, per text version: label and
/// explanation joined by a newline. Never edit an existing entry. A changed
/// consent text gets a new version, a new entry here and the new version in
/// the server allowlist (guard test in feedback_consent_text_version_test).
/// A new app language only adds its hash to the current version: no text a
/// user already saw changes (fr/it/zh in feedback-quote-v2, #1951).
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
    'fr': 'f72a82753ce2bed94a6ae0bb1f331d7b12829b675e877e00e846424182d3229e',
    'it': 'c352c795c5e060f82593418f0d80ccdd616093ddcbc03f72e6b9f23e4a2f1de3',
    'zh': '9e73d05f1933d609d98194e0c335bd65c7ad5e38ac3c26c7fddd8debf5e6142a',
  },
};

/// Secret for one consent, kept on the device. The server only stores its
/// SHA-256 (withdraw_token_hash) and can withdraw with the secret, but cannot
/// read it back.
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
  /// contact panel asks for none and sends `null` (the API accepts a missing rating).
  final int? rating;
  final String feedbackText;
  final String category;
  final String appVersion;
  final String deviceIdHash;
  final String locale;

  /// Optional, user-volunteered — only used to follow up on this specific
  /// feedback. `null` when the user left the field empty; never sent as an
  /// empty string (the API requires either NULL or a
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
// ContactPayload (POST /v1/contact)
// ---------------------------------------------------------------------------

/// The shortest message `POST /v1/contact` accepts.
const kContactMessageMinLength = 10;

/// The longest message `POST /v1/contact` accepts.
const kContactMessageMaxLength = 4000;

/// The `kind` values `POST /v1/contact` accepts.
const kContactKinds = {'problem', 'question', 'other', 'idea', 'praise'};

/// The `lang` values `POST /v1/contact` accepts; anything else is sent as
/// `en`.
const kContactLangs = {'de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr', 'he'};

/// `Platform.operatingSystem` as the contact API names it, or `null` for a
/// system it does not know (the field is optional).
String? contactOsName(String operatingSystem) => switch (operatingSystem) {
  'macos' || 'windows' || 'linux' => operatingSystem,
  _ => null,
};

/// The message the app's contact form sends. The server does not store it:
/// it goes by mail to the team inbox. Diagnostics ([appVersion], [os]) are
/// set only when the user opted in.
final class ContactPayload {
  const ContactPayload({
    required this.kind,
    required this.message,
    required this.lang,
    required this.elapsedMs,
    required this.installHash,
    this.email = '',
    this.rating,
    this.appVersion,
    this.os,
    this.diagnostics,
    this.stepId,
    this.publishConsent = false,
    this.withdrawTokenHash,
  });

  /// One of [kContactKinds].
  final String kind;
  final String message;

  /// Empty when the user wants no answer; the app source allows that.
  final String email;
  final String lang;

  /// Milliseconds since the form opened. The server treats very fast sends
  /// as bots.
  final int elapsedMs;

  /// SHA-256 (hex) of the install id. Narrows the server's rate limit to
  /// this install; never the raw id.
  final String installHash;
  final int? rating;
  final String? appVersion;
  final String? os;

  /// The opt-in diagnostics attachment (system summary and cleaned log
  /// lines, at most 64 KiB); `null` without the tick.
  final String? diagnostics;

  /// The onboarding step the panel was opened on; only with the opt-in.
  final String? stepId;

  /// Website quote opt-in, only for praise (decision 24).
  final bool publishConsent;
  final String? withdrawTokenHash;

  /// The same message without the [diagnostics] attachment.
  ContactPayload withoutDiagnostics() => ContactPayload(
    kind: kind,
    message: message,
    lang: lang,
    elapsedMs: elapsedMs,
    installHash: installHash,
    email: email,
    rating: rating,
    appVersion: appVersion,
    os: os,
    stepId: stepId,
    publishConsent: publishConsent,
    withdrawTokenHash: withdrawTokenHash,
  );

  Map<String, Object?> toJson() {
    final publish =
        publishConsent && kind == 'praise' && withdrawTokenHash != null;
    return {
      'source': 'app',
      'kind': kind,
      'message': message,
      'email': email,
      'lang': kContactLangs.contains(lang) ? lang : 'en',
      'website': '', // honeypot, always empty from the app
      'elapsed': elapsedMs,
      'install': installHash,
      'rating': rating,
      if (appVersion != null) 'appVersion': appVersion,
      if (os != null) 'os': os,
      if (diagnostics != null) 'diagnostics': diagnostics,
      if (stepId != null) 'stepId': stepId,
      if (publish) ...{
        'publish_consent': true,
        'consent_text_version': kFeedbackConsentTextVersion,
        'withdraw_token_hash': withdrawTokenHash,
      },
    };
  }
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

/// API base URL is empty — POST skipped entirely.
final class FeedbackSkippedNotConfigured extends FeedbackSubmissionResult {
  const FeedbackSkippedNotConfigured();
}

/// Server-side rate limit: HTTP 429.
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

/// Sends contact messages and feedback to the WhisPaste API
/// (`POST /v1/contact`, `POST /v1/feedback`) and withdraws quote consent at
/// both (`/v1/contact/withdraw`, `/v1/feedback/withdraw`).
///
/// Construct with the API [baseUrl] (no trailing slash, `kApiBaseUrl` in the
/// app). An empty URL makes every call return [FeedbackSkippedNotConfigured]
/// without touching the network.
final class FeedbackSubmissionService {
  FeedbackSubmissionService({
    required this._client,
    required this._baseUrl,
    this._timeout = const Duration(seconds: 15),
    BreadcrumbSinkFn? breadcrumbSink,
    MessageSinkFn? messageSink,
  }) : _breadcrumbSink = breadcrumbSink ?? _defaultBreadcrumbSink,
       _messageSink = messageSink ?? _defaultMessageSink;

  /// The service as the app builds it: talks to [kApiBaseUrl]. The caller
  /// owns [client] and closes it.
  factory FeedbackSubmissionService.fromEnvironment(http.Client client) =>
      FeedbackSubmissionService(client: client, baseUrl: kApiBaseUrl);

  static final _log = AppLogger('FeedbackSubmissionService');

  /// HTTP statuses that make a withdrawal final.
  static const _finalWithdrawalStatuses = {400, 409, 410, 422};

  /// Cap on the response body slice captured in the Sentry event. Keeps the
  /// payload small even when the server returns an HTML error page.
  static const _maxCapturedBodyChars = 500;

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;
  final BreadcrumbSinkFn _breadcrumbSink;
  final MessageSinkFn _messageSink;

  /// True when an API base URL is set.
  bool get isConfigured => _baseUrl.isNotEmpty;

  /// Withdraws the website-quote consent that belongs to [token]. Never
  /// throws. The server answers the same way whether or not a row matched.
  ///
  /// 2xx confirms. Only 400, 409, 410 and 422 are final: the request itself
  /// is wrong. Everything else (5xx, 401, 403, 404 and other 4xx, timeouts,
  /// network errors) is retried, because one systemic fault such as a
  /// rotated key or a renamed function must not end every withdrawal. Only
  /// the status code is logged, never the secret.
  ///
  /// A consent may have been given through the old feedback endpoint or the
  /// contact form, and the device does not know which, so both endpoints
  /// get the secret. Confirmed only when both confirm; a retry on either
  /// side retries both (both answer the same for unknown secrets).
  Future<WithdrawalOutcome> withdrawPublishConsent(String token) async {
    if (token.isEmpty || !isConfigured) return WithdrawalOutcome.retry;
    final contact = await _withdrawAt('/v1/contact/withdraw', {
      'withdraw_token': token,
    });
    final feedback = await _withdrawAt('/v1/feedback/withdraw', {
      'token': token,
    });
    if (contact == WithdrawalOutcome.retry ||
        feedback == WithdrawalOutcome.retry) {
      return WithdrawalOutcome.retry;
    }
    if (contact == WithdrawalOutcome.confirmed &&
        feedback == WithdrawalOutcome.confirmed) {
      return WithdrawalOutcome.confirmed;
    }
    return WithdrawalOutcome.rejected;
  }

  Future<WithdrawalOutcome> _withdrawAt(
    String path,
    Map<String, String> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': appUserAgent,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final status = response.statusCode;
      _log.info('Consent withdrawal at $path answered HTTP $status');
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
            'path': path,
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
    if (!isConfigured) {
      _log.info(
        'Feedback API not configured — skipping feedback submission '
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
            Uri.parse('$_baseUrl/v1/feedback'),
            headers: {
              'Content-Type': 'application/json',
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = errorBodyWithoutRowData(response.body);
        _log.warning('Feedback submission error: ${response.statusCode} $body');
        _emitBreadcrumb('server_error');
        // Only a 5xx (backend down or broken) is critical enough for a Sentry
        // event; a breadcrumb alone disappears with the session if the run
        // does not also crash. 4xx answers name a field the user can fix and
        // are counted in the API's own logs, so they stay breadcrumbs (#266).
        if (response.statusCode >= 500) {
          _captureMessage(
            'feedback_server_error',
            statusCode: response.statusCode,
            body: response.body,
          );
        }
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

  /// Sends [payload] to `POST /v1/contact`. Never throws.
  ///
  /// 202 means the team inbox got it. 429 is the rate limit. Every other
  /// status is a [FeedbackServerError]; 5xx is reported to Sentry (mail or
  /// store down), 4xx is not, since a 422 names one field the user can fix.
  ///
  /// A server that refuses the diagnostics attachment (413 from an API
  /// before whispaste-api 07324d5 with its 16 KiB body limit, or 422 naming
  /// `diagnostics`) gets the message once more without it, so the attachment
  /// never costs the message. An API that does not know the field ignores it.
  Future<FeedbackSubmissionResult> submitContact(ContactPayload payload) async {
    final result = await _postContact(payload);
    if (payload.diagnostics != null && _refusesDiagnostics(result)) {
      _log.info('Contact diagnostics refused, sending the message without');
      _emitBreadcrumb('diagnostics_refused', message: 'contact_submit');
      return _postContact(payload.withoutDiagnostics());
    }
    return result;
  }

  static bool _refusesDiagnostics(FeedbackSubmissionResult result) =>
      switch (result) {
        FeedbackServerError(statusCode: 413) => true,
        FeedbackServerError(statusCode: 422, :final body) =>
          _problemField(body) == 'diagnostics',
        _ => false,
      };

  static Object? _problemField(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['field'] : null;
    } on FormatException {
      return null;
    }
  }

  Future<FeedbackSubmissionResult> _postContact(ContactPayload payload) async {
    if (!isConfigured) {
      _emitBreadcrumb('skipped_not_configured', message: 'contact_submit');
      return const FeedbackSkippedNotConfigured();
    }
    _log.info('Submitting contact message: kind=${payload.kind}');
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/contact'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': appUserAgent,
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(_timeout);
      final status = response.statusCode;
      if (status == 429) {
        _emitBreadcrumb('rate_limited_server', message: 'contact_submit');
        return const FeedbackRateLimitedServer();
      }
      if (status < 200 || status >= 300) {
        final body = errorBodyWithoutRowData(response.body);
        _log.warning('Contact submission error: $status $body');
        _emitBreadcrumb('server_error', message: 'contact_submit');
        if (status >= 500) {
          _captureMessage(
            'contact_server_error',
            statusCode: status,
            body: response.body,
          );
        }
        return FeedbackServerError(status, body);
      }
      _emitBreadcrumb('sent', message: 'contact_submit');
      return const FeedbackSent();
    } on Exception catch (e) {
      _log.warning('Contact network failure: ${e.runtimeType}');
      _emitBreadcrumb('network_error', message: 'contact_submit');
      return FeedbackNetworkError(e);
    }
  }

  void _emitBreadcrumb(String result, {String message = 'feedback_submit'}) {
    _breadcrumbSink(
      Breadcrumb(
        message: message,
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
    final safe = errorBodyForSentry(body);
    final truncated = safe.length > _maxCapturedBodyChars
        ? '${safe.substring(0, _maxCapturedBodyChars)}…'
        : safe;
    _messageSink(message, SentryLevel.warning, {
      'status_code': statusCode,
      'body': truncated,
    });
  }
}

/// [body] of a failed submit without anything the user typed. The API answers
/// with Problem Details (`title`, `status`, `field`); only those are kept.
/// Other bodies (proxy or gateway pages) are kept as they are.
@visibleForTesting
String errorBodyWithoutRowData(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return body; // a proxy or gateway page, not a Problem Details body
  }
  if (decoded is Map<String, Object?>) {
    return jsonEncode({
      for (final key in const ['title', 'status', 'field'])
        if (decoded.containsKey(key)) key: decoded[key],
    });
  }
  return body;
}

/// [body] of a failed submit as it may go to Sentry: only the Problem Details
/// fields `title`, `status` and `field`. Any other body (a proxy or gateway
/// page, which could echo the request) is replaced by its length, so nothing
/// the user typed can reach Sentry (#266).
@visibleForTesting
String errorBodyForSentry(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map<String, Object?>) return errorBodyWithoutRowData(body);
  return '[body omitted: ${body.length} chars]';
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
