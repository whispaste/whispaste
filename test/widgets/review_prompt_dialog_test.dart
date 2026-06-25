/// Widget tests for [ReviewPromptWatcher] — verifies button layout and URL
/// targets across all platform × channel combinations.
///
/// Covers:
///  AC1  No `apps.apple.com` URL in any reachable code path.
///  AC2  macOS/Linux (portable, !isWindows): only GitHub star button.
///  AC3  Windows non-store (installer/portable): both buttons; Rate-on-Store
///       opens Windows Store review URL.
///  AC4  Windows store: functionally unchanged (only "Yes" button visible).
///  AC5  GitHub URL is sourced from a single constant — no duplication.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/review_prompt_service.dart';
import 'package:whispaste/widgets/review_prompt_dialog.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifier
// ---------------------------------------------------------------------------

/// Stub that lets tests drive [shouldShowPrompt] without touching
/// SharedPreferences or the deploy channel.
class _FakeReviewPromptNotifier extends ReviewPromptNotifier {
  _FakeReviewPromptNotifier(this._channel);
  final DeployChannel _channel;

  /// Recorder for the persistence seam — the real notifier writes the
  /// cooldown to SharedPreferences inside [dismiss]; the fake just records
  /// that the gate's negative path invoked it.
  bool dismissCalled = false;
  bool? dismissPermanent;

  @override
  ReviewPromptState build() =>
      ReviewPromptState(shouldShowPrompt: false, channel: _channel);

  /// Flips [shouldShowPrompt] to `true` so [ReviewPromptWatcher]'s listener
  /// fires and starts the 1-second delay.
  void triggerShow() =>
      state = ReviewPromptState(shouldShowPrompt: true, channel: _channel);

  @override
  Future<void> markShown() async =>
      state = state.copyWith(shouldShowPrompt: false);

  @override
  Future<void> dismiss({required bool permanent}) async {
    dismissCalled = true;
    dismissPermanent = permanent;
    state = state.copyWith(shouldShowPrompt: false);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Pumps [ReviewPromptWatcher] and advances time past the 1-second delay so
/// the dialog is fully visible and animated in.
Future<_FakeReviewPromptNotifier> _showDialog(
  WidgetTester tester,
  DeployChannel channel, {
  required bool isWindows,
  required L10n l10n,
}) async {
  platformIsWindowsOverride = isWindows;
  final notifier = _FakeReviewPromptNotifier(channel);

  await tester.pumpWidget(
    makeTestable(
      const ReviewPromptWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [reviewPromptProvider.overrideWith(() => notifier)],
    ),
  );
  await tester.pump(); // initial build, ref.listen registered

  notifier.triggerShow();
  await tester.pump(); // state change propagated, 1-second timer started
  await tester.pump(const Duration(seconds: 1)); // timer fires → _showDialog()
  await tester.pumpAndSettle(); // showGeneralDialog + 300 ms animation

  return notifier;
}

/// Taps "Not now" to cleanly dismiss the dialog so the test ends without
/// leaked timers or pending futures.
Future<void> _dismiss(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.text(l10n.reviewPromptNotNow));
  await tester.pumpAndSettle();
}

/// Taps the positive gate answer to advance from the neutral-question stage
/// to the review-buttons stage (AC2). No-op if the dialog already shows the
/// review buttons.
Future<void> _answerGateYes(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.text(l10n.reviewPromptGateYes));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    platformIsWindowsOverride = null;
    // Stub url_launcher so URL launches don't fail with "no platform".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (_) async => true);
  });

  tearDown(() {
    platformIsWindowsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  // ---------------------------------------------------------------------------
  // AC1 / AC5 — sentiment gate renders first
  // ---------------------------------------------------------------------------

  group('sentiment gate', () {
    testWidgets('renders the neutral gate question first — no review buttons '
        'visible until answered (AC1)', (tester) async {
      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );

      // Neutral question + internal-feedback declaration are visible.
      expect(find.text(l10n.reviewPromptTitle), findsOneWidget);
      expect(find.text(l10n.reviewPromptGateBody), findsOneWidget);
      // The two sentiment answers are present.
      expect(find.text(l10n.reviewPromptGateYes), findsOneWidget);
      expect(find.text(l10n.reviewPromptGateNo), findsOneWidget);

      // No review CTA is reachable yet — they only appear after a positive
      // answer (AC2), so the user is never pushed straight to the store.
      expect(find.text(l10n.reviewPromptRateStore), findsNothing);
      expect(find.text(l10n.reviewPromptStarGitHub), findsNothing);
      expect(find.text(l10n.reviewPromptYes), findsNothing);

      await _dismiss(tester, l10n);
    });

    testWidgets('positive answer reveals the channel-specific review buttons '
        '(AC2)', (tester) async {
      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );
      await _answerGateYes(tester, l10n);

      // The gate answers are gone and the review CTAs are now reachable.
      expect(find.text(l10n.reviewPromptGateYes), findsNothing);
      expect(find.text(l10n.reviewPromptGateNo), findsNothing);
      expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
      expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);

      await _dismiss(tester, l10n);
    });

    testWidgets('negative answer navigates to the feedback page — never '
        'launches a store URL (AC3)', (tester) async {
      String? capturedUrl;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcherChannel, (call) async {
            if (call.method == 'canLaunch' || call.method == 'launch') {
              capturedUrl = (call.arguments as Map)['url'] as String?;
            }
            return true;
          });

      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );

      await tester.tap(find.text(l10n.reviewPromptGateNo));
      await tester.pumpAndSettle();

      // Routed to the internal feedback page — not the store.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReviewPromptWatcher)),
      );
      expect(container.read(activePageProvider), 'feedback');
      // No store (or any) URL was launched on the negative path.
      expect(capturedUrl, isNull);
    });

    testWidgets('negative answer snoozes the prompt so it does not re-ask '
        'across sessions (AC4)', (tester) async {
      final notifier = await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );

      await tester.tap(find.text(l10n.reviewPromptGateNo));
      await tester.pumpAndSettle();

      // The SharedPreferences-backed dismiss seam was invoked (non-permanent
      // snooze) and the prompt is no longer surfacing.
      expect(notifier.dismissCalled, isTrue);
      expect(notifier.dismissPermanent, isFalse);
      expect(notifier.state.shouldShowPrompt, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AC2 / AC3 / AC4 — button layout per platform × channel
  // ---------------------------------------------------------------------------

  group('button layout', () {
    testWidgets('macOS/Linux portable (!isWindows): only GitHub star button — '
        'no Rate-on-Store button', (tester) async {
      await _showDialog(
        tester,
        DeployChannel.portable,
        isWindows: false,
        l10n: l10n,
      );
      await _answerGateYes(tester, l10n);

      expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
      expect(find.text(l10n.reviewPromptRateStore), findsNothing);

      await _dismiss(tester, l10n);
    });

    testWidgets(
      'Windows installer (isWindows): both Rate-on-Store and Star-on-GitHub',
      (tester) async {
        await _showDialog(
          tester,
          DeployChannel.installer,
          isWindows: true,
          l10n: l10n,
        );
        await _answerGateYes(tester, l10n);

        expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);

        await _dismiss(tester, l10n);
      },
    );

    testWidgets(
      'Windows portable (isWindows): both Rate-on-Store and Star-on-GitHub',
      (tester) async {
        await _showDialog(
          tester,
          DeployChannel.portable,
          isWindows: true,
          l10n: l10n,
        );
        await _answerGateYes(tester, l10n);

        expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);

        await _dismiss(tester, l10n);
      },
    );

    testWidgets(
      'Windows store: primary Store-Review button plus secondary GitHub-Stern '
      'button (Doppelspur) — AC3',
      (tester) async {
        await _showDialog(
          tester,
          DeployChannel.store,
          isWindows: true,
          l10n: l10n,
        );
        await _answerGateYes(tester, l10n);

        // Primary store-review button (store-channel wording "Loving it!").
        expect(find.text(l10n.reviewPromptYes), findsOneWidget);
        // Secondary GitHub-Stern button next to it (GitHub-Stern-Doppelspur).
        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
        // The portable "Rate on the Store" wording is still NOT used here.
        expect(find.text(l10n.reviewPromptRateStore), findsNothing);

        await _dismiss(tester, l10n);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC1 / AC3 — URL targets
  // ---------------------------------------------------------------------------

  group('URL targets', () {
    late String? capturedUrl;

    setUp(() {
      capturedUrl = null;
      // Replace the simple stub with a capturing version.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcherChannel, (call) async {
            if (call.method == 'canLaunch' || call.method == 'launch') {
              capturedUrl = (call.arguments as Map)['url'] as String?;
            }
            return true;
          });
    });

    testWidgets('Windows non-store Rate-on-Store → Windows Store review URL', (
      tester,
    ) async {
      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );
      await _answerGateYes(tester, l10n);

      await tester.tap(find.text(l10n.reviewPromptRateStore));
      await tester.pumpAndSettle();

      expect(capturedUrl, kWindowsStoreReviewUrl);
    });

    testWidgets(
      'Windows store Yes-button → Windows Store review URL (channel-agnostic)',
      (tester) async {
        await _showDialog(
          tester,
          DeployChannel.store,
          isWindows: true,
          l10n: l10n,
        );
        await _answerGateYes(tester, l10n);

        await tester.tap(find.text(l10n.reviewPromptYes));
        await tester.pumpAndSettle();

        expect(capturedUrl, kWindowsStoreReviewUrl);
      },
    );

    testWidgets('macOS/Linux Star-on-GitHub tap → GitHub repo URL', (
      tester,
    ) async {
      await _showDialog(
        tester,
        DeployChannel.portable,
        isWindows: false,
        l10n: l10n,
      );
      await _answerGateYes(tester, l10n);

      await tester.tap(find.text(l10n.reviewPromptStarGitHub));
      await tester.pumpAndSettle();

      // AC5 — the dialog launches the single-source GitHub URL constant, not a
      // private duplicate.
      expect(capturedUrl, kGitHubRepoUrl);
    });

    testWidgets('no apps.apple.com URL is ever launched — AC1', (tester) async {
      // Verify via the Windows non-store path (the previously broken path).
      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );
      await _answerGateYes(tester, l10n);

      await tester.tap(find.text(l10n.reviewPromptRateStore));
      await tester.pumpAndSettle();

      expect(capturedUrl, isNot(contains('apps.apple.com')));
    });
  });
}
