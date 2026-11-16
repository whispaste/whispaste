/// Pure rules of the newsletter sign-up in the "Mitmachen" block: what the
/// app sends to `POST /v1/newsletter/subscribe` and what each answer means
/// for the form. The address only lives in the request; the app never
/// stores it.
///
/// After the double opt-in the app learns once whether the sign-up was
/// confirmed: it sends a random status secret with the sign-up and later
/// asks `POST /v1/newsletter/status` with it, only while a confirmation is
/// pending and only on the triggers in [shouldAskNewsletterStatus]. The
/// server reports `active` exactly once and never for an address that was
/// already on the list; afterwards (and once the link ran out) it says
/// `unknown`.
library;

import 'dart:convert';
import 'dart:math';

/// The consent wording the app shows (`newsletterConsent` in the ARB files)
/// belongs to this version. The server refuses any other value; a new
/// wording comes with a new version from the API, never edited in place.
const String kNewsletterConsentVersion = 'newsletter-2026-10-31';

/// The server counts a form sent faster than this as automated and drops it
/// silently, so the app waits until it has passed before it sends (see
/// [newsletterSendDelay]).
const Duration kNewsletterMinFillIn = Duration(milliseconds: 2500);

/// The languages the newsletter is written in. Every app language is one of
/// them; anything else would be stored as English by the server anyway.
const Set<String> kNewsletterLocales = {
  'de',
  'en',
  'es',
  'pt',
  'it',
  'ru',
  'zh',
  'fr',
  'he',
};

final _emailFormat = RegExp(r'^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$');

/// A first check before anything is sent; the server has the final word.
bool looksLikeNewsletterEmail(String value) {
  final email = value.trim();
  return email.length <= 254 && _emailFormat.hasMatch(email);
}

/// The newsletter language for the app's [languageCode].
String newsletterLocale(String languageCode) =>
    kNewsletterLocales.contains(languageCode) ? languageCode : 'en';

/// How long to wait before sending so the form has been shown for at least
/// [kNewsletterMinFillIn]: a person who pastes an address and sends at once
/// would otherwise get the confirmation screen but no mail. The app waits
/// instead of reporting a longer time than really passed (GR-055).
Duration newsletterSendDelay({
  required DateTime shownAt,
  required DateTime now,
}) {
  final left = kNewsletterMinFillIn - now.difference(shownAt);
  return left.isNegative ? Duration.zero : left;
}

/// Milliseconds between showing the form and sending it, as they passed.
int newsletterElapsedMs({required DateTime shownAt, required DateTime now}) =>
    now.difference(shownAt).inMilliseconds;

/// The JSON body of one sign-up. The honeypot is always empty.
String newsletterRequestBody({
  required String email,
  required String languageCode,
  required int elapsedMs,
  String? statusSecret,
}) => jsonEncode({
  'email': email.trim(),
  'source': 'app',
  'consent': kNewsletterConsentVersion,
  'locale': newsletterLocale(languageCode),
  'website': '',
  'elapsed': elapsedMs,
  'status': ?statusSecret,
});

/// What the form shows after one attempt.
enum NewsletterOutcome {
  /// 202: the confirmation mail is on its way (or the address is already
  /// on the list; the server never tells which).
  accepted,

  /// 422 on the address: the server does not take it.
  invalidEmail,

  /// 429: too many attempts for now.
  tooManyAttempts,

  /// No answer: no network, a timeout or a broken connection.
  offline,

  /// 422 on anything but the address (a refused consent version, source or
  /// language): only an outdated app sends this, so the cause is the app and
  /// the next step is an update.
  outdatedApp,

  /// Any other answer: the server cannot take sign-ups right now.
  unavailable,
}

/// Maps the server's answer to what the form shows.
NewsletterOutcome newsletterOutcome(int statusCode, String body) {
  if (statusCode == 202) return NewsletterOutcome.accepted;
  if (statusCode == 429) return NewsletterOutcome.tooManyAttempts;
  if (statusCode == 422) {
    final field = _problemField(body);
    if (field == 'email') return NewsletterOutcome.invalidEmail;
    if (field != null) return NewsletterOutcome.outdatedApp;
  }
  return NewsletterOutcome.unavailable;
}

String? _problemField(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, Object?> && decoded['field'] is String
        ? decoded['field']! as String
        : null;
  } on FormatException {
    return null;
  }
}

/// How long the server keeps a confirmation link (and the status secret
/// sent with it) valid. Afterwards the app forgets the secret and offers the
/// form again.
const Duration kNewsletterConfirmWindow = Duration(hours: 48);

/// The shortest gap between two status questions, whatever the trigger. The
/// server allows 30 questions an hour per secret; a 429 with Retry-After
/// holds the app back for longer (see [shouldAskNewsletterStatus]).
const Duration kNewsletterStatusGap = Duration(minutes: 2);

/// The link back from the confirmation page asks at once, the user waits for
/// the answer. Only this floor applies to it, so a double click or two links
/// do not ask twice.
const Duration kNewsletterLinkMinGap = Duration(seconds: 10);

final _statusSecretFormat = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// A fresh status secret: 256 random bits, base64url without padding
/// (43 characters, the shape the server accepts).
String newNewsletterStatusSecret([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Whether [value] has the shape of a status secret.
bool isNewsletterStatusSecret(String value) =>
    _statusSecretFormat.hasMatch(value);

/// What the device remembers of its newsletter sign-up: a pending one (the
/// secret and until when its confirmation link is valid) or the day it was
/// confirmed. Never the address.
final class NewsletterSignup {
  const NewsletterSignup({
    this.statusSecret,
    this.pendingUntil,
    this.confirmedAt,
  });

  static const none = NewsletterSignup();

  final String? statusSecret;
  final DateTime? pendingUntil;
  final DateTime? confirmedAt;

  /// A sign-up whose confirmation link may still be clicked at [now].
  bool isPending(DateTime now) =>
      statusSecret != null &&
      pendingUntil != null &&
      now.isBefore(pendingUntil!);

  /// A new sign-up was accepted at [now]: it replaces whatever was known.
  static NewsletterSignup sent(String statusSecret, DateTime now) =>
      NewsletterSignup(
        statusSecret: statusSecret,
        pendingUntil: now.add(kNewsletterConfirmWindow),
      );

  /// What is left once [now] is past the confirmation window: the secret is
  /// dropped, a confirmation date stays.
  NewsletterSignup expiredAt(DateTime now) =>
      statusSecret != null && !isPending(now)
      ? NewsletterSignup(confirmedAt: confirmedAt)
      : this;

  @override
  bool operator ==(Object other) =>
      other is NewsletterSignup &&
      other.statusSecret == statusSecret &&
      other.pendingUntil == pendingUntil &&
      other.confirmedAt == confirmedAt;

  @override
  int get hashCode => Object.hash(statusSecret, pendingUntil, confirmedAt);
}

/// Whether to ask the server now. Only while a confirmation is pending and
/// never before [retryAfterUntil] (a 429 with Retry-After, which wins over
/// everything else). Window focus and the card showing ask at most once per
/// [kNewsletterStatusGap]; [immediate] (the link back from the confirmation
/// page) asks at once, but at least [kNewsletterLinkMinGap] after the last
/// question. There is no timer: without one of the triggers the app never asks.
bool shouldAskNewsletterStatus({
  required NewsletterSignup signup,
  required DateTime now,
  DateTime? lastAsked,
  DateTime? retryAfterUntil,
  bool immediate = false,
}) {
  if (!signup.isPending(now)) return false;
  if (retryAfterUntil != null && now.isBefore(retryAfterUntil)) return false;
  if (lastAsked == null) return true;
  final elapsed = now.difference(lastAsked);
  return elapsed >= (immediate ? kNewsletterLinkMinGap : kNewsletterStatusGap);
}

/// The server's answer to one status question.
enum NewsletterStatusAnswer {
  /// Confirmed. Reported once; the server forgets the secret with it.
  active,

  /// Not confirmed yet, or unknown to the server.
  pending,

  /// The server no longer knows the secret (`state: unknown`): the link ran
  /// out, or the one-time `active` was already reported. Not an error: the
  /// app drops the secret and says so calmly.
  lapsed,

  /// The server refuses the secret's shape: it can never become active.
  refused,

  /// Too many questions for now (429): wait, no error.
  limited,

  /// No usable answer (offline, server error): ask again later.
  unknown,
}

/// One answer of the status endpoint, with the Retry-After wait of a 429.
final class NewsletterStatusReply {
  const NewsletterStatusReply(this.answer, {this.retryAfter});

  final NewsletterStatusAnswer answer;
  final Duration? retryAfter;
}

/// Retry-After in seconds, the only form the server sends. Anything else
/// (a date, a negative or broken value) counts as absent.
Duration? newsletterRetryAfter(String? header) {
  final seconds = int.tryParse(header?.trim() ?? '');
  return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
}

/// Maps the status endpoint's answer.
NewsletterStatusAnswer newsletterStatusAnswer(int statusCode, String body) {
  if (statusCode == 422) return NewsletterStatusAnswer.refused;
  if (statusCode == 429) return NewsletterStatusAnswer.limited;
  if (statusCode != 200) return NewsletterStatusAnswer.unknown;
  try {
    final decoded = jsonDecode(body);
    final state = decoded is Map<String, Object?> ? decoded['state'] : null;
    return switch (state) {
      'active' => NewsletterStatusAnswer.active,
      'pending' => NewsletterStatusAnswer.pending,
      'unknown' => NewsletterStatusAnswer.lapsed,
      _ => NewsletterStatusAnswer.unknown,
    };
  } on FormatException {
    return NewsletterStatusAnswer.unknown;
  }
}

/// The sign-up after [answer] arrived at [now].
NewsletterSignup newsletterSignupAfter(
  NewsletterSignup signup,
  NewsletterStatusAnswer answer,
  DateTime now,
) => switch (answer) {
  NewsletterStatusAnswer.active => NewsletterSignup(confirmedAt: now),
  NewsletterStatusAnswer.refused || NewsletterStatusAnswer.lapsed =>
    NewsletterSignup(confirmedAt: signup.confirmedAt),
  NewsletterStatusAnswer.pending ||
  NewsletterStatusAnswer.limited ||
  NewsletterStatusAnswer.unknown => signup.expiredAt(now),
};
