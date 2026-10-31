/// Hand-over points of the onboarding contact panel: what a message sends
/// with and without the technical details, that it never carries the quote
/// consent or a rating, how the server's answer maps, and what the chips
/// trigger (idea board link, send, retry with the text kept).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:whispaste/features/onboarding/widgets/onboarding_contact.dart';
import 'package:whispaste/features/onboarding/widgets/onboarding_contact_launcher.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

FeedbackPayload _payload({
  OnboardingContactKind kind = OnboardingContactKind.problem,
  String message = '  The hotkey does nothing.  ',
  String email = '',
  bool diagnostics = false,
}) => buildOnboardingContactPayload(
  kind: kind,
  message: message,
  email: email,
  includeDiagnostics: diagnostics,
  stepId: 'mic-check',
  appVersion: '9.9.9',
  os: 'macos 15.5',
  deviceIdHash: 'abcdef012345',
  locale: 'de',
);

void main() {
  group('payload', () {
    test('without the opt-in the text is the message alone', () {
      final json = _payload().toJson();
      expect(json['feedback_text'], 'The hotkey does nothing.');
      expect(json['feedback_text'], isNot(contains('mic-check')));
      expect(json['feedback_text'], isNot(contains('macos')));
      expect(json['category'], 'bug');
      expect(json['rating'], isNull);
      expect(json['publish_consent'], false);
      expect(json.containsKey('consent_text_version'), isFalse);
      expect(json.containsKey('withdraw_token_hash'), isFalse);
      expect(json.containsKey('contact_email'), isFalse);
    });

    test('with the opt-in it adds step, app version and OS only', () {
      final text = _payload(diagnostics: true).feedbackText;
      expect(text, startsWith('The hotkey does nothing.\n\n'));
      expect(text, contains('Step mic-check'));
      expect(text, contains('App 9.9.9'));
      expect(text, contains('OS macos 15.5'));
      expect(text, isNot(contains('Engine')));
      expect(text, isNot(contains('Backend')));
    });

    test('the text never exceeds the server limit', () {
      final text = _payload(message: 'x' * 5000, diagnostics: true);
      expect(
        text.feedbackText.length,
        lessThanOrEqualTo(kOnboardingContactMaxTextLength),
      );
    });

    test('an e-mail is trimmed and carries the contact locale', () {
      final json = _payload(email: ' me@example.org ').toJson();
      expect(json['contact_email'], 'me@example.org');
      expect(json['contact_locale'], 'de');
    });

    test('categories follow the feedback form; ideas never send', () {
      expect(onboardingContactCategory(OnboardingContactKind.problem), 'bug');
      expect(
        onboardingContactCategory(OnboardingContactKind.question),
        'general',
      );
      expect(onboardingContactCategory(OnboardingContactKind.other), 'general');
      expect(onboardingContactCategory(OnboardingContactKind.idea), isNull);
      expect(
        () => _payload(kind: OnboardingContactKind.idea),
        throwsArgumentError,
      );
    });

    test('message and e-mail gates', () {
      expect(isSendableContactMessage('too short'), isFalse);
      expect(isSendableContactMessage('  long enough  '), isTrue);
      expect(isAcceptableContactEmail(''), isTrue);
      expect(isAcceptableContactEmail('me@example.org'), isTrue);
      expect(isAcceptableContactEmail('me@example'), isFalse);
      expect(isAcceptableContactEmail('me example.org'), isFalse);
    });

    test('server answers map to what the panel shows', () {
      expect(
        onboardingContactOutcome(const FeedbackSent()),
        OnboardingContactOutcome.sent,
      );
      expect(
        onboardingContactOutcome(const FeedbackNetworkError('offline')),
        OnboardingContactOutcome.retry,
      );
      expect(
        onboardingContactOutcome(const FeedbackServerError(500, '')),
        OnboardingContactOutcome.retry,
      );
      expect(
        onboardingContactOutcome(const FeedbackRateLimitedServer()),
        OnboardingContactOutcome.rateLimited,
      );
      expect(
        onboardingContactOutcome(const FeedbackSkippedNotConfigured()),
        OnboardingContactOutcome.unavailable,
      );
    });
  });

  group('panel', () {
    late List<Map<String, Object?>> sent;
    late bool offline;

    setUp(() {
      sent = [];
      offline = false;
    });

    FeedbackSubmissionService service() => FeedbackSubmissionService(
      client: MockClient((req) async {
        if (offline) throw const SocketException('offline');
        sent.add((jsonDecode(req.body) as Map).cast<String, Object?>());
        return http.Response('', 201);
      }),
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'test-key',
      breadcrumbSink: (_) {},
    );

    Future<void> pump(WidgetTester tester, {bool sendEnabled = true}) async {
      await tester.pumpWidget(
        makeTestable(
          const Align(
            alignment: Alignment.bottomRight,
            child: OnboardingContactLauncher(stepId: 'welcome'),
          ),
          locale: const Locale('en'),
          overrides: [
            feedbackSubmissionServiceProvider.overrideWithValue(service()),
            onboardingContactSendEnabledProvider.overrideWithValue(sendEnabled),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> tap(WidgetTester tester, String id) async {
      // The panel scrolls on a small test surface; bring the target into view first.
      final finder = find.byKey(ValueKey(id));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> type(WidgetTester tester, String id, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pump();
    }

    testWidgets('the idea chip opens the public board', (tester) async {
      final launcher = _FakeUrlLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);

      await pump(tester);
      await tap(tester, 'onboarding-contact-launcher');
      await tap(tester, 'onboarding-contact-chip-idea');
      await tap(tester, 'onboarding-contact-idea-open');

      expect(launcher.launched, [kOnboardingIdeaBoardUrl]);
      expect(sent, isEmpty);
    });

    testWidgets('a problem sends the step only after the opt-in', (
      tester,
    ) async {
      await pump(tester);
      await tap(tester, 'onboarding-contact-launcher');
      await tap(tester, 'onboarding-contact-chip-problem');
      await type(tester, 'onboarding-contact-message', 'No sound at all.');
      await tap(tester, 'onboarding-contact-send');

      expect(sent, hasLength(1));
      expect(sent.single['category'], 'bug');
      expect(sent.single['feedback_text'], 'No sound at all.');

      // The panel thanks and stays until the user presses Done.
      expect(find.byKey(const ValueKey('onboarding-contact-sent')), findsOne);
      expect(find.byKey(const ValueKey('onboarding-contact-done')), findsOne);
      await tap(tester, 'onboarding-contact-done');
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('onboarding-contact-panel')),
        findsNothing,
      );

      await tap(tester, 'onboarding-contact-launcher');
      await tap(tester, 'onboarding-contact-chip-question');
      await type(tester, 'onboarding-contact-message', 'Which model is best?');
      await tap(tester, 'onboarding-contact-diagnostics');
      await tap(tester, 'onboarding-contact-send');

      expect(sent, hasLength(2));
      expect(sent.last['category'], 'general');
      expect(sent.last['feedback_text'], contains('Step welcome'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('a short message is not sent', (tester) async {
      await pump(tester);
      await tap(tester, 'onboarding-contact-launcher');
      await tap(tester, 'onboarding-contact-chip-other');
      await type(tester, 'onboarding-contact-message', 'short');
      await tap(tester, 'onboarding-contact-send');
      expect(sent, isEmpty);
    });

    testWidgets('offline keeps the text and retries', (tester) async {
      offline = true;
      await pump(tester);
      await tap(tester, 'onboarding-contact-launcher');
      await tap(tester, 'onboarding-contact-chip-problem');
      await type(tester, 'onboarding-contact-message', 'Paste fails often.');
      await tap(tester, 'onboarding-contact-send');

      expect(find.byKey(const ValueKey('onboarding-contact-error')), findsOne);
      expect(find.text('Paste fails often.'), findsOne);

      offline = false;
      await tap(tester, 'onboarding-contact-send');
      expect(sent.single['feedback_text'], 'Paste fails often.');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
    });

    test('sending stays off until the rating migration is live', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(onboardingContactSendEnabledProvider), isFalse);
    });

    testWidgets(
      'with sending off, nothing is sent and the mail address shows',
      (tester) async {
        await pump(tester, sendEnabled: false);
        await tap(tester, 'onboarding-contact-launcher');
        await tap(tester, 'onboarding-contact-chip-problem');
        expect(
          find.byKey(const ValueKey('onboarding-contact-send')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('onboarding-contact-write-mail')),
          findsOne,
        );
        expect(sent, isEmpty);
      },
    );

    testWidgets('Esc closes the panel', (tester) async {
      await pump(tester);
      await tap(tester, 'onboarding-contact-launcher');
      expect(find.byKey(const ValueKey('onboarding-contact-panel')), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('onboarding-contact-panel')),
        findsNothing,
      );
    });
  });
}
