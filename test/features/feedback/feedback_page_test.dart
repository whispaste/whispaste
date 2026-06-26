import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/services/feedback_submission_service.dart';

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
  await tester.tap(find.text(l10n.feedbackCategoryGeneral));
  await tester.pumpAndSettle();
  await tester.tap(find.text('🤩'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Test feedback');
  await tester.pumpAndSettle();

  final submitFinder = find.widgetWithText(ElevatedButton, l10n.feedbackSubmit);
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
      final submitFinder = find.widgetWithText(
        ElevatedButton,
        l10n.feedbackSubmit,
      );
      expect(submitFinder, findsOneWidget);

      // No rating/category/comment yet → onPressed must be null.
      final button = tester.widget<ElevatedButton>(submitFinder);
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

        // Select the "General" category chip (l10n.feedbackCategoryGeneral).
        await tester.tap(find.text(l10n.feedbackCategoryGeneral));
        await tester.pumpAndSettle();

        // Tap the 🤩 emoji (rating = 5).
        await tester.tap(find.text('🤩'));
        await tester.pumpAndSettle();

        // Enter a comment so feedback_text is non-empty.
        await tester.enterText(find.byType(TextField), 'Great app!');
        await tester.pumpAndSettle();

        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, l10n.feedbackSubmit),
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
  // Thank-You-View review CTAs (Säule A+ — feedback page as a review surface)
  // ───────────────────────────────────────────────────────────────────────

  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  group('Thank-You-View review CTAs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      feedbackPlatformIsWindowsOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, (_) async => true);
    });

    tearDown(() {
      feedbackPlatformIsWindowsOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, null);
    });

    testWidgets('CTAs are NOT visible on the form view before submit (AC2)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The review CTAs live exclusively in the Thank-You-View, so the form
      // view must not surface them — they never compete with the submit.
      expect(find.text(l10n.reviewSupportEntry), findsNothing);
      expect(find.text(l10n.reviewPromptRateStore), findsNothing);
      expect(find.text(l10n.reviewPromptStarGitHub), findsNothing);
    });

    testWidgets(
      'Windows Thank-You-View shows Store-Review + GitHub-Stern CTAs (AC1)',
      (tester) async {
        feedbackPlatformIsWindowsOverride = true;
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text(l10n.feedbackThankYou), findsOneWidget);
        expect(find.text(l10n.reviewSupportEntry), findsOneWidget);
        expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
      },
    );

    testWidgets(
      'macOS/Linux Thank-You-View shows GitHub-Stern CTA only — no store (AC1)',
      (tester) async {
        feedbackPlatformIsWindowsOverride = false;
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillAndSubmit(tester);

        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
        expect(find.text(l10n.reviewPromptRateStore), findsNothing);
      },
    );

    testWidgets(
      'Store-Review CTA launches the Windows Store review URL (AC3/AC4)',
      (tester) async {
        feedbackPlatformIsWindowsOverride = true;
        String? capturedUrl;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcherChannel, (call) async {
              if (call.method == 'canLaunch' || call.method == 'launch') {
                capturedUrl = (call.arguments as Map)['url'] as String?;
              }
              return true;
            });

        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();
        await _fillAndSubmit(tester);

        await tester.tap(find.text(l10n.reviewPromptRateStore));
        await tester.pumpAndSettle();

        expect(capturedUrl, kWindowsStoreReviewUrl);
      },
    );

    testWidgets('GitHub-Stern CTA launches the GitHub repo URL (AC3/AC4)', (
      tester,
    ) async {
      feedbackPlatformIsWindowsOverride = false;
      String? capturedUrl;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcherChannel, (call) async {
            if (call.method == 'canLaunch' || call.method == 'launch') {
              capturedUrl = (call.arguments as Map)['url'] as String?;
            }
            return true;
          });

      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _fillAndSubmit(tester);

      await tester.tap(find.text(l10n.reviewPromptStarGitHub));
      await tester.pumpAndSettle();

      expect(capturedUrl, kGitHubRepoUrl);
    });
  });
}
