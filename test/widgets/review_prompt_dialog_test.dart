/// Widget tests for [WpReviewPromptWatcher] — verifies button layout and URL
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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/prompt_timing.dart';
import 'package:whispaste/services/review_prompt_service.dart';
import 'package:whispaste/services/store_review_request_service.dart';
import 'package:whispaste/widgets/review_prompt_dialog.dart';

import '../fixtures/test_helpers.dart';
import '../test_helpers/nudge_gate_open.dart';

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
  /// that the not-now path invoked it.
  bool dismissCalled = false;
  bool? dismissPermanent;

  @override
  ReviewPromptState build() =>
      ReviewPromptState(shouldShowPrompt: false, channel: _channel);

  /// Flips [shouldShowPrompt] to `true` so [WpReviewPromptWatcher]'s listener
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

  /// Whether the GR-009 store-request cap still has room. Tests set this.
  bool nativeAllowed = true;
  bool nativeRequestMarked = false;

  @override
  Future<bool> nativeRequestAllowed() async => nativeAllowed;

  @override
  Future<void> markNativeRequested() async {
    nativeRequestMarked = true;
    state = state.copyWith(shouldShowPrompt: false);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Pumps [WpReviewPromptWatcher] and advances time past [kPostRecordingPromptDelay]
/// so the dialog is fully visible and animated in.
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
      const WpReviewPromptWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [
        nudgeGateOpenOverride(),
        reviewPromptProvider.overrideWith(() => notifier),
      ],
    ),
  );
  await tester.pump(); // initial build, ref.listen registered

  notifier.triggerShow();
  await tester.pump(); // state change propagated, delay timer started
  await tester.pump(kPostRecordingPromptDelay); // timer fires → _showDialog()
  await tester.pumpAndSettle(); // showGeneralDialog + 300 ms animation

  return notifier;
}

/// Taps "Not now" to cleanly dismiss the dialog so the test ends without
/// leaked timers or pending futures.
Future<void> _dismiss(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.text(l10n.reviewPromptNotNow));
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
    platformIsMacOsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null);
  });

  // ---------------------------------------------------------------------------
  // No sentiment gate — the review options are offered directly
  // ---------------------------------------------------------------------------

  group('direct review options', () {
    testWidgets('shows the review question and the review buttons at once, '
        'with no sentiment question in between', (tester) async {
      await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );

      expect(find.text(l10n.reviewPromptTitle), findsOneWidget);
      expect(find.text(l10n.reviewPromptBody), findsOneWidget);
      expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
      expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
      expect(find.text(l10n.reviewPromptNotNow), findsOneWidget);
      expect(find.text(l10n.reviewPromptNever), findsOneWidget);

      await _dismiss(tester, l10n);
    });

    testWidgets('"not now" snoozes the prompt; no gate step is involved', (
      tester,
    ) async {
      final notifier = await _showDialog(
        tester,
        DeployChannel.installer,
        isWindows: true,
        l10n: l10n,
      );

      await _dismiss(tester, l10n);

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

      expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
      expect(find.text(l10n.reviewPromptRateStore), findsNothing);

      await _dismiss(tester, l10n);
    });

    // UIA-FBK-10: screen readers would speak the star glyphs as "Stern".
    test(
      'the review button labels carry no star glyph in any language (UIA-FBK-10)',
      () {
        for (final lang in ['de', 'en', 'es', 'pt', 'he', 'ru']) {
          final arb =
              jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                  as Map<String, dynamic>;
          for (final key in [
            'reviewPromptStarGitHub',
            'reviewPromptRateStore',
          ]) {
            expect(
              arb[key] as String,
              isNot(matches(RegExp('[\u2605\u2B50]'))),
              reason: '$lang $key',
            );
          }
        }
      },
    );

    testWidgets(
      'Windows installer (isWindows): both Rate-on-Store and Star-on-GitHub',
      (tester) async {
        await _showDialog(
          tester,
          DeployChannel.installer,
          isWindows: true,
          l10n: l10n,
        );

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

        expect(find.text(l10n.reviewPromptRateStore), findsOneWidget);
        expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);

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

      await tester.tap(find.text(l10n.reviewPromptRateStore));
      await tester.pumpAndSettle();

      expect(capturedUrl, kWindowsStoreReviewUrl);
    });

    testWidgets('macOS/Linux Star-on-GitHub tap → GitHub repo URL', (
      tester,
    ) async {
      await _showDialog(
        tester,
        DeployChannel.portable,
        isWindows: false,
        l10n: l10n,
      );

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

      await tester.tap(find.text(l10n.reviewPromptRateStore));
      await tester.pumpAndSettle();

      expect(capturedUrl, isNot(contains('apps.apple.com')));
    });

    // Regression test: the store-channel "Yes" button used to always launch
    // the Windows Store review URL regardless of platform, so a Mac App
    // Store install (channel == store, !isWindows) silently failed to open
    // anything (ms-windows-store:// does not resolve on macOS).
  });

  // ---------------------------------------------------------------------------
  // Mac App Store build: native StoreKit request instead of the own dialog
  // ---------------------------------------------------------------------------

  group('macOS Mac App Store build', () {
    Future<({int calls, _FakeReviewPromptNotifier notifier})> pumpMacStore(
      WidgetTester tester, {
      required NativeReviewOutcome nativeResult,
    }) async {
      platformIsWindowsOverride = false;
      platformIsMacOsOverride = true;
      var calls = 0;
      final notifier = _FakeReviewPromptNotifier(DeployChannel.store);

      await tester.pumpWidget(
        makeTestable(
          const WpReviewPromptWatcher(child: SizedBox()),
          locale: const Locale('en'),
          overrides: [
            nudgeGateOpenOverride(),
            reviewPromptProvider.overrideWith(() => notifier),
            nativeStoreReviewRequestProvider.overrideWithValue(() async {
              calls++;
              return nativeResult;
            }),
          ],
        ),
      );
      await tester.pump();
      notifier.triggerShow();
      await tester.pump();
      await tester.pump(kPostRecordingPromptDelay);
      await tester.pumpAndSettle();
      return (calls: calls, notifier: notifier);
    }

    testWidgets(
      'a due prompt makes one native request and shows no own dialog',
      (tester) async {
        final result = await pumpMacStore(
          tester,
          nativeResult: NativeReviewOutcome.requested,
        );

        expect(result.calls, 1);
        expect(find.text(l10n.reviewPromptTitle), findsNothing);
        expect(result.notifier.state.shouldShowPrompt, isFalse);
        expect(result.notifier.dismissCalled, isFalse);
      },
    );

    testWidgets('a failed native request defers the prompt without a dialog', (
      tester,
    ) async {
      final result = await pumpMacStore(
        tester,
        nativeResult: NativeReviewOutcome.failed,
      );

      expect(result.calls, 1);
      expect(find.text(l10n.reviewPromptTitle), findsNothing);
      expect(result.notifier.state.shouldShowPrompt, isFalse);
      expect(result.notifier.dismissCalled, isFalse);
    });

    testWidgets('the portable macOS build keeps its own GitHub dialog', (
      tester,
    ) async {
      platformIsMacOsOverride = true;
      await _showDialog(
        tester,
        DeployChannel.portable,
        isWindows: false,
        l10n: l10n,
      );

      expect(find.text(l10n.reviewPromptTitle), findsOneWidget);
      await _dismiss(tester, l10n);
    });
  });

  group('Windows Microsoft Store build', () {
    Future<({int calls, _FakeReviewPromptNotifier notifier})> pumpWindowsStore(
      WidgetTester tester, {
      required NativeReviewOutcome nativeResult,
    }) async {
      platformIsWindowsOverride = true;
      platformIsMacOsOverride = false;
      var calls = 0;
      final notifier = _FakeReviewPromptNotifier(DeployChannel.store);

      await tester.pumpWidget(
        makeTestable(
          const WpReviewPromptWatcher(child: SizedBox()),
          locale: const Locale('en'),
          overrides: [
            nudgeGateOpenOverride(),
            reviewPromptProvider.overrideWith(() => notifier),
            nativeStoreReviewRequestProvider.overrideWithValue(() async {
              calls++;
              return nativeResult;
            }),
          ],
        ),
      );
      await tester.pump();
      notifier.triggerShow();
      await tester.pump();
      await tester.pump(kPostRecordingPromptDelay);
      await tester.pumpAndSettle();
      return (calls: calls, notifier: notifier);
    }

    testWidgets(
      'a due prompt makes one native request and shows no own dialog',
      (tester) async {
        final result = await pumpWindowsStore(
          tester,
          nativeResult: NativeReviewOutcome.requested,
        );

        expect(result.calls, 1);
        expect(find.text(l10n.reviewPromptTitle), findsNothing);
        expect(result.notifier.state.shouldShowPrompt, isFalse);
        expect(result.notifier.dismissCalled, isFalse);
      },
    );

    testWidgets('an unavailable native request defers without a dialog', (
      tester,
    ) async {
      final result = await pumpWindowsStore(
        tester,
        nativeResult: NativeReviewOutcome.unavailable,
      );

      expect(result.calls, 1);
      expect(find.text(l10n.reviewPromptTitle), findsNothing);
      expect(result.notifier.state.shouldShowPrompt, isFalse);
      expect(result.notifier.dismissCalled, isFalse);
    });

    testWidgets('a failed Store request defers without a dialog', (
      tester,
    ) async {
      final result = await pumpWindowsStore(
        tester,
        nativeResult: NativeReviewOutcome.failed,
      );

      expect(result.calls, 1);
      expect(find.text(l10n.reviewPromptTitle), findsNothing);
      expect(result.notifier.state.shouldShowPrompt, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // GR-009 — the store request is capped at 3 per 365 days
  // ---------------------------------------------------------------------------

  group('store request cap (GR-009)', () {
    testWidgets('a capped store request makes no native call and no dialog', (
      tester,
    ) async {
      platformIsWindowsOverride = false;
      platformIsMacOsOverride = true;
      var calls = 0;
      final notifier = _FakeReviewPromptNotifier(DeployChannel.store)
        ..nativeAllowed = false;

      await tester.pumpWidget(
        makeTestable(
          const WpReviewPromptWatcher(child: SizedBox()),
          locale: const Locale('en'),
          overrides: [
            nudgeGateOpenOverride(),
            reviewPromptProvider.overrideWith(() => notifier),
            nativeStoreReviewRequestProvider.overrideWithValue(() async {
              calls++;
              return NativeReviewOutcome.requested;
            }),
          ],
        ),
      );
      await tester.pump();
      notifier.triggerShow();
      await tester.pump();
      await tester.pump(kPostRecordingPromptDelay);
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(notifier.nativeRequestMarked, isFalse);
      expect(find.text(l10n.reviewPromptTitle), findsNothing);
      expect(notifier.state.shouldShowPrompt, isFalse);
    });

    testWidgets('an accepted store request is recorded against the cap', (
      tester,
    ) async {
      platformIsWindowsOverride = false;
      platformIsMacOsOverride = true;
      final notifier = _FakeReviewPromptNotifier(DeployChannel.store);

      await tester.pumpWidget(
        makeTestable(
          const WpReviewPromptWatcher(child: SizedBox()),
          locale: const Locale('en'),
          overrides: [
            nudgeGateOpenOverride(),
            reviewPromptProvider.overrideWith(() => notifier),
            nativeStoreReviewRequestProvider.overrideWithValue(
              () async => NativeReviewOutcome.requested,
            ),
          ],
        ),
      );
      await tester.pump();
      notifier.triggerShow();
      await tester.pump();
      await tester.pump(kPostRecordingPromptDelay);
      await tester.pumpAndSettle();

      expect(notifier.nativeRequestMarked, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // GR-011 — Linux never gets a store review request; GitHub star stays
  // ---------------------------------------------------------------------------

  group('Linux (GR-011)', () {
    test('no channel makes a native store request on Linux', () {
      for (final channel in DeployChannel.values) {
        expect(
          usesNativeStoreRequest(
            channel: channel,
            isMacOs: false,
            isWindows: false,
          ),
          isFalse,
          reason: '$channel must not request a store review on Linux',
        );
      }
    });

    test('macOS is the control: its store channel still requests natively', () {
      expect(
        usesNativeStoreRequest(
          channel: DeployChannel.store,
          isMacOs: true,
          isWindows: false,
        ),
        isTrue,
        reason: 'control: the macOS store channel still requests natively',
      );
    });

    testWidgets('a Linux portable prompt offers the GitHub star and no store '
        'rating', (tester) async {
      platformIsMacOsOverride = false;
      await _showDialog(
        tester,
        DeployChannel.portable,
        isWindows: false,
        l10n: l10n,
      );

      expect(find.text(l10n.reviewPromptStarGitHub), findsOneWidget);
      expect(find.text(l10n.reviewPromptRateStore), findsNothing);
      await _dismiss(tester, l10n);
    });
  });
}
