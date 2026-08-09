/// Tests for the store thank-you hint.
///
/// Locale content (AC — forbidden word rule):
///   The hint title and body in DE/EN/HE must NOT contain any of:
///   kauf, gekauft, preis, bezahlt, gratis, kostenlos, open source, github.
///   (Case-insensitive. Checked against the generated localizations directly —
///   no Flutter widget pump required.)
///
/// CTA URL sourcing (AC — single-source constants):
///   Verifies [kWindowsStoreReviewUrl] is the MS-Store deep-link and
///   [kGitHubRepoUrl] is the WhisPaste GitHub repo — both used verbatim in
///   the watcher without hardcoded literals.
///
/// Button layout per platform (AC — mirrors the review prompt dialog):
///   Windows: Store-review CTA + GitHub-star CTA.
///   macOS/Linux: only the GitHub-star CTA — no store review deep-link
///   exists for those platforms, so no Store CTA (and no
///   [kWindowsStoreReviewUrl] launch) may be reachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/app_urls.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_he.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/services/store_thank_you_service.dart';
import 'package:whispaste/widgets/store_thank_you_dialog.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifier
// ---------------------------------------------------------------------------

/// Stub that lets tests drive [StoreThankYouState.shouldShow] without touching
/// SharedPreferences, the deploy channel, or the history database.
class _FakeStoreThankYouNotifier extends StoreThankYouNotifier {
  @override
  Future<void> checkAndMaybeShow({required bool onboardingCompleted}) async {}

  /// Flips [StoreThankYouState.shouldShow] to `true` so
  /// [WpStoreThankYouWatcher]'s listener fires and starts the 2-second delay.
  void triggerShow() => state = const StoreThankYouState(shouldShow: true);

  @override
  Future<void> markShown() async =>
      state = const StoreThankYouState(shouldShow: false);
}

/// Stands in for a user with an onboarding revision run in progress.
class _RunningRevisionNotifier extends OnboardingRevisionRunNotifier {
  @override
  bool build() => true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

/// Pumps [WpStoreThankYouWatcher] and advances time past the 2-second delay so
/// the dialog is fully visible and animated in.
Future<void> _showDialog(WidgetTester tester, {required bool isWindows}) async {
  storeThankYouPlatformIsWindowsOverride = isWindows;
  final notifier = _FakeStoreThankYouNotifier();

  await tester.pumpWidget(
    makeTestable(
      const WpStoreThankYouWatcher(child: SizedBox()),
      locale: const Locale('en'),
      overrides: [storeThankYouProvider.overrideWith(() => notifier)],
    ),
  );
  await tester.pump(); // initial build, ref.listen registered

  notifier.triggerShow();
  await tester.pump(); // state change propagated, delay timer started
  await tester.pump(const Duration(seconds: 2)); // timer fires → _showDialog()
  await tester.pumpAndSettle(); // showGeneralDialog + animation
}

/// Taps the dismiss button to cleanly close the dialog so the test ends
/// without leaked timers or pending futures.
Future<void> _dismiss(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.text(l10n.storeThankYouDismiss));
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------------------------
  // Locale content assertions — pure (no Flutter widgets needed)
  // ---------------------------------------------------------------------------

  group('storeThankYou locale strings — forbidden word check', () {
    /// Words that MUST NOT appear in the hint title or body text (any locale).
    ///
    /// Rationale:
    ///   - kauf/gekauft/preis/bezahlt: refund-protection — must not imply the
    ///     user paid or refer to a purchase transaction.
    ///   - gratis/kostenlos/open source/github: must not mention the free /
    ///     open-source alternative and thereby hint at refund eligibility.
    const forbidden = [
      'kauf',
      'gekauft',
      'preis',
      'bezahlt',
      'gratis',
      'kostenlos',
      'open source',
      'github',
    ];

    final locales = [L10nDe(), L10nEn(), L10nHe()];

    for (final l10n in locales) {
      test('${l10n.localeName}: storeThankYouTitle + storeThankYouBody '
          'contain no forbidden words', () {
        final text = '${l10n.storeThankYouTitle} ${l10n.storeThankYouBody}'
            .toLowerCase();

        for (final word in forbidden) {
          expect(
            text.contains(word),
            isFalse,
            reason:
                'Locale "${l10n.localeName}" contains forbidden word '
                '"$word" in storeThankYouTitle / storeThankYouBody. '
                'Full text: "$text"',
          );
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // CTA URL sourcing — single-source constants (no hardcoded literals)
  // ---------------------------------------------------------------------------

  group('storeThankYou CTA URL constants', () {
    test(
      'kWindowsStoreReviewUrl is the MS Store review deep-link (store CTA source)',
      () {
        expect(kWindowsStoreReviewUrl, startsWith('ms-windows-store://'));
        expect(kWindowsStoreReviewUrl, contains('ProductId='));
      },
    );

    test(
      'kGitHubRepoUrl is the WhisPaste GitHub repo (GitHub star CTA source)',
      () {
        expect(kGitHubRepoUrl, startsWith('https://github.com/'));
        expect(kGitHubRepoUrl, contains('whispaste'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Button layout per platform — widget tests
  // ---------------------------------------------------------------------------

  group('button layout per platform', () {
    late L10n l10n;
    late String? capturedUrl;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    setUp(() {
      storeThankYouPlatformIsWindowsOverride = null;
      SharedPreferences.setMockInitialValues({});
      capturedUrl = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcherChannel, (call) async {
            if (call.method == 'canLaunch' || call.method == 'launch') {
              capturedUrl = (call.arguments as Map)['url'] as String?;
            }
            return true;
          });
    });

    tearDown(() {
      storeThankYouPlatformIsWindowsOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcherChannel, null);
    });

    testWidgets('Windows: both Store-review and GitHub-star CTAs', (
      tester,
    ) async {
      await _showDialog(tester, isWindows: true);

      expect(find.text(l10n.storeThankYouCtaStore), findsOneWidget);
      expect(find.text(l10n.storeThankYouCtaGitHub), findsOneWidget);

      await _dismiss(tester, l10n);
    });

    testWidgets('macOS/Linux (!isWindows): only GitHub-star CTA — no '
        'Store-review button', (tester) async {
      await _showDialog(tester, isWindows: false);

      expect(find.text(l10n.storeThankYouCtaGitHub), findsOneWidget);
      expect(find.text(l10n.storeThankYouCtaStore), findsNothing);

      await _dismiss(tester, l10n);
    });

    testWidgets('Windows Store-review tap → Windows Store review URL', (
      tester,
    ) async {
      await _showDialog(tester, isWindows: true);

      await tester.tap(find.text(l10n.storeThankYouCtaStore));
      await tester.pumpAndSettle();

      expect(capturedUrl, kWindowsStoreReviewUrl);
    });

    testWidgets('macOS/Linux GitHub-star tap → GitHub repo URL — never the '
        'Windows Store URL', (tester) async {
      await _showDialog(tester, isWindows: false);

      await tester.tap(find.text(l10n.storeThankYouCtaGitHub));
      await tester.pumpAndSettle();

      expect(capturedUrl, kGitHubRepoUrl);
    });
  });

  // ---------------------------------------------------------------------------
  // Show-time re-check — widget test
  // ---------------------------------------------------------------------------

  group('show-time re-check', () {
    setUp(() {
      storeThankYouPlatformIsWindowsOverride = null;
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      storeThankYouPlatformIsWindowsOverride = null;
    });

    testWidgets(
      'suppressed if an onboarding revision run starts between check time '
      'and the two-second show delay',
      (tester) async {
        storeThankYouPlatformIsWindowsOverride = false;
        final notifier = _FakeStoreThankYouNotifier();

        await tester.pumpWidget(
          makeTestable(
            const WpStoreThankYouWatcher(child: SizedBox()),
            locale: const Locale('en'),
            overrides: [
              storeThankYouProvider.overrideWith(() => notifier),
              onboardingRevisionRunProvider.overrideWith(
                () => _RunningRevisionNotifier(),
              ),
            ],
          ),
        );
        await tester.pump(); // initial build, ref.listen registered

        notifier.triggerShow();
        await tester.pump(); // state change propagated, delay timer started
        await tester.pump(const Duration(seconds: 2)); // delay elapses
        await tester.pumpAndSettle();

        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          find.text(l10n.storeThankYouCtaGitHub),
          findsNothing,
          reason:
              'The re-check in _maybeShow must catch a revision run that '
              'started after the notifier already decided to show.',
        );
      },
    );
  });
}
