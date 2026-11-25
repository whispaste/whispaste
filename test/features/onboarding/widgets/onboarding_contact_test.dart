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
import 'package:whispaste/services/feedback_diagnostics.dart';

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

ContactPayload _payload({
  OnboardingContactKind kind = OnboardingContactKind.problem,
  String message = '  The hotkey does nothing.  ',
  String email = '',
  bool diagnostics = false,
  List<String>? logReads,
}) => buildOnboardingContactPayload(
  message: OnboardingContactMessage(
    kind: kind,
    message: message,
    email: email,
    includeDiagnostics: diagnostics,
    stepId: 'micCheck',
    elapsed: const Duration(seconds: 12),
  ),
  locale: 'de',
  installHash: 'a' * 64,
  appVersion: '9.9.9',
  operatingSystem: 'macos',
  readDiagnostics: () {
    logReads?.add('read');
    return 'sanitized log excerpt';
  },
);

void main() {
  group('payload', () {
    test('without the opt-in only the message leaves, no log is read', () {
      final reads = <String>[];
      final json = _payload(logReads: reads).toJson();
      expect(json['message'], 'The hotkey does nothing.');
      expect(json['kind'], 'problem');
      expect(json['rating'], isNull);
      for (final key in const [
        'appVersion',
        'os',
        'stepId',
        'diagnostics',
        'publish_consent',
        'withdraw_token_hash',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(reads, isEmpty);
    });

    test('with the opt-in version, system, step and the attachment travel '
        'apart from the message', () {
      final reads = <String>[];
      final json = _payload(diagnostics: true, logReads: reads).toJson();
      expect(json['message'], 'The hotkey does nothing.');
      expect(json['appVersion'], '9.9.9');
      expect(json['os'], 'macos');
      expect(json['stepId'], 'mic_check');
      expect(json['diagnostics'], 'sanitized log excerpt');
      expect(reads, hasLength(1));
    });

    test('step ids follow the API pattern', () {
      expect(contactStepId('tryOut'), 'try_out');
      expect(contactStepId('welcome'), 'welcome');
      expect(contactStepId('mic-check'), 'mic_check');
      expect(contactStepId('42'), isNull);
      expect(contactStepId('a' * 40), hasLength(32));
    });

    test('an e-mail is trimmed', () {
      expect(
        _payload(email: ' me@example.org ').toJson()['email'],
        'me@example.org',
      );
    });

    test('ideas never send; the other kinds keep their category', () {
      expect(onboardingContactCategory(OnboardingContactKind.problem), 'bug');
      expect(onboardingContactCategory(OnboardingContactKind.idea), isNull);
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
      baseUrl: 'https://api.example.test',
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
            feedbackDiagnosticAttachmentProvider.overrideWithValue(
              'sanitized crash log',
            ),
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
      expect(sent.single['kind'], 'problem');
      expect(sent.single['message'], 'No sound at all.');
      expect(sent.single.containsKey('diagnostics'), isFalse);

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
      expect(sent.last['kind'], 'question');
      expect(sent.last['stepId'], 'welcome');
      expect(sent.last['diagnostics'], 'sanitized crash log');
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
      expect(sent.single['message'], 'Paste fails often.');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
    });

    test('sending is on: the API takes a message without a rating', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(onboardingContactSendEnabledProvider), isTrue);
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
