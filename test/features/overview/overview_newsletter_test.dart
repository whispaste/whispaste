/// What "Anmelden" in the "Mitmachen" block triggers: nothing without consent,
/// one sign-up with the typed address after it, and the double opt-in state
/// or the error state from the answer; later the status question that turns
/// a pending sign-up into a confirmed one. Elements are found by testID;
/// layout and wording are judged by eye.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/features/overview/overview_newsletter.dart';
import 'package:whispaste/services/newsletter/newsletter_logic.dart';
import 'package:whispaste/services/newsletter/newsletter_service.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSubscriber implements NewsletterSubscriber {
  _FakeSubscriber(this.answer);

  final NewsletterOutcome answer;
  final sent = <({String email, String languageCode})>[];
  final secrets = <String?>[];

  @override
  Future<NewsletterOutcome> subscribe({
    required String email,
    required String languageCode,
    required int elapsedMs,
    String? statusSecret,
  }) async {
    sent.add((email: email, languageCode: languageCode));
    secrets.add(statusSecret);
    return answer;
  }
}

class _FakeChecker implements NewsletterStatusChecker {
  _FakeChecker(this.answer);

  final NewsletterStatusAnswer answer;
  final asked = <String>[];

  @override
  Future<NewsletterStatusReply> check(String statusSecret) async {
    asked.add(statusSecret);
    return NewsletterStatusReply(answer);
  }
}

const _email = ValueKey('overview-newsletter-email');
const _consent = ValueKey('overview-newsletter-consent');
const _submit = ValueKey('overview-newsletter-submit');

Future<_FakeSubscriber> _pump(
  WidgetTester tester,
  NewsletterOutcome answer, {
  _FakeChecker? checker,
}) async {
  final subscriber = _FakeSubscriber(answer);
  await tester.pumpWidget(
    makeTestable(
      const Scaffold(
        body: SingleChildScrollView(child: OverviewNewsletterSignup()),
      ),
      overrides: [
        newsletterSubscriberProvider.overrideWithValue(subscriber),
        newsletterStatusCheckerProvider.overrideWithValue(
          checker ?? _FakeChecker(NewsletterStatusAnswer.pending),
        ),
      ],
      locale: const Locale('de'),
    ),
  );
  await tester.pumpAndSettle();
  return subscriber;
}

Future<void> _fill(WidgetTester tester, String address) async {
  await tester.enterText(
    find.descendant(of: find.byKey(_email), matching: find.byType(TextField)),
    address,
  );
  await tester.pump();
}

const _secret = 'sssssssssssssssssssssssssssssssssssssssssss';

void _pendingSignup() {
  SharedPreferences.setMockInitialValues({
    kNewsletterStatusSecretKey: _secret,
    kNewsletterPendingUntilKey: DateTime.now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch,
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('without consent nothing is sent', (tester) async {
    final subscriber = await _pump(tester, NewsletterOutcome.accepted);
    await _fill(tester, 'anna@example.org');
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();
    expect(subscriber.sent, isEmpty);
  });

  testWidgets(
    'with consent one sign-up goes out and the form says to confirm',
    (tester) async {
      final subscriber = await _pump(tester, NewsletterOutcome.accepted);
      await _fill(tester, 'anna@example.org');
      await tester.tap(find.byKey(_consent));
      await tester.pump();
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      expect(subscriber.sent, [
        (email: 'anna@example.org', languageCode: 'de'),
      ]);
      expect(subscriber.secrets.single, isNotNull);
      expect(isNewsletterStatusSecret(subscriber.secrets.single!), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kNewsletterStatusSecretKey),
        subscriber.secrets.single,
      );
      expect(find.bySemanticsIdentifier('overview-newsletter-sent'), findsOne);
      expect(find.byKey(_email), findsNothing);
    },
  );

  testWidgets(
    'a send right after the form appears waits for the fill-in bar (GR-055)',
    (tester) async {
      final subscriber = await _pump(tester, NewsletterOutcome.accepted);
      await _fill(tester, 'anna@example.org');
      await tester.tap(find.byKey(_consent));
      await tester.pump();
      await tester.tap(find.byKey(_submit));
      await tester.pump(kNewsletterMinFillIn ~/ 2);
      expect(subscriber.sent, isEmpty);
      await tester.pump(kNewsletterMinFillIn);
      await tester.pumpAndSettle();
      expect(subscriber.sent, hasLength(1));
    },
  );

  testWidgets('"another address" brings back an empty form', (tester) async {
    await _pump(tester, NewsletterOutcome.accepted);
    await _fill(tester, 'anna@example.org');
    await tester.tap(find.byKey(_consent));
    await tester.pump();
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('overview-newsletter-again'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(of: find.byKey(_email), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('an address that cannot be one is refused before sending', (
    tester,
  ) async {
    final subscriber = await _pump(tester, NewsletterOutcome.accepted);
    await _fill(tester, 'anna@example');
    await tester.tap(find.byKey(_consent));
    await tester.pump();
    await tester.tap(find.byKey(_submit));
    await tester.pumpAndSettle();
    expect(subscriber.sent, isEmpty);
    expect(find.bySemanticsIdentifier('overview-newsletter-error'), findsOne);
  });

  for (final answer in [
    NewsletterOutcome.tooManyAttempts,
    NewsletterOutcome.offline,
    NewsletterOutcome.unavailable,
  ]) {
    testWidgets('$answer keeps the address and shows the error', (
      tester,
    ) async {
      await _pump(tester, answer);
      await _fill(tester, 'anna@example.org');
      await tester.tap(find.byKey(_consent));
      await tester.pump();
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('overview-newsletter-error'), findsOne);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(_email),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, 'anna@example.org');
    });
  }

  group('status', () {
    testWidgets('a confirmed sign-up shows as confirmed and forgets the '
        'secret', (tester) async {
      _pendingSignup();
      final checker = _FakeChecker(NewsletterStatusAnswer.active);
      await _pump(tester, NewsletterOutcome.accepted, checker: checker);
      expect(checker.asked, [_secret]);
      expect(
        find.bySemanticsIdentifier('overview-newsletter-confirmed'),
        findsOne,
      );
      expect(find.byKey(_email), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kNewsletterStatusSecretKey), isNull);
      expect(prefs.getInt(kNewsletterConfirmedAtKey), isNotNull);
    });

    testWidgets('a pending sign-up keeps asking the user to confirm', (
      tester,
    ) async {
      _pendingSignup();
      await _pump(tester, NewsletterOutcome.accepted);
      expect(find.bySemanticsIdentifier('overview-newsletter-sent'), findsOne);
      expect(
        find.bySemanticsIdentifier('overview-newsletter-confirmed'),
        findsNothing,
      );
    });

    testWidgets('a sign-up the server no longer knows ends as a calm note '
        'above the form', (tester) async {
      _pendingSignup();
      final checker = _FakeChecker(NewsletterStatusAnswer.refused);
      await _pump(tester, NewsletterOutcome.accepted, checker: checker);
      expect(
        find.bySemanticsIdentifier('overview-newsletter-lapsed'),
        findsOne,
      );
      expect(find.byKey(_email), findsOne);
      expect(
        find.bySemanticsIdentifier('overview-newsletter-confirmed'),
        findsNothing,
      );
    });

    testWidgets('without a pending sign-up the server is never asked', (
      tester,
    ) async {
      final checker = _FakeChecker(NewsletterStatusAnswer.active);
      await _pump(tester, NewsletterOutcome.accepted, checker: checker);
      expect(checker.asked, isEmpty);
      expect(find.byKey(_email), findsOne);
    });
  });
}
