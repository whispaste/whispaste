import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

// ---------------------------------------------------------------------------
// Service factories for testing
// ---------------------------------------------------------------------------

/// Returns a [FeedbackSubmissionService] that always produces [FeedbackSent].
FeedbackSubmissionService _sentService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('', 201)),
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always produces
/// [FeedbackSkippedNotConfigured] (empty URL/key).
FeedbackSubmissionService _notConfiguredService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('', 201)),
  supabaseUrl: '',
  supabasePublishableKey: '',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always returns HTTP 500.
FeedbackSubmissionService _serverErrorService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('Internal Server Error', 500)),
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always throws [SocketException].
FeedbackSubmissionService _networkErrorService() => FeedbackSubmissionService(
  client: MockClient((_) async {
    throw const SocketException('Connection refused');
  }),
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
  breadcrumbSink: (_) {},
);

// ---------------------------------------------------------------------------
// Helper: fill form + tap submit
// ---------------------------------------------------------------------------

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.tap(find.text(l10n.feedbackTypePraise));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier('feedback-rating-5'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('feedbackCommentField')),
    'Test feedback',
  );
  await tester.pumpAndSettle();

  final submitFinder = find.widgetWithText(WpButton, l10n.feedbackSubmit);
  await tester.ensureVisible(submitFinder);
  await tester.pumpAndSettle();
  await tester.tap(submitFinder);
  await tester.pumpAndSettle();
}

void main() {
  group('isValidFeedbackContactEmail', () {
    test('accepts a plausible address', () {
      expect(isValidFeedbackContactEmail('user@example.com'), isTrue);
    });

    test('rejects missing @, missing domain dot, and whitespace', () {
      expect(isValidFeedbackContactEmail('not-an-email'), isFalse);
      expect(isValidFeedbackContactEmail('user@example'), isFalse);
      expect(isValidFeedbackContactEmail('user @example.com'), isFalse);
      expect(isValidFeedbackContactEmail(''), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // FeedbackPage widget tests
  // ───────────────────────────────────────────────────────────────────────
  group('FeedbackPage widget', () {
    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a feedback sent within 24 h is flagged when the form opens, '
        'and sending is blocked (UIA-FBK-04)', (tester) async {
      SharedPreferences.setMockInitialValues({
        'feedback_last_submitted_ms': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.feedbackErrorRateLimited), findsOneWidget);
      final button = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.feedbackSubmit),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('submit button is disabled before inputs are filled', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // "Send Feedback" comes from l10n.feedbackSubmit (app_en.arb).
      final submitFinder = find.widgetWithText(WpButton, l10n.feedbackSubmit);
      expect(submitFinder, findsOneWidget);

      // No type/comment yet → onPressed must be null.
      final button = tester.widget<WpButton>(submitFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'submit button becomes enabled after all three inputs are filled',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // Select a type chip (praise: the least demanding one).
        await tester.tap(find.text(l10n.feedbackTypePraise));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('feedback-rating-5'));
        await tester.pumpAndSettle();

        // Enter a comment so feedback_text is non-empty.
        await tester.enterText(
          find.byKey(const Key('feedbackCommentField')),
          'Great app!',
        );
        await tester.pumpAndSettle();

        final button = tester.widget<WpButton>(
          find.widgetWithText(WpButton, l10n.feedbackSubmit),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    // ── AC: optional contact email ─────────────────────────────────────────

    Future<void> fillRequiredInputs(WidgetTester tester) async {
      await tester.tap(find.text(l10n.feedbackTypePraise));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('feedback-rating-5'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'Great app!',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('submit stays enabled when the email field is left empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await fillRequiredInputs(tester);

      final button = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.feedbackSubmit),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('an invalid email disables submit and shows an inline error', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await fillRequiredInputs(tester);

      await tester.enterText(
        find.byKey(const Key('feedbackEmailField')),
        'not-an-email',
      );
      await tester.pumpAndSettle();

      final button = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.feedbackSubmit),
      );
      expect(button.onPressed, isNull);
      expect(find.text(l10n.feedbackContactEmailInvalid), findsOneWidget);
    });

    testWidgets('a valid email keeps submit enabled, no inline error', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await fillRequiredInputs(tester);

      await tester.enterText(
        find.byKey(const Key('feedbackEmailField')),
        'user@example.com',
      );
      await tester.pumpAndSettle();

      final button = tester.widget<WpButton>(
        find.widgetWithText(WpButton, l10n.feedbackSubmit),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text(l10n.feedbackContactEmailInvalid), findsNothing);
    });

    testWidgets(
      'the reply-language picker only appears once an email is entered',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();
        await fillRequiredInputs(tester);

        expect(find.text(l10n.feedbackContactLanguageLabel), findsNothing);

        await tester.enterText(
          find.byKey(const Key('feedbackEmailField')),
          'user@example.com',
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.feedbackContactLanguageLabel), findsOneWidget);
      },
    );

    // ── AC: SkippedNotConfigured shows error, no ThankYou ─────────────────

    testWidgets(
      'SkippedNotConfigured: shows feedbackErrorNotConfigured banner, no thank-you screen',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _notConfiguredService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        // Must NOT show thank-you screen.
        expect(find.text(l10n.feedbackThankYou), findsNothing);
        // Must show the "not configured" error text.
        expect(find.text(l10n.feedbackErrorNotConfigured), findsOneWidget);
      },
    );

    testWidgets(
      'SkippedNotConfigured: cooldown is NOT written to SharedPreferences',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _notConfiguredService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('feedback_last_submitted_ms'), isNull);
      },
    );

    // ── AC: FeedbackSent shows ThankYou, writes cooldown ─────────────────

    // UIA-FBK-06: the thank-you message is announced when it appears.
    testWidgets('the thank-you message is a live region (UIA-FBK-06)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(
        find.ancestor(
          of: find.text(l10n.feedbackThankYou),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FeedbackSent: shows thank-you screen and writes cooldown', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.text(l10n.feedbackThankYou), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('feedback_last_submitted_ms'), isNotNull);
    });

    // UIA-FBK-05: an Error (not an Exception) from the send path must still
    // end the sending state with a message.
    testWidgets(
      'an Error during send shows the server error, not a spinner (UIA-FBK-05)',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(
              submissionService: FeedbackSubmissionService(
                client: MockClient((_) async => throw StateError('type error')),
                supabaseUrl: 'https://example.supabase.co',
                supabasePublishableKey: 'test-key',
                breadcrumbSink: (_) {},
              ),
            ),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(l10n.feedbackErrorServer), findsOneWidget);
      },
    );

    // ── AC: ServerError shows feedbackErrorServer, no ThankYou ───────────

    testWidgets(
      'FeedbackServerError: shows feedbackErrorServer banner, no thank-you',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _serverErrorService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text(l10n.feedbackThankYou), findsNothing);
        expect(find.text(l10n.feedbackErrorServer), findsOneWidget);
      },
    );

    // ── AC: NetworkError shows feedbackErrorNetwork, no ThankYou ─────────

    testWidgets(
      'FeedbackNetworkError: shows feedbackErrorNetwork banner, no thank-you',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _networkErrorService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text(l10n.feedbackThankYou), findsNothing);
        expect(find.text(l10n.feedbackErrorNetwork), findsOneWidget);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // Thank-You-View without review CTAs (growth review R-02)
  //
  // Feedback is never a review prompt: the thank-you state must not offer a
  // store rating or a GitHub star, on any platform, whatever was submitted.
  // ───────────────────────────────────────────────────────────────────────

  group('Thank-You-View without review CTAs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('after submit: no rating section, the ideas link stays', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _fillAndSubmit(tester);

      expect(find.text(l10n.feedbackThankYou), findsOneWidget);
      expect(find.text(l10n.reviewSupportEntry), findsNothing);
      expect(find.text(l10n.feedbackIdeasLink), findsOneWidget);
    });
  });
}
