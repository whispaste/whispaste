/// The device's newsletter sign-up as the app keeps it: when the status
/// endpoint is asked, how a 429 holds it back, and what an active answer
/// leaves behind. Time comes from an injected clock, never from waiting.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/services/newsletter/newsletter_logic.dart';
import 'package:whispaste/services/newsletter/newsletter_service.dart';

final _sentAt = DateTime.utc(2026, 11, 2, 10);
final _secret = 's' * 43;

class _FakeChecker implements NewsletterStatusChecker {
  _FakeChecker(this.replies);

  /// Replies in order; the last one repeats.
  final List<NewsletterStatusReply> replies;
  final asked = <DateTime>[];

  @override
  Future<NewsletterStatusReply> check(String statusSecret) async {
    expect(statusSecret, _secret);
    asked.add(clock.now());
    final index = asked.length - 1;
    return replies[index < replies.length ? index : replies.length - 1];
  }
}

/// Holds the status answer until the test completes it, so a sign-up can be
/// sent while the question is still out.
class _GatedChecker implements NewsletterStatusChecker {
  final asked = Completer<void>();
  final answer = Completer<NewsletterStatusReply>();

  @override
  Future<NewsletterStatusReply> check(String statusSecret) {
    expect(statusSecret, _secret);
    asked.complete();
    return answer.future;
  }
}

/// Runs [body] with the clock set to [at].
Future<T> _at<T>(DateTime at, Future<T> Function() body) =>
    withClock(Clock.fixed(at), body);

void main() {
  late _FakeChecker checker;
  late ProviderContainer container;

  /// A container with a sign-up sent at [_sentAt] and [replies] from the
  /// status endpoint.
  Future<void> arrange(List<NewsletterStatusReply> replies) async {
    SharedPreferences.setMockInitialValues({});
    checker = _FakeChecker(replies);
    container = ProviderContainer(
      overrides: [newsletterStatusCheckerProvider.overrideWithValue(checker)],
    );
    addTearDown(container.dispose);
    await _at(_sentAt, () => container.read(newsletterSignupProvider.future));
    await _at(
      _sentAt,
      () => container.read(newsletterSignupProvider.notifier).sent(_secret),
    );
  }

  Future<void> ask(DateTime at) =>
      _at(at, () => container.read(newsletterSignupProvider.notifier).ask());

  /// The link back from the confirmation page.
  Future<void> link(DateTime at) => _at(
    at,
    () =>
        container.read(newsletterSignupProvider.notifier).ask(immediate: true),
  );

  NewsletterSignup current() =>
      container.read(newsletterSignupProvider).requireValue;

  const pending = NewsletterStatusReply(NewsletterStatusAnswer.pending);

  test('the server is asked at most once per two minutes', () async {
    await arrange([pending]);

    await ask(_sentAt);
    await ask(_sentAt.add(const Duration(minutes: 1)));
    await ask(_sentAt.add(const Duration(minutes: 2)));

    expect(checker.asked, [_sentAt, _sentAt.add(const Duration(minutes: 2))]);
    expect(current().statusSecret, _secret);
  });

  test('a 429 without Retry-After only keeps the two-minute gap', () async {
    await arrange([
      const NewsletterStatusReply(NewsletterStatusAnswer.limited),
    ]);

    await ask(_sentAt);
    await ask(_sentAt.add(const Duration(minutes: 1)));
    await ask(_sentAt.add(const Duration(minutes: 2)));

    expect(checker.asked.length, 2);
    expect(current().statusSecret, _secret, reason: 'a 429 is no error');
  });

  test(
    'a 429 with Retry-After holds the questions back until it passed',
    () async {
      await arrange([
        const NewsletterStatusReply(
          NewsletterStatusAnswer.limited,
          retryAfter: Duration(minutes: 10),
        ),
        pending,
      ]);

      await ask(_sentAt);
      await ask(_sentAt.add(const Duration(minutes: 9, seconds: 59)));
      expect(checker.asked.length, 1);

      await ask(_sentAt.add(const Duration(minutes: 10)));
      expect(checker.asked.length, 2);
    },
  );

  test('active confirms once and forgets the secret', () async {
    await arrange([const NewsletterStatusReply(NewsletterStatusAnswer.active)]);
    final confirmedAt = _sentAt.add(const Duration(minutes: 3));

    await ask(confirmedAt);

    expect(current(), NewsletterSignup(confirmedAt: confirmedAt));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kNewsletterStatusSecretKey), isNull);
    expect(prefs.getInt(kNewsletterConfirmedAtKey), isNotNull);

    await ask(confirmedAt.add(const Duration(minutes: 5)));
    expect(checker.asked.length, 1, reason: 'nothing is pending any more');
  });

  test('a late answer to a superseded sign-up leaves the newer one', () async {
    SharedPreferences.setMockInitialValues({});
    final gate = _GatedChecker();
    container = ProviderContainer(
      overrides: [newsletterStatusCheckerProvider.overrideWithValue(gate)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(newsletterSignupProvider.notifier);
    final later = _sentAt.add(const Duration(minutes: 3));
    await _at(_sentAt, () => container.read(newsletterSignupProvider.future));
    await _at(_sentAt, () => notifier.sent(_secret));

    final asking = _at(later, () => notifier.ask());
    await gate.asked.future;
    final newer = 't' * 43;
    await _at(later, () => notifier.sent(newer));
    gate.answer.complete(
      const NewsletterStatusReply(NewsletterStatusAnswer.active),
    );
    await asking;

    expect(current().statusSecret, newer);
    expect(current().confirmedAt, isNull, reason: 'the old sign-up confirmed');
  });

  test('the link back asks at once, 30 s after a focus question', () async {
    await arrange([pending]);
    await ask(_sentAt);

    await link(_sentAt.add(const Duration(seconds: 30)));

    expect(checker.asked.length, 2);
  });

  test('the link back waits 10 s after the last question', () async {
    await arrange([pending]);
    await ask(_sentAt);

    await link(_sentAt.add(const Duration(seconds: 5)));
    expect(checker.asked.length, 1, reason: 'a double click asks once');

    await link(_sentAt.add(const Duration(seconds: 10)));
    expect(checker.asked.length, 2);
  });

  test('the link back does not ask during a Retry-After wait', () async {
    await arrange([
      const NewsletterStatusReply(
        NewsletterStatusAnswer.limited,
        retryAfter: Duration(minutes: 10),
      ),
      pending,
    ]);
    await ask(_sentAt);

    await link(_sentAt.add(const Duration(seconds: 30)));
    expect(checker.asked.length, 1);

    await link(_sentAt.add(const Duration(minutes: 10)));
    expect(checker.asked.length, 2);
  });

  test('focus and the card keep the two-minute gap', () async {
    await arrange([pending]);
    await ask(_sentAt);

    await ask(_sentAt.add(const Duration(seconds: 30)));
    expect(checker.asked.length, 1);
  });

  test(
    'a failing question never escapes the unawaited callers (F17-5)',
    () async {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [
          newsletterStatusCheckerProvider.overrideWithValue(_ThrowingChecker()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(newsletterSignupProvider.notifier);
      await _at(_sentAt, () => container.read(newsletterSignupProvider.future));
      await _at(_sentAt, () => notifier.sent(_secret));

      await expectLater(_at(_sentAt, notifier.ask), completes);
      expect(current().statusSecret, _secret);
    },
  );
}

/// A status check that fails outside the HTTP checker's own error handling.
class _ThrowingChecker implements NewsletterStatusChecker {
  @override
  Future<NewsletterStatusReply> check(String statusSecret) async =>
      throw StateError('prefs gone');
}
