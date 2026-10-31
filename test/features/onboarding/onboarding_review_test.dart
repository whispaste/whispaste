/// Tests for the manually reopened introduction — `internal-notes
/// onboarding-revisions/issues/07`, reduced to its manual-reopen path.
///
/// The flow itself is the same seven-page shell the first run gets (that is
/// the point: one flow, prefilled from live settings). What is tested here is
/// everything that differs, and every one of those differences is a promise
/// about what a review is *not* allowed to do:
///  - it starts at page 1, never at a persisted resume position, and never
///    writes one;
///  - it carries a visible exit on every platform, including macOS, where the
///    first run deliberately has none;
///  - its way out — the X and the last page's action alike — never touches
///    `onboardingCompleted`, only the ephemeral session flag;
///  - its last page is reachable without a fresh test recording, because the
///    two completion gates guard the first run, not a returning user reading
///    a page;
///  - the Settings entry that opens it exists only for a finished setup.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test_doubles.dart';

import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart'
    show kOnboardingFlowVersion;
import 'package:whispaste/features/help/help_page.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/settings/sections/onboarding_review_section.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/onboarding_telemetry.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;

late L10n l10n;

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults,
      initial = settings ?? AppSettings.defaults;

  AppSettings _settings;

  /// The stored state the review opened on.
  final AppSettings initial;

  /// The writes that touched the first run's durable record: its resume
  /// position or its completion flag. Pages may still store their own
  /// answers (the about page saves name and role) during a review.
  List<AppSettings> get flowWrites => [
    for (final w in writes)
      if (w.onboarding.onboardingCurrentStep !=
              initial.onboarding.onboardingCurrentStep ||
          w.onboarding.onboardingCompleted !=
              initial.onboarding.onboardingCompleted)
        w,
  ];

  /// Every write the overlay asked for, in order. A review's whole contract
  /// is about writes that must not happen, so the assertions need the list
  /// itself, not just the resulting values.
  final List<AppSettings> writes = [];

  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    writes.add(_settings);
    state = AsyncData(_settings);
  }
}

/// Keeps the microphone status off the real platform channel, which in a test
/// binding leaves the Try & Go chip in a state it is not laid out for. Same
/// stand-in the overlay's own suite uses.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Statically resolved — never the real notifier. `ModelStep._detectHardware`
/// awaits `awaitInitialScan()`, and the real notifier's initial scan is real
/// `Directory`/`File` I/O, which never resolves under `testWidgets` (see the
/// override in `onboarding_overlay_test.dart`, which this mirrors).
class _StaticWhisperDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

class _StaticParakeetDownload extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();
}

/// Settings of someone who finished setup a long time ago and got half-way
/// through the flow once, back when they did.
///
/// Carries an already-generated `cohortPseudonymSalt`, as any real returning
/// user with usage stats on would by now (`telemetryProvider` backfills it
/// lazily on first dispatch) — without it, the very first `_trackStep` call
/// in these tests triggers that one-time backfill write itself, which has
/// nothing to do with the review flow under test and would corrupt the
/// "review touches no settings" assertions below.
AppSettings _returningUser() => AppSettings.defaults.copyWithSections(
  onboarding: const OnboardingSettings(
    onboardingCompleted: true,
    onboardingCurrentStep: 3,
    onboardingFlowVersion: kOnboardingFlowVersion,
  ),
  privacy: const PrivacySettings(cohortPseudonymSalt: 'test-cohort-salt'),
);

Future<_FakeSettingsNotifier> _pumpReview(
  WidgetTester tester, {
  bool manualReview = true,
  AppSettings? settings,
  Locale locale = const Locale('en'),
  OnboardingTelemetry? telemetry,
}) async {
  final notifier = _FakeSettingsNotifier(settings ?? _returningUser());
  await tester.pumpWidget(
    makeTestable(
      disableAnimations: true,
      OnboardingOverlay(manualReview: manualReview),
      locale: locale,
      overrides: [
        onboardingMicProbeProvider.overrideWithValue(OnboardingFakeMicProbe()),
        audioInputDevicesProvider.overrideWith(
          (ref) async => const ['Default'],
        ),
        settingsProvider.overrideWith(() => notifier),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        modelDownloadProvider.overrideWith(_StaticWhisperDownload.new),
        parakeetDownloadProvider.overrideWith(_StaticParakeetDownload.new),
        if (telemetry != null)
          onboardingTelemetryProvider.overrideWithValue(telemetry),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

/// Reads the ephemeral session flag out of the tree the overlay is mounted
/// in — the flag is what "the review is open" actually means.
bool _reviewOpen(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(OnboardingOverlay)),
).read(onboardingManuallyOpenProvider);

/// Opens the Help hub on the introduction tab, the way a settings deep link does.
class _IntroTarget extends HelpTargetNotifier {
  @override
  HelpTarget? build() => const HelpTarget(tab: HelpTab.intro);
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Real Inter metrics. With the default square-glyph test font every
    // string is roughly twice as wide as it ships, which makes the Try & Go
    // page's chips report overflows the app never has.
    await loadAppFonts();
  });

  group('the reopened introduction — position', () {
    testWidgets(
      'starts at page 1 even though a resume position is persisted, and '
      'paging through it never writes one',
      (tester) async {
        final settings = await _pumpReview(tester);

        final steps = buildOnboardingStepIds();
        expect(
          onboardingPage(steps[0]),
          findsOneWidget,
          reason:
              'The persisted step 3 belongs to an interrupted first run; a '
              'review has no position of its own to resume.',
        );

        await tapOnboardingNext(tester);
        await tapOnboardingNext(tester);
        expect(onboardingPage(steps[2]), findsOneWidget);
        expect(
          settings.flowWrites,
          isEmpty,
          reason:
              'Paging through a review must leave the interrupted first '
              "run's position exactly where it was.",
        );
        expect(settings.current.onboarding.onboardingCurrentStep, 3);
      },
    );
  });

  group('the reopened introduction — the visible exit', () {
    testWidgets('renders on macOS, where the first run deliberately has none', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpReview(tester, manualReview: false);
        expect(
          find.byKey(kOnboardingReviewExitButtonKey),
          findsNothing,
          reason:
              'During the first run on macOS the X would duplicate the '
              'native traffic lights — and closing means quitting there.',
        );

        // Both reading directions: the traffic lights stay in the physical
        // top-left corner in Hebrew too, so a *logical* placement would put
        // the X straight on top of them there.
        for (final locale in const [Locale('en'), Locale('he')]) {
          await _pumpReview(tester, locale: locale);
          final exit = find.byKey(kOnboardingReviewExitButtonKey);
          expect(exit, findsOneWidget);
          expect(
            tester.getCenter(exit).dx,
            greaterThan(
              tester.getSize(find.byType(OnboardingOverlay)).width / 2,
            ),
            reason:
                'The X must sit at the physical right in ${locale.languageCode}: '
                'the physical left is where macOS draws the native traffic '
                'lights under TitleBarStyle.hidden.',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ends the review and leaves onboardingCompleted alone', (
      tester,
    ) async {
      final settings = await _pumpReview(tester);
      expect(_reviewOpen(tester), isFalse); // never opened in this harness

      // Open it the way Settings does, so the exit has something to undo.
      ProviderScope.containerOf(
        tester.element(find.byType(OnboardingOverlay)),
      ).read(onboardingManuallyOpenProvider.notifier).open();
      await tester.pump();
      expect(_reviewOpen(tester), isTrue);

      await tester.tap(find.byKey(kOnboardingReviewExitButtonKey));
      await tester.pumpAndSettle();

      expect(_reviewOpen(tester), isFalse);
      expect(
        settings.writes,
        isEmpty,
        reason:
            'The exit is a session-flag flip and nothing else — a review '
            'must be incapable of writing onboardingCompleted, which is '
            'the only durable record that this user ever set the app up.',
      );
      expect(settings.current.onboarding.onboardingCompleted, isTrue);
    });

    testWidgets('a review reports review actions only, never the funnel', (
      tester,
    ) async {
      final actions = <String>[];
      await _pumpReview(
        tester,
        telemetry: OnboardingTelemetry(
          track: ({required category, required action, name}) =>
              actions.add(action),
          decide: ({required shareUsageStats}) {},
        ),
      );
      await tapOnboardingNext(tester);
      await tester.tap(find.byKey(kOnboardingReviewExitButtonKey));
      await tester.pumpAndSettle();

      expect(actions, ['review_step', 'review_step', 'review_exit']);
    });
  });

  group('the reopened introduction — the last page', () {
    testWidgets(
      'its action is enabled without a fresh test recording and behaves like '
      'the exit',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final settings = await _pumpReview(tester);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingOverlay)),
          );
          container.read(onboardingManuallyOpenProvider.notifier).open();
          await tester.pump();

          final total = buildOnboardingStepIds().length;
          for (var page = 2; page <= total; page++) {
            await tapOnboardingNext(tester);
          }
          expect(onboardingPage(OnboardingStepId.privacy), findsOneWidget);

          final cta = tester.widget<WpHeroButton>(
            find.byKey(kOnboardingNextButtonKey),
          );
          expect(
            cta.label,
            l10n.onboardingReviewDone,
            reason: 'Nothing is being started here — it is being finished.',
          );
          expect(
            cta.onPressed,
            isNotNull,
            reason:
                'The completion gates guard a first run from ending in a '
                'half-configured app; a review opens on one that works.',
          );

          await tapOnboardingNext(tester);
          expect(container.read(onboardingManuallyOpenProvider), isFalse);
          expect(settings.flowWrites, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('the Help entry', () {
    testWidgets('is absent until the first-run setup is finished', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          disableAnimations: true,
          const HelpPage(),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(AppSettings.defaults),
            ),
            helpTargetProvider.overrideWith(_IntroTarget.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The section is in the tree but renders nothing until setup is done.
      expect(find.text(l10n.onboardingReviewAction), findsNothing);
    });

    testWidgets(
      'opens the review on the Help page for a user who finished setup',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            disableAnimations: true,
            const HelpPage(),
            locale: const Locale('en'),
            overrides: [
              settingsProvider.overrideWith(
                () => _FakeSettingsNotifier(_returningUser()),
              ),
              helpTargetProvider.overrideWith(_IntroTarget.new),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final section = find.byType(OnboardingReviewSection);
        expect(section, findsOneWidget);

        final action = find.descendant(
          of: section,
          matching: find.text(l10n.onboardingReviewAction),
        );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();

        expect(
          ProviderScope.containerOf(
            tester.element(find.byType(HelpPage)),
          ).read(onboardingManuallyOpenProvider),
          isTrue,
        );
      },
    );
  });

  group('onboardingSurfaceActive', () {
    test('is true during the first run and false once it is done', () {
      expect(
        onboardingSurfaceActive(
          onboardingCompleted: false,
          manuallyOpen: false,
        ),
        isTrue,
      );
      expect(
        onboardingSurfaceActive(onboardingCompleted: true, manuallyOpen: false),
        isFalse,
      );
    });

    test('is true again while a finished user has the flow reopened', () {
      expect(
        onboardingSurfaceActive(onboardingCompleted: true, manuallyOpen: true),
        isTrue,
      );
    });

    test('is true while an onboarding revision run is in progress, even though '
        'onboarding is long completed and no manual reopen is happening', () {
      expect(
        onboardingSurfaceActive(
          onboardingCompleted: true,
          manuallyOpen: false,
          revisionRunning: true,
        ),
        isTrue,
      );
    });
  });
}
