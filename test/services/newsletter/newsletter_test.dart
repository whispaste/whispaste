/// The newsletter sign-up contract with the API: the request the app sends
/// and what each answer means for the form.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/services/newsletter/newsletter_logic.dart';
import 'package:whispaste/services/newsletter/newsletter_service.dart';

void main() {
  group('request', () {
    test('carries source app, the consent version and an empty honeypot', () {
      final body =
          jsonDecode(
                newsletterRequestBody(
                  email: '  anna@example.org ',
                  languageCode: 'de',
                  elapsedMs: 4100,
                ),
              )
              as Map<String, Object?>;
      expect(body, {
        'email': 'anna@example.org',
        'source': 'app',
        'consent': kNewsletterConsentVersion,
        'locale': 'de',
        'website': '',
        'elapsed': 4100,
      });
    });

    test('every app language is a newsletter language', () {
      for (final code in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
        expect(newsletterLocale(code), code);
      }
      expect(newsletterLocale('nl'), 'en');
    });

    test('a fast send waits for the server bar, the real time is sent', () {
      final shown = DateTime.utc(2026, 10, 31, 12);
      final fast = shown.add(const Duration(milliseconds: 800));
      expect(
        newsletterSendDelay(shownAt: shown, now: fast),
        kNewsletterMinFillIn - const Duration(milliseconds: 800),
      );
      expect(newsletterElapsedMs(shownAt: shown, now: fast), 800);
      final slow = shown.add(const Duration(seconds: 9));
      expect(newsletterSendDelay(shownAt: shown, now: slow), Duration.zero);
      expect(newsletterElapsedMs(shownAt: shown, now: slow), 9000);
      final atBar = shown.add(kNewsletterMinFillIn);
      expect(newsletterSendDelay(shownAt: shown, now: atBar), Duration.zero);
    });

    test('the first address check matches the server rules', () {
      expect(looksLikeNewsletterEmail('anna@example.org'), isTrue);
      expect(looksLikeNewsletterEmail(' anna@example.org '), isTrue);
      expect(looksLikeNewsletterEmail('anna@example'), isFalse);
      expect(looksLikeNewsletterEmail('anna example.org'), isFalse);
      expect(looksLikeNewsletterEmail('<anna>@example.org'), isFalse);
      expect(looksLikeNewsletterEmail('${'a' * 250}@example.org'), isFalse);
    });
  });

  group('privacy link', () {
    test('opens the newsletter section in the app language, else English', () {
      expect(
        newsletterPrivacyUrl('de'),
        '$kWebsiteUrl/datenschutz/#newsletter',
      );
      expect(newsletterPrivacyUrl('en'), '$kWebsiteUrl/en/privacy/#newsletter');
      for (final code in ['es', 'pt', 'ru']) {
        expect(
          newsletterPrivacyUrl(code),
          '$kWebsiteUrl/$code/privacy/#newsletter',
        );
      }
      expect(newsletterPrivacyUrl('he'), '$kWebsiteUrl/en/privacy/#newsletter');
    });
  });

  group('answer', () {
    test('202 is accepted, whatever the address state', () {
      expect(
        newsletterOutcome(202, '{"status":"accepted"}'),
        NewsletterOutcome.accepted,
      );
    });

    test('422 on the address is an address error', () {
      expect(
        newsletterOutcome(422, '{"title":"Invalid field","field":"email"}'),
        NewsletterOutcome.invalidEmail,
      );
    });

    test('422 on consent or source names the outdated app', () {
      expect(
        newsletterOutcome(422, '{"field":"consent"}'),
        NewsletterOutcome.outdatedApp,
      );
      expect(newsletterOutcome(422, 'not json'), NewsletterOutcome.unavailable);
    });

    test('429 is too many attempts, 500 is unavailable', () {
      expect(newsletterOutcome(429, '{}'), NewsletterOutcome.tooManyAttempts);
      expect(newsletterOutcome(500, '{}'), NewsletterOutcome.unavailable);
    });
  });

  group('HTTP hand-over', () {
    test('posts JSON to the subscribe address', () async {
      late http.Request sent;
      final subscriber = HttpNewsletterSubscriber(
        MockClient((request) async {
          sent = request;
          return http.Response('{"status":"accepted"}', 202);
        }),
      );
      final outcome = await subscriber.subscribe(
        email: 'anna@example.org',
        languageCode: 'he',
        elapsedMs: 3000,
      );
      expect(outcome, NewsletterOutcome.accepted);
      expect(sent.method, 'POST');
      expect(sent.url.toString(), kNewsletterSubscribeUrl);
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['email'], 'anna@example.org');
      expect(body['locale'], 'he');
    });

    test('no connection is offline', () async {
      final subscriber = HttpNewsletterSubscriber(
        MockClient((_) async => throw const SocketException('no route')),
      );
      expect(
        await subscriber.subscribe(
          email: 'anna@example.org',
          languageCode: 'de',
          elapsedMs: 3000,
        ),
        NewsletterOutcome.offline,
      );
    });
  });

  group('status secret', () {
    test('goes along with the sign-up only when there is one', () {
      Map<String, Object?> body(String? secret) =>
          jsonDecode(
                newsletterRequestBody(
                  email: 'anna@example.org',
                  languageCode: 'de',
                  elapsedMs: 4100,
                  statusSecret: secret,
                ),
              )
              as Map<String, Object?>;
      final secret = newNewsletterStatusSecret();
      expect(body(secret)['status'], secret);
      expect(body(null).containsKey('status'), isFalse);
    });

    test('is 256 bit in the shape the server accepts, new every time', () {
      final secrets = {
        for (var i = 0; i < 20; i++) newNewsletterStatusSecret(),
      };
      expect(secrets, hasLength(20));
      expect(secrets.every(isNewsletterStatusSecret), isTrue);
      expect(isNewsletterStatusSecret('too-short'), isFalse);
      expect(isNewsletterStatusSecret('${secrets.first}='), isFalse);
    });
  });

  group('status', () {
    final sentAt = DateTime.utc(2026, 11, 1, 10);
    final pending = NewsletterSignup.sent('s' * 43, sentAt);

    test('is asked only while a confirmation is pending', () {
      expect(
        shouldAskNewsletterStatus(signup: NewsletterSignup.none, now: sentAt),
        isFalse,
      );
      expect(shouldAskNewsletterStatus(signup: pending, now: sentAt), isTrue);
      expect(
        shouldAskNewsletterStatus(
          signup: pending,
          now: sentAt.add(kNewsletterConfirmWindow),
        ),
        isFalse,
      );
    });

    test('every trigger keeps the two-minute gap', () {
      final now = sentAt.add(const Duration(minutes: 5));
      expect(kNewsletterStatusGap, const Duration(minutes: 2));
      expect(
        shouldAskNewsletterStatus(
          signup: pending,
          now: now,
          lastAsked: now.subtract(const Duration(minutes: 1, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        shouldAskNewsletterStatus(
          signup: pending,
          now: now,
          lastAsked: now.subtract(kNewsletterStatusGap),
        ),
        isTrue,
      );
    });

    test('the link back asks at once after the 10 s floor only', () {
      final now = sentAt.add(const Duration(minutes: 5));
      expect(kNewsletterLinkMinGap, const Duration(seconds: 10));
      bool link(Duration since, {DateTime? retryAfterUntil}) =>
          shouldAskNewsletterStatus(
            signup: pending,
            now: now,
            lastAsked: now.subtract(since),
            retryAfterUntil: retryAfterUntil,
            immediate: true,
          );
      expect(link(const Duration(seconds: 5)), isFalse);
      expect(link(const Duration(seconds: 10)), isTrue);
      expect(link(const Duration(seconds: 30)), isTrue);
      expect(
        link(
          const Duration(seconds: 30),
          retryAfterUntil: now.add(const Duration(minutes: 1)),
        ),
        isFalse,
        reason: 'a running Retry-After wins over the link',
      );
    });

    test('a Retry-After wait holds the questions back until it has passed', () {
      final now = sentAt.add(const Duration(minutes: 5));
      final until = now.add(const Duration(minutes: 20));
      expect(
        shouldAskNewsletterStatus(
          signup: pending,
          now: now,
          retryAfterUntil: until,
        ),
        isFalse,
      );
      expect(
        shouldAskNewsletterStatus(
          signup: pending,
          now: until,
          retryAfterUntil: until,
        ),
        isTrue,
      );
    });

    test('Retry-After counts only as whole seconds', () {
      expect(newsletterRetryAfter('90'), const Duration(seconds: 90));
      expect(newsletterRetryAfter(' 0 '), Duration.zero);
      expect(newsletterRetryAfter(null), isNull);
      expect(newsletterRetryAfter('-5'), isNull);
      expect(newsletterRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
    });

    test('answers map to active, pending, refused or unknown', () {
      expect(
        newsletterStatusAnswer(200, '{"state":"active"}'),
        NewsletterStatusAnswer.active,
      );
      expect(
        newsletterStatusAnswer(200, '{"state":"pending"}'),
        NewsletterStatusAnswer.pending,
      );
      expect(
        newsletterStatusAnswer(200, '{"state":"unknown"}'),
        NewsletterStatusAnswer.lapsed,
      );
      expect(
        newsletterStatusAnswer(422, '{"field":"status"}'),
        NewsletterStatusAnswer.refused,
      );
      expect(newsletterStatusAnswer(429, ''), NewsletterStatusAnswer.limited);
      for (final (code, body) in const [
        (500, ''),
        (200, 'not json'),
        (200, '{"state":"maybe"}'),
        (200, '[]'),
      ]) {
        expect(
          newsletterStatusAnswer(code, body),
          NewsletterStatusAnswer.unknown,
          reason: '$code $body',
        );
      }
    });

    test('active keeps the day and drops the secret', () {
      final now = sentAt.add(const Duration(minutes: 3));
      expect(
        newsletterSignupAfter(pending, NewsletterStatusAnswer.active, now),
        NewsletterSignup(confirmedAt: now),
      );
    });

    test('a refused secret is dropped, an earlier confirmation stays', () {
      final before = DateTime.utc(2026, 1, 2);
      final again = NewsletterSignup(
        statusSecret: 's' * 43,
        pendingUntil: sentAt.add(kNewsletterConfirmWindow),
        confirmedAt: before,
      );
      expect(
        newsletterSignupAfter(again, NewsletterStatusAnswer.refused, sentAt),
        NewsletterSignup(confirmedAt: before),
      );
    });

    test('pending → active (once) → unknown ends with the day kept', () {
      final seen = sentAt.add(const Duration(minutes: 3));
      var signup = newsletterSignupAfter(
        pending,
        NewsletterStatusAnswer.pending,
        seen,
      );
      expect(signup, pending);
      signup = newsletterSignupAfter(
        signup,
        NewsletterStatusAnswer.active,
        seen,
      );
      expect(signup, NewsletterSignup(confirmedAt: seen));
      signup = newsletterSignupAfter(
        signup,
        NewsletterStatusAnswer.lapsed,
        seen.add(const Duration(minutes: 1)),
      );
      expect(signup, NewsletterSignup(confirmedAt: seen));
    });

    test('pending → unknown drops the secret without a confirmation', () {
      expect(
        newsletterSignupAfter(
          pending,
          NewsletterStatusAnswer.lapsed,
          sentAt.add(const Duration(hours: 1)),
        ),
        NewsletterSignup.none,
      );
    });

    test('pending and unknown change nothing until the window closes', () {
      for (final answer in const [
        NewsletterStatusAnswer.pending,
        NewsletterStatusAnswer.unknown,
      ]) {
        expect(newsletterSignupAfter(pending, answer, sentAt), pending);
        expect(
          newsletterSignupAfter(
            pending,
            answer,
            sentAt.add(kNewsletterConfirmWindow),
          ),
          NewsletterSignup.none,
        );
      }
    });
  });

  group('status HTTP hand-over', () {
    test('posts only the secret to the status address', () async {
      late http.Request sent;
      final checker = HttpNewsletterStatusChecker(
        MockClient((request) async {
          sent = request;
          return http.Response('{"state":"active"}', 200);
        }),
      );
      expect(
        (await checker.check('s' * 43)).answer,
        NewsletterStatusAnswer.active,
      );
      expect(sent.method, 'POST');
      expect(sent.url.toString(), kNewsletterStatusUrl);
      expect(jsonDecode(sent.body), {'status': 's' * 43});
    });

    test('429 keeps the Retry-After wait of the server', () async {
      final checker = HttpNewsletterStatusChecker(
        MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '1200'}),
        ),
      );
      final reply = await checker.check('s' * 43);
      expect(reply.answer, NewsletterStatusAnswer.limited);
      expect(reply.retryAfter, const Duration(minutes: 20));
    });

    test('no connection is unknown', () async {
      final checker = HttpNewsletterStatusChecker(
        MockClient((_) async => throw const SocketException('no route')),
      );
      expect(
        (await checker.check('s' * 43)).answer,
        NewsletterStatusAnswer.unknown,
      );
    });
  });
}
