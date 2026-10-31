/// End-to-end tests for the onboarding revision run —
/// `internal-notes` (the run itself) and `/04` (the
/// update notice on step 1 and the visible exit), the counterpart to
/// `onboarding_flow_test.dart`'s first-run walkthrough and
/// `onboarding_review_test.dart`'s manually reopened review.
///
/// A revision run shares almost all of a review's shape (same steps, always
/// starts at page 1, never re-writes `onboardingCompleted`) but differs in
/// what its ending does: both reaching the last step and the visible exit
/// stamp `onboardingContentVersion` via `OnboardingRevisionRunNotifier`'s
/// `complete()` — a review never touches that field at all, because a review
/// only ever opens on a user who is already caught up.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, ProviderScope;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/onboarding/steps/privacy_step.dart'
    show kPrivacyStepCrashToggleKey, kPrivacyStepUsageToggleKey;

import 'onboarding_test_doubles.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart'
    show kOnboardingFlowVersion;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;

late L10n l10n;

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(AppSettings initial) : _settings = initial;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Never resolves the real platform channel — the automatic mic request on
/// leaving page 1 must not fire during a revision run at all (see the test
/// below), but the checker still has to exist for [WelcomeStep] to mount.
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

/// A bestandsuser two versions behind the target, exactly the shape
/// `onboardingRevisionDue` requires: onboarding long completed, seen content
/// version below target, flow version current (so no unrelated legacy-index
/// migration fires and confuses the assertions below).
///
/// Carries an already-generated `cohortPseudonymSalt`, as any real
/// long-completed user with usage stats on would by now (`telemetryProvider`
/// backfills it lazily on first dispatch) — without it, the very first
/// `_trackStep` call in these tests triggers that one-time backfill write
/// itself, which has nothing to do with the revision run under test and
/// would break the "every other setting untouched" assertions below.
AppSettings _staleUser({int seenContentVersion = 1}) =>
    AppSettings.defaults.copyWithSections(
      onboarding: OnboardingSettings(
        onboardingCompleted: true,
        onboardingFlowVersion: kOnboardingFlowVersion,
        onboardingContentVersion: seenContentVersion,
      ),
      privacy: const PrivacySettings(cohortPseudonymSalt: 'test-cohort-salt'),
    );

OnboardingRevisionEntry _entry(int version) => OnboardingRevisionEntry(
  version: version,
  reason: (l10n) => 'reason $version',
);

/// A reason of the shape a real registry entry carries: a full sentence, at
/// the length German tends to produce.
///
/// [_entry]'s `'reason 2'` is fine for the stamping tests, but it would make
/// every layout assertion below meaningless — the notice strip is bounded at
/// two lines, and only text that actually fills those two lines measures the
/// height the fixed window has to absorb. German for every locale on
/// purpose: it is the worst case, and a registry entry's text is not
/// something the *locale* of the test gets to make shorter.
OnboardingRevisionEntry _wordyEntry(int version) => OnboardingRevisionEntry(
  version: version,
  reason: (l10n) =>
      'Neuerung $version: Die Modell-Auswahl enthält jetzt ein deutlich '
      'schnelleres Modell für ältere Prozessoren und erklärt genauer, '
      'welches davon zu deiner Hardware passt.',
);

Future<_FakeSettingsNotifier> _pumpRevisionRun(
  WidgetTester tester, {
  AppSettings? settings,
  OnboardingRevisionRegistry registry = const [],
  Locale locale = const Locale('en'),
  Size size = const Size(1280, 1600),
  double textScale = 1.0,
  bool manualReview = false,
  bool revisionRun = true,
}) async {
  final notifier = _FakeSettingsNotifier(settings ?? _staleUser());
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: OnboardingOverlay(
          manualReview: manualReview,
          revisionRun: revisionRun,
        ),
      ),
      size: size,
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
        onboardingRevisionRegistryProvider.overrideWithValue(registry),
        modelDownloadProvider.overrideWith(_StaticWhisperDownload.new),
        parakeetDownloadProvider.overrideWith(_StaticParakeetDownload.new),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

/// The notice strip's full text, ellipsis or not — [Text]'s span is the
/// complete string even when only two lines of it are painted, which is also
/// exactly what assistive technology reads out.
String _noticeText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(kOnboardingRevisionNoticeKey),
        matching: find.byType(Text),
      ),
    )
    .textSpan!
    .toPlainText();

/// Leaves through the visible exit and confirms the one-way-door dialog.
Future<void> _exitAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(kOnboardingRevisionExitButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.onboardingRevisionExitConfirmAction));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    await loadAppFonts();
  });

  group('Revision run — starts fresh, never touches onboardingCompleted', () {
    testWidgets(
      'mounts on step 1 regardless of a leftover, non-zero step position',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpRevisionRun(
            tester,
            settings: _staleUser().copyWithSections(
              onboarding: _staleUser().onboarding.copyWith(
                onboardingCurrentStep: 3,
              ),
            ),
          );

          expect(find.byType(WelcomeStep), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'onboardingCompleted stays true throughout navigation — it is never '
      'the flag a revision run touches',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpRevisionRun(tester);
          await tapOnboardingNext(tester);
          await tapOnboardingNext(tester);

          expect(settings.state.value!.onboarding.onboardingCompleted, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'never requests the microphone permission on leaving page 1, even '
      'when its status is unknown — a revision run shows status, it does '
      'not ask again',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpRevisionRun(tester);
          expect(find.byType(WelcomeStep), findsOneWidget);

          await tapOnboardingNext(tester);

          // The fake checker's check(request: true) would have been the
          // only path to a granted/denied status; staying `unknown` proves
          // request() was never invoked.
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingOverlay)),
          );
          expect(
            container.read(micPermissionNotifierProvider).status,
            MicPermissionStatus.unknown,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('Revision run — completion', () {
    testWidgets(
      'the completion CTA reads "Done", not "Get started", and is enabled '
      'without any test recording — the no-data-loss promise requires a run '
      'with zero user input to be completable',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpRevisionRun(tester);
          final steps = buildOnboardingStepIds();
          for (var i = 1; i < steps.length; i++) {
            await tapOnboardingNext(tester);
          }

          expect(onboardingPage(OnboardingStepId.privacy), findsOneWidget);
          expect(find.text(l10n.onboardingReviewDone), findsOneWidget);
          expect(find.text(l10n.onboardingStartUsing), findsNothing);
          expect(
            tester
                .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
                .onPressed,
            isNotNull,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'a full run with zero other input stamps the target version and '
      'leaves every other setting untouched — the no-data-loss promise',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final initial = _staleUser();
          final settings = await _pumpRevisionRun(
            tester,
            settings: initial,
            registry: [_entry(1), _entry(2)],
          );

          for (var i = 1; i < buildOnboardingStepIds().length; i++) {
            await tapOnboardingNext(tester);
          }
          await tapOnboardingNext(tester); // completion tap

          final after = settings.state.value!.onboarding;
          expect(after.onboardingContentVersion, 2);
          expect(after.onboardingCurrentStep, 0);
          expect(after.onboardingCompleted, isTrue);
          // Every other section is byte-for-byte the same starting point —
          // the registry/step-position/content-version fields are the only
          // ones this run is allowed to move.
          expect(
            settings.state.value!.copyWithSections(
              onboarding: initial.onboarding,
            ),
            initial,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'no revision run is offered on the next mount after completion',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpRevisionRun(
            tester,
            registry: [_entry(1)],
          );
          for (var i = 0; i < 5; i++) {
            await tapOnboardingNext(tester);
          }

          final onboarding = settings.state.value!.onboarding;
          expect(
            onboardingRevisionDue(
              onboardingCompleted: onboarding.onboardingCompleted,
              seenContentVersion: onboarding.onboardingContentVersion,
              targetContentVersion: targetOnboardingContentVersion([
                _entry(1),
              ], currentOnboardingPlatform()),
            ),
            isFalse,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // ===========================================================================
  // Ticket 04 — the update notice on step 1 and the visible exit.
  // ===========================================================================

  group('Revision run — update notice on step 1', () {
    testWidgets(
      'names the update, says the settings are kept, and carries the reason '
      'of every skipped version newest-first — but never a version the user '
      'has already seen',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpRevisionRun(
            tester,
            settings: _staleUser(seenContentVersion: 1),
            registry: [_wordyEntry(1), _wordyEntry(2), _wordyEntry(3)],
          );

          expect(find.byKey(kOnboardingRevisionNoticeKey), findsOneWidget);
          final text = _noticeText(tester);
          expect(text, contains(l10n.onboardingRevisionNoticeTitle));
          expect(text, contains('Neuerung 3'));
          expect(text, contains('Neuerung 2'));
          expect(
            text,
            isNot(contains('Neuerung 1')),
            reason:
                'Version 1 is what this user was stamped with — it is not '
                'news to them.',
          );
          expect(
            text.indexOf('Neuerung 3'),
            lessThan(text.indexOf('Neuerung 2')),
            reason:
                'Newest first: the freshest reason is the one that survives '
                'the strip\'s two-line bound.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('a truncated notice can be expanded to show every reason and '
        'collapsed again (UIA-ONB-12)', (tester) async {
      tester.view.physicalSize = kOnboardingWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpRevisionRun(
          tester,
          settings: _staleUser(seenContentVersion: 0),
          registry: [_wordyEntry(1), _wordyEntry(2), _wordyEntry(3)],
          size: kOnboardingWindowSize,
        );
        Text noticeText() => tester.widget<Text>(
          find.descendant(
            of: find.byKey(kOnboardingRevisionNoticeKey),
            matching: find.byType(Text),
          ),
        );
        expect(noticeText().maxLines, 2);

        await tester.tap(find.byKey(kOnboardingRevisionNoticeToggleKey));
        await tester.pumpAndSettle();
        expect(noticeText().maxLines, isNull);

        await tester.tap(find.byKey(kOnboardingRevisionNoticeToggleKey));
        await tester.pumpAndSettle();
        expect(noticeText().maxLines, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a notice that fits offers no toggle', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpRevisionRun(tester, registry: const []);
        expect(find.byKey(kOnboardingRevisionNoticeKey), findsOneWidget);
        expect(find.byKey(kOnboardingRevisionNoticeToggleKey), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('lives on step 1 only — it explains the run, it is not a '
        'banner the whole flow carries', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpRevisionRun(tester, registry: [_wordyEntry(2)]);
        expect(find.byKey(kOnboardingRevisionNoticeKey), findsOneWidget);

        await tapOnboardingNext(tester);
        expect(find.byKey(kOnboardingRevisionNoticeKey), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'is absent in the first run and in a review — step 1 keeps its claim '
      'line there, unchanged',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          for (final mode in [
            (revisionRun: false, manualReview: false, name: 'first run'),
            (revisionRun: false, manualReview: true, name: 'review'),
          ]) {
            await _pumpRevisionRun(
              tester,
              registry: [_wordyEntry(2)],
              revisionRun: mode.revisionRun,
              manualReview: mode.manualReview,
            );

            expect(
              find.byKey(kOnboardingRevisionNoticeKey),
              findsNothing,
              reason: 'no update notice in a ${mode.name}',
            );
            expect(
              find.byType(WelcomeStep),
              findsOneWidget,
              reason: 'page 1 is the start page in a ${mode.name}',
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'neither asks for nor implies telemetry consent: the notice says '
      'nothing about it, and the done page shows the choice this user already made '
      '(CONTEXT.md §6.5)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          // A user who opted out of usage stats and *into* crash reports —
          // two different values, so a run that silently normalised either
          // one cannot pass by accident.
          final initial = _staleUser().copyWithSections(
            privacy: _staleUser().privacy.copyWith(shareUsageStats: false),
          );
          final settings = await _pumpRevisionRun(
            tester,
            settings: initial.copyWith(errorReporting: true),
            registry: [_wordyEntry(2)],
          );

          final notice = _noticeText(tester);
          for (final consentWord in [
            l10n.settingsShareUsageStats,
            l10n.settingsErrorReporting,
          ]) {
            expect(
              notice,
              isNot(contains(consentWord)),
              reason:
                  'The update notice must not put a consent question in the '
                  'user\'s way.',
            );
          }

          // The privacy switches live on the last page, not on step 2.
          for (var i = 1; i < buildOnboardingStepIds().length; i++) {
            await tapOnboardingNext(tester);
          }

          Switch toggle(Key key) => tester.widget<Switch>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Switch),
              matchRoot: true,
            ),
          );
          expect(
            toggle(kPrivacyStepCrashToggleKey).value,
            isTrue,
            reason: 'The privacy page shows the stored crash-report choice.',
          );
          expect(
            toggle(kPrivacyStepUsageToggleKey).value,
            isFalse,
            reason: 'The privacy page shows the stored usage choice.',
          );
          expect(settings.state.value!.privacy.shareUsageStats, isFalse);
          expect(settings.state.value!.errorReporting, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('Revision run — the visible exit', () {
    testWidgets('is reachable on every step of the run', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpRevisionRun(tester, registry: [_wordyEntry(2)]);

        final steps = buildOnboardingStepIds();
        for (var page = 1; page <= steps.length; page++) {
          if (page > 1) await tapOnboardingNext(tester);
          expect(onboardingPage(steps[page - 1]), findsOneWidget);
          expect(
            find.byKey(kOnboardingRevisionExitButtonKey),
            findsOneWidget,
            reason: 'the exit is missing on page $page',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not exist in the first run or in a review — both have '
        'their own ending', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        for (final manualReview in [false, true]) {
          await _pumpRevisionRun(
            tester,
            registry: [_wordyEntry(2)],
            revisionRun: false,
            manualReview: manualReview,
          );
          expect(
            find.byKey(kOnboardingRevisionExitButtonKey),
            findsNothing,
            reason: 'manualReview: $manualReview',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'ends flush against the strip on macOS, where no X follows it — on the '
      'same line the review\'s X sits on',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpRevisionRun(tester, registry: [_wordyEntry(2)]);
          final exit = find.byKey(kOnboardingRevisionExitButtonKey);
          // The nearest Row ancestor is the top bar itself — [WpButton]'s own
          // Rows are descendants of the keyed widget, not above it.
          final strip = find
              .ancestor(of: exit, matching: find.byType(Row))
              .first;
          expect(
            find.byKey(kOnboardingReviewExitButtonKey),
            findsNothing,
            reason:
                'macOS draws no X here, so the exit button is the strip\'s '
                'last child — the premise of the alignment below.',
          );
          final revisionEdge = tester.getTopRight(exit).dx;
          expect(
            revisionEdge,
            tester.getTopRight(strip).dx,
            reason:
                'The separator before the X must not outlive the X: as an '
                'unconditional trailing child it left the exit button 4 px '
                'short of the edge it is supposed to end on.',
          );

          // Same strip, other mode: the review's X is the reference edge, and
          // the two modes must not disagree about where the strip ends.
          await _pumpRevisionRun(
            tester,
            registry: [_wordyEntry(2)],
            revisionRun: false,
            manualReview: true,
          );
          expect(
            tester.getTopRight(find.byKey(kOnboardingReviewExitButtonKey)).dx,
            revisionEdge,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'states what stays unconfigured and where to catch it up before it '
      'closes the one-way door',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpRevisionRun(tester, registry: [_wordyEntry(2)]);
          await tester.tap(find.byKey(kOnboardingRevisionExitButtonKey));
          await tester.pumpAndSettle();

          expect(
            find.text(l10n.onboardingRevisionExitConfirmTitle),
            findsOneWidget,
          );
          expect(
            find.text(l10n.onboardingRevisionExitConfirmBody),
            findsOneWidget,
          );
          // The catch-up address is not decoration — it names the Help page
          // entry that reopens exactly these steps (WP-65 moved it there).
          expect(
            l10n.onboardingRevisionExitConfirmBody,
            contains(l10n.onboardingReviewLabel),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'dismissing the confirmation changes nothing — same step, nothing '
      'stamped',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpRevisionRun(
            tester,
            registry: [_wordyEntry(2)],
          );
          await tapOnboardingNext(tester);
          await tapOnboardingNext(tester);

          await tester.tap(find.byKey(kOnboardingRevisionExitButtonKey));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(
              MaterialLocalizations.of(
                tester.element(find.byType(OnboardingOverlay)),
              ).cancelButtonLabel,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            onboardingPage(buildOnboardingStepIds()[2]),
            findsOneWidget,
            reason: 'two Next taps from the start land on the third page',
          );
          expect(settings.state.value!.onboarding.onboardingContentVersion, 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('Revision run — abort', () {
    testWidgets(
      'aborting mid-flow through the visible exit stamps the target version, '
      'resets the step position, and is not offered again',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpRevisionRun(
            tester,
            registry: [_entry(1), _entry(2)],
          );

          // Reach page 3 — a genuinely mid-flow abort, not one from page 1.
          await tapOnboardingNext(tester);
          await tapOnboardingNext(tester);

          await _exitAndConfirm(tester);

          final onboarding = settings.state.value!.onboarding;
          expect(onboarding.onboardingContentVersion, 2);
          expect(onboarding.onboardingCurrentStep, 0);
          expect(
            onboarding.onboardingCompleted,
            isTrue,
            reason: 'An abort must not touch the narrower flag either.',
          );
          expect(
            onboardingRevisionDue(
              onboardingCompleted: onboarding.onboardingCompleted,
              seenContentVersion: onboarding.onboardingContentVersion,
              targetContentVersion: targetOnboardingContentVersion([
                _entry(1),
                _entry(2),
              ], currentOnboardingPlatform()),
            ),
            isFalse,
            reason:
                'A revision run is offered at most once per version, '
                'whichever way it ends.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
