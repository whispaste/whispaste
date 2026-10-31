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
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

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

      // No rating/category/comment yet → onPressed must be null.
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

        // Select the "General" category chip (l10n.feedbackCategoryGeneral).
        await tester.tap(find.text(l10n.feedbackCategoryGeneral));
        await tester.pumpAndSettle();

        // Tap the 🤩 emoji (rating = 5).
        await tester.tap(find.text('🤩'));
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
      await tester.tap(find.text(l10n.feedbackCategoryGeneral));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🤩'));
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

  // ───────────────────────────────────────────────────────────────────────
  // The two pickers are real controls
  //
  // Both were bare `GestureDetector`s: two of this form's three inputs could
  // not be reached, focused or operated without a mouse, on a page whose
  // audience explicitly includes people with RSI. These tests pin the
  // interaction contract so a later refactor cannot quietly drop it again.
  // ───────────────────────────────────────────────────────────────────────
  group('Feedback pickers', () {
    // Own `setUpAll` rather than borrowing the widget group's: this group must
    // pass when run on its own with `--plain-name`, not only in file order.
    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      'announce themselves once, as buttons, with a selection state',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          makeTestable(
            FeedbackPage(submissionService: _sentService()),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(find.text(l10n.feedbackCategoryBug)),
          // The label is asserted verbatim on purpose: a `Semantics(label:)`
          // over a subtree that renders the same text prepends rather than
          // replaces, which used to make every chip say its own name twice.
          isSemantics(
            isButton: true,
            label: l10n.feedbackCategoryBug,
            hasTapAction: true,
          ),
        );

        expect(
          tester.getSemantics(find.text(l10n.feedbackRatingOkay)),
          isSemantics(
            isButton: true,
            // One of five, and picking it unpicks the rest.
            isInMutuallyExclusiveGroup: true,
            // The emoji glyph is excluded, so the name is the word, not
            // "slightly smiling face, Okay".
            label: l10n.feedbackRatingOkay,
            hasTapAction: true,
          ),
        );

        handle.dispose();
      },
    );

    testWidgets('can be operated from the keyboard alone', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> activateByKeyboard(String label) async {
        final inkWell = tester.widget<InkWell>(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first,
        );
        expect(
          inkWell.focusNode,
          isNotNull,
          reason: '"$label" must own a focus node to be reachable by Tab',
        );
        inkWell.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }

      await activateByKeyboard(l10n.feedbackCategoryBug);
      await activateByKeyboard(l10n.feedbackRatingLoveIt);

      expect(
        tester.getSemantics(find.text(l10n.feedbackCategoryBug)),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.text(l10n.feedbackRatingLoveIt)),
        isSemantics(isSelected: true),
      );

      handle.dispose();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The category chips are the one control on this form whose tap surface is
  // taller than the thing the eye sees: `WpFilterChip` centres a ~28px pill
  // in a 48px target, so ~10px above and below each pill is empty. The page
  // states the gaps around that row an `xs` step short to cancel it. Both
  // halves of that arrangement — the compensation and the slack it assumes —
  // live in different files, so pin the result rather than either input.
  // ───────────────────────────────────────────────────────────────────────
  group('Feedback category chips — vertical rhythm', () {
    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    /// Distance from the bottom of [label] to the top of the nearest visible
    /// edge below it — the gap a reader actually sees, not the box gap.
    double opticalGap(WidgetTester tester, Finder label, Finder control) =>
        tester.getRect(control).top - tester.getRect(label).bottom;

    testWidgets('sit the same distance under their label as every other '
        'control on the form', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final firstPill = find
          .descendant(
            of: find.byType(WpFilterChip).first,
            matching: find.byType(AnimatedContainer),
          )
          .first;
      final firstEmojiTile = find
          .ancestor(
            of: find.text(l10n.feedbackRatingFrustrated),
            matching: find.byType(AnimatedContainer),
          )
          .first;

      final chipGap = opticalGap(
        tester,
        find.text(l10n.feedbackCategoryLabel),
        firstPill,
      );
      final ratingGap = opticalGap(
        tester,
        find.text(l10n.feedbackRatingLabel),
        firstEmojiTile,
      );

      expect(
        chipGap,
        closeTo(ratingGap, 3),
        reason:
            'the chips sat 26px under their label against the rating row\'s '
            '16px, because the gap was stated as WpSpacing.md on a row that '
            'brings 10px of its own. Off by more than a rounding step means '
            'the chip\'s pill or touch target moved and the compensation on '
            'the page no longer matches it.',
      );
    });

    testWidgets('share their runs instead of taking one row each', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(submissionService: _sentService()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final chips = find.byType(WpFilterChip);
      expect(chips, findsNWidgets(4));
      final tops = {
        for (var i = 0; i < 4; i++) tester.getTopLeft(chips.at(i)).dy,
      };
      // Deliberately not "exactly one run": how many fit depends on the label
      // widths, and those depend on the locale and on which font the test
      // environment resolves. What the bug did was categorical — every chip
      // reported the full 560px column around a compact pill, so all four
      // landed on rows of their own no matter how short the labels were.
      expect(
        tops.length,
        lessThan(4),
        reason:
            'each chip claimed the full width of the form column and dropped '
            'onto a run of its own — the Wrap on this page is what first '
            'exposed that in WpFilterChip',
      );
    });
  });
}
