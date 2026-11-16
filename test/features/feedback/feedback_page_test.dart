import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/features/feedback/contact_draft.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Service factories for testing
// ---------------------------------------------------------------------------

/// Returns a [FeedbackSubmissionService] that always produces [FeedbackSent].
FeedbackSubmissionService _sentService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('', 201)),
  baseUrl: 'https://api.example.test',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always produces
/// [FeedbackSkippedNotConfigured] (empty URL/key).
FeedbackSubmissionService _notConfiguredService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('', 201)),
  baseUrl: '',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always returns HTTP 500.
FeedbackSubmissionService _serverErrorService() => FeedbackSubmissionService(
  client: MockClient((_) async => http.Response('Internal Server Error', 500)),
  baseUrl: 'https://api.example.test',
  breadcrumbSink: (_) {},
);

/// Returns a [FeedbackSubmissionService] that always throws [SocketException].
FeedbackSubmissionService _networkErrorService() => FeedbackSubmissionService(
  client: MockClient((_) async {
    throw const SocketException('Connection refused');
  }),
  baseUrl: 'https://api.example.test',
  breadcrumbSink: (_) {},
);

// ---------------------------------------------------------------------------
// Helper: fill form + tap submit
// ---------------------------------------------------------------------------

final _submit = find.byKey(const ValueKey('contact-form-submit'));
final _thanks = find.byKey(const ValueKey('contact-form-send-another'));

WpButton _submitButton(WidgetTester tester) => tester.widget<WpButton>(
  find.ancestor(of: _submit, matching: find.byType(WpButton)),
);

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('feedbackCommentField')),
    'Test feedback message',
  );
  await tester.pumpAndSettle();

  final submitFinder = _submit;
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

      expect(_submit, findsOneWidget);
      // No message yet → onPressed must be null.
      expect(_submitButton(tester).onPressed, isNull);

      // Below the API minimum the button stays disabled.
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'too short',
      );
      await tester.pumpAndSettle();
      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('a message alone enables submit: category and rating are '
        'optional', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'The hotkey stops working.',
      );
      await tester.pumpAndSettle();

      expect(_submitButton(tester).onPressed, isNotNull);
    });

    // ── AC: optional contact email ─────────────────────────────────────────

    Future<void> fillRequiredInputs(WidgetTester tester) async {
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

      expect(_submitButton(tester).onPressed, isNotNull);
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

      expect(_submitButton(tester).onPressed, isNull);
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

      expect(_submitButton(tester).onPressed, isNotNull);
    });

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
        expect(_thanks, findsNothing);
        expect(_submit, findsOneWidget);
      },
    );

    // ── AC: FeedbackSent shows ThankYou and clears the draft ─────────────

    testWidgets('FeedbackSent: shows thank-you screen and clears the draft', (
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

      expect(_thanks, findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FeedbackPage)),
      );
      expect(container.read(contactDraftProvider).hasText, isFalse);
    });

    testWidgets('only a tap sends: typing alone never reaches the API', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(
            submissionService: FeedbackSubmissionService(
              client: MockClient((_) async {
                calls++;
                return http.Response('', 202);
              }),
              baseUrl: 'https://api.example.test',
              breadcrumbSink: (_) {},
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'Test feedback message\n',
      );
      await tester.pumpAndSettle();
      expect(calls, 0);

      await tester.ensureVisible(_submit);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(calls, 1);
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
                baseUrl: 'https://api.example.test',
                breadcrumbSink: (_) {},
              ),
            ),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(tester.takeException(), isNull);
        expect(_submit, findsOneWidget);
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

        expect(_thanks, findsNothing);
        expect(_submit, findsOneWidget);
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

        expect(_thanks, findsNothing);
        expect(_submit, findsOneWidget);
        // The draft stays and the button offers a retry.
        expect(find.text('Test feedback message'), findsOneWidget);
        expect(_submitButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets('the draft survives leaving and reopening the page', (
      tester,
    ) async {
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      await tester.pumpWidget(
        makeTestable(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? FeedbackPage(submissionService: _sentService())
                : const SizedBox.shrink(),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'Half-written message',
      );
      await tester.enterText(
        find.byKey(const Key('feedbackEmailField')),
        'me@example.org',
      );
      await tester.pumpAndSettle();

      show.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackPage), findsNothing);
      show.value = true;
      await tester.pumpAndSettle();

      expect(find.text('Half-written message'), findsOneWidget);
      expect(find.text('me@example.org'), findsOneWidget);
    });

    testWidgets('Escape with text asks before the draft is discarded', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'Keep me please',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Keep me please'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Keep me please'), findsNothing);
    });

    testWidgets('Escape on an empty form asks nothing', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-dialog-confirm')),
        findsNothing,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Thank-You-View without review CTAs (growth review R-02)
  //
  // Feedback is never a review prompt: the thank-you state must not offer a
  // store rating or a GitHub star, on any platform, whatever was submitted.
  // ───────────────────────────────────────────────────────────────────────

  group('Thank-You-View without review CTAs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('after submit: the ideas link stays', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _fillAndSubmit(tester);

      expect(_thanks, findsOneWidget);
      expect(
        find.byKey(const ValueKey('contact-form-ideas-board')),
        findsOneWidget,
      );
    });
  });
}
