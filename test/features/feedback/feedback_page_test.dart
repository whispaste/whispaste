import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

import '../../fixtures/test_helpers.dart';

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
  await tester.tap(find.text('General'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('🤩'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Test feedback');
  await tester.pumpAndSettle();

  final submitFinder = find.widgetWithText(ElevatedButton, 'Send Feedback');
  await tester.ensureVisible(submitFinder);
  await tester.pumpAndSettle();
  await tester.tap(submitFinder);
  await tester.pumpAndSettle();
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // computeFeedbackDeviceIdHash — pure unit tests
  // ───────────────────────────────────────────────────────────────────────
  group('computeFeedbackDeviceIdHash', () {
    test('always returns exactly 12 characters', () {
      expect(computeFeedbackDeviceIdHash('my-pc').length, 12);
      expect(computeFeedbackDeviceIdHash('').length, 12);
      expect(computeFeedbackDeviceIdHash('x' * 100).length, 12);
    });

    test('is deterministic', () {
      final a = computeFeedbackDeviceIdHash('test-host');
      final b = computeFeedbackDeviceIdHash('test-host');
      expect(a, equals(b));
    });

    test('produces only lowercase hex characters', () {
      final hash = computeFeedbackDeviceIdHash('my-computer');
      expect(hash, matches(RegExp(r'^[0-9a-f]{12}$')));
    });

    test('different hostnames produce different hashes', () {
      final a = computeFeedbackDeviceIdHash('host-a');
      final b = computeFeedbackDeviceIdHash('host-b');
      expect(a, isNot(equals(b)));
    });

    test('fallback hostname used on error produces valid hash', () {
      // 'fallback_device' is the seed used by _deriveDeviceId when
      // Platform.localHostname throws — must produce a valid 12-char hash.
      final hash = computeFeedbackDeviceIdHash('fallback_device');
      expect(hash.length, 12);
      expect(hash, matches(RegExp(r'^[0-9a-f]{12}$')));
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
        makeTestable(FeedbackPage(submissionService: _sentService())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('submit button is disabled before inputs are filled', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(FeedbackPage(submissionService: _sentService())),
      );
      await tester.pumpAndSettle();

      // "Send Feedback" comes from l10n.feedbackSubmit (app_en.arb).
      final submitFinder = find.widgetWithText(ElevatedButton, 'Send Feedback');
      expect(submitFinder, findsOneWidget);

      // No rating/category/comment yet → onPressed must be null.
      final button = tester.widget<ElevatedButton>(submitFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'submit button becomes enabled after all three inputs are filled',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(FeedbackPage(submissionService: _sentService())),
        );
        await tester.pumpAndSettle();

        // Select the "General" category chip (l10n.feedbackCategoryGeneral).
        await tester.tap(find.text('General'));
        await tester.pumpAndSettle();

        // Tap the 🤩 emoji (rating = 5).
        await tester.tap(find.text('🤩'));
        await tester.pumpAndSettle();

        // Enter a comment so feedback_text is non-empty.
        await tester.enterText(find.byType(TextField), 'Great app!');
        await tester.pumpAndSettle();

        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Send Feedback'),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    // ── AC: SkippedNotConfigured shows error, no ThankYou ─────────────────

    testWidgets(
      'SkippedNotConfigured: shows feedbackErrorNotConfigured banner, no thank-you screen',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _notConfiguredService()),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        // Must NOT show thank-you screen.
        expect(find.text('Thank you!'), findsNothing);
        // Must show the "not configured" error text.
        expect(
          find.text('Feedback is not available in this build.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'SkippedNotConfigured: cooldown is NOT written to SharedPreferences',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _notConfiguredService()),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('feedback_last_submitted_ms'), isNull);
      },
    );

    // ── AC: FeedbackSent shows ThankYou, writes cooldown ─────────────────

    testWidgets('FeedbackSent: shows thank-you screen and writes cooldown', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(FeedbackPage(submissionService: _sentService())),
      );
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.text('Thank you!'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('feedback_last_submitted_ms'), isNotNull);
    });

    // ── AC: ServerError shows feedbackErrorServer, no ThankYou ───────────

    testWidgets(
      'FeedbackServerError: shows feedbackErrorServer banner, no thank-you',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(FeedbackPage(submissionService: _serverErrorService())),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text('Thank you!'), findsNothing);
        expect(
          find.text('Something went wrong. Please try again later.'),
          findsOneWidget,
        );
      },
    );

    // ── AC: NetworkError shows feedbackErrorNetwork, no ThankYou ─────────

    testWidgets(
      'FeedbackNetworkError: shows feedbackErrorNetwork banner, no thank-you',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(FeedbackPage(submissionService: _networkErrorService())),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text('Thank you!'), findsNothing);
        expect(
          find.text(
            'Could not connect to the server. Please check your internet connection.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
