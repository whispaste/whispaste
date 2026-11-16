/// Sends one newsletter sign-up, only when the user presses "Anmelden" in the
/// "Mitmachen" block. Nothing is sent on start-up, nothing is retried, and the
/// address is neither stored nor logged. Failures are expected states of the
/// form (offline, too many attempts), never crash reports.
///
/// While a sign-up waits for its confirmation, [NewsletterSignupNotifier]
/// asks the status endpoint on the triggers of [shouldAskNewsletterStatus]
/// (at most every two minutes) and keeps the result on the device (the secret, its deadline, the
/// confirmation date; never the address).
library;

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_urls.dart';
import '../../core/logging/app_logger.dart';
import 'newsletter_logic.dart';

final _log = AppLogger('Newsletter');

abstract interface class NewsletterSubscriber {
  Future<NewsletterOutcome> subscribe({
    required String email,
    required String languageCode,
    required int elapsedMs,
    String? statusSecret,
  });
}

const _headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'User-Agent': 'WhisPaste',
};

/// POST [kNewsletterSubscribeUrl] with the plain product user agent (no
/// version, no identifier) and a short timeout.
class HttpNewsletterSubscriber implements NewsletterSubscriber {
  const HttpNewsletterSubscriber(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<NewsletterOutcome> subscribe({
    required String email,
    required String languageCode,
    required int elapsedMs,
    String? statusSecret,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(kNewsletterSubscribeUrl),
            headers: _headers,
            body: newsletterRequestBody(
              email: email,
              languageCode: languageCode,
              elapsedMs: elapsedMs,
              statusSecret: statusSecret,
            ),
          )
          .timeout(timeout);
      final outcome = newsletterOutcome(response.statusCode, response.body);
      if (outcome == NewsletterOutcome.unavailable) {
        _log.info('Newsletter sign-up refused: HTTP ${response.statusCode}');
      }
      return outcome;
    } on Object catch (error) {
      // Offline, DNS, TLS or timeout. The error never contains the address.
      _log.info('Newsletter sign-up not sent: ${error.runtimeType}');
      return NewsletterOutcome.offline;
    }
  }
}

final newsletterSubscriberProvider = Provider<NewsletterSubscriber>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpNewsletterSubscriber(client);
});

abstract interface class NewsletterStatusChecker {
  Future<NewsletterStatusReply> check(String statusSecret);
}

/// POST [kNewsletterStatusUrl] with the secret. Any failure is
/// [NewsletterStatusAnswer.unknown]: an expected state, logged without the
/// secret, never a crash report.
class HttpNewsletterStatusChecker implements NewsletterStatusChecker {
  const HttpNewsletterStatusChecker(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<NewsletterStatusReply> check(String statusSecret) async {
    try {
      final response = await _client
          .post(
            Uri.parse(kNewsletterStatusUrl),
            headers: _headers,
            body: jsonEncode({'status': statusSecret}),
          )
          .timeout(timeout);
      final answer = newsletterStatusAnswer(response.statusCode, response.body);
      if (answer == NewsletterStatusAnswer.unknown ||
          answer == NewsletterStatusAnswer.limited) {
        _log.info('Newsletter status not known: HTTP ${response.statusCode}');
      }
      return NewsletterStatusReply(
        answer,
        retryAfter: newsletterRetryAfter(response.headers['retry-after']),
      );
    } on Object catch (error) {
      _log.info('Newsletter status not asked: ${error.runtimeType}');
      return const NewsletterStatusReply(NewsletterStatusAnswer.unknown);
    }
  }
}

final newsletterStatusCheckerProvider = Provider<NewsletterStatusChecker>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpNewsletterStatusChecker(client);
});

/// Prefs keys of [NewsletterSignup]. The secret is a short-lived, single-use
/// value that only reveals whether this device's own sign-up was confirmed,
/// so it sits in the preferences, not in the credential store.
const kNewsletterStatusSecretKey = 'newsletter_status_secret';
const kNewsletterPendingUntilKey = 'newsletter_pending_until';
const kNewsletterConfirmedAtKey = 'newsletter_confirmed_at';

/// The device's newsletter sign-up, kept in the preferences. [ask] is the
/// one place that talks to the status endpoint.
class NewsletterSignupNotifier extends AsyncNotifier<NewsletterSignup> {
  DateTime? _lastAsked;
  DateTime? _retryAfterUntil;
  Future<void>? _asking;

  @override
  Future<NewsletterSignup> build() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? at(String key) {
      final ms = prefs.getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    final secret = prefs.getString(kNewsletterStatusSecretKey);
    final stored = NewsletterSignup(
      statusSecret: secret != null && isNewsletterStatusSecret(secret)
          ? secret
          : null,
      pendingUntil: at(kNewsletterPendingUntilKey),
      confirmedAt: at(kNewsletterConfirmedAtKey),
    );
    final current = stored.expiredAt(clock.now());
    if (current != stored) await _save(current);
    return current;
  }

  /// A sign-up with [statusSecret] was accepted just now.
  Future<void> sent(String statusSecret) async {
    final signup = NewsletterSignup.sent(statusSecret, clock.now());
    _lastAsked = null;
    _retryAfterUntil = null;
    await _save(signup);
    state = AsyncData(signup);
  }

  /// Asks the server whether the pending sign-up was confirmed, if the rules
  /// allow it now (see [shouldAskNewsletterStatus]). [immediate]: the link back
  /// from the confirmation page. Concurrent triggers (focus and the link back
  /// arrive together) share one question.
  ///
  /// Never throws: the card and the link back call it unawaited, so a failed
  /// prefs read or write is logged instead of becoming an unhandled error
  /// (F17-5). The status stays as it was and the next trigger asks again.
  Future<void> ask({bool immediate = false}) {
    final running = _asking;
    if (running != null) return running;
    final question = _ask(immediate)
        .catchError((Object error) {
          _log.info('Newsletter status not updated: ${error.runtimeType}');
        })
        .whenComplete(() => _asking = null);
    _asking = question;
    return question;
  }

  Future<void> _ask(bool immediate) async {
    final signup = await future;
    final now = clock.now();
    if (!shouldAskNewsletterStatus(
      signup: signup,
      now: now,
      lastAsked: _lastAsked,
      retryAfterUntil: _retryAfterUntil,
      immediate: immediate,
    )) {
      final expired = signup.expiredAt(now);
      if (expired != signup) await _apply(expired);
      return;
    }
    _lastAsked = now;
    final reply = await ref
        .read(newsletterStatusCheckerProvider)
        .check(signup.statusSecret!);
    final answeredAt = clock.now();
    // A sign-up sent while the question was out replaces this one. Its answer
    // is about the old secret: it must neither confirm nor hold back the new
    // sign-up.
    final base = state.value;
    if (base == null || base.statusSecret != signup.statusSecret) return;
    final retryAfter = reply.retryAfter;
    _retryAfterUntil = retryAfter == null ? null : answeredAt.add(retryAfter);
    await _apply(newsletterSignupAfter(base, reply.answer, answeredAt));
  }

  Future<void> _apply(NewsletterSignup signup) async {
    if (signup == state.value) return;
    await _save(signup);
    state = AsyncData(signup);
  }

  static Future<void> _save(NewsletterSignup signup) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> put(String key, Object? value) => switch (value) {
      null => prefs.remove(key),
      final String text => prefs.setString(key, text),
      final DateTime time => prefs.setInt(key, time.millisecondsSinceEpoch),
      _ => throw ArgumentError.value(value, key),
    };
    await put(kNewsletterStatusSecretKey, signup.statusSecret);
    await put(kNewsletterPendingUntilKey, signup.pendingUntil);
    await put(kNewsletterConfirmedAtKey, signup.confirmedAt);
  }
}

final newsletterSignupProvider =
    AsyncNotifierProvider<NewsletterSignupNotifier, NewsletterSignup>(
      NewsletterSignupNotifier.new,
    );
