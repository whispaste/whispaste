/// End-to-end tests for the onboarding revision run —
/// `.scratch/onboarding-revisions/issues/03`, the counterpart to
/// `onboarding_flow_test.dart`'s first-run walkthrough and
/// `onboarding_review_test.dart`'s manually reopened review.
///
/// A revision run shares almost all of a review's shape (same steps, always
/// starts at page 1, never re-writes `onboardingCompleted`) but differs in
/// what its ending does: both reaching the last step and the visible exit
/// ticket 04 will build stamp `onboardingContentVersion` via
/// [OnboardingRevisionRunNotifier.complete] — a review never touches that
/// field at all, because a review only ever opens on a user who is already
/// caught up.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart'
    show kOnboardingFlowVersion;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

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

/// A bestandsuser two versions behind the target, exactly the shape
/// `onboardingRevisionDue` requires: onboarding long completed, seen content
/// version below target, flow version current (so no unrelated legacy-index
/// migration fires and confuses the assertions below).
AppSettings _staleUser({int seenContentVersion = 1}) =>
    AppSettings.defaults.copyWithSections(
      onboarding: OnboardingSettings(
        onboardingCompleted: true,
        onboardingFlowVersion: kOnboardingFlowVersion,
        onboardingContentVersion: seenContentVersion,
      ),
    );

OnboardingRevisionEntry _entry(int version) => OnboardingRevisionEntry(
  version: version,
  reason: (l10n) => 'reason $version',
);

Future<_FakeSettingsNotifier> _pumpRevisionRun(
  WidgetTester tester, {
  AppSettings? settings,
  OnboardingRevisionRegistry registry = const [],
}) async {
  final notifier = _FakeSettingsNotifier(settings ?? _staleUser());
  await tester.pumpWidget(
    makeTestable(
      const OnboardingOverlay(revisionRun: true),
      size: const Size(1280, 1600),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => notifier),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        onboardingRevisionRegistryProvider.overrideWithValue(registry),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(kOnboardingNextButtonKey));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
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
          expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
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
          await _tapNext(tester);
          await _tapNext(tester);

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

          await _tapNext(tester);

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
          for (var i = 0; i < 5; i++) {
            await _tapNext(tester);
          }

          expect(find.text(l10n.onboardingStepOf(6, 6)), findsOneWidget);
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

          for (var i = 0; i < 5; i++) {
            await _tapNext(tester);
          }
          await _tapNext(tester); // completion tap

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
          for (var i = 0; i < 6; i++) {
            await _tapNext(tester);
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

  group('Revision run — abort', () {
    testWidgets(
      'aborting mid-flow (simulated here by invoking complete() directly, '
      'exactly as ticket 04\'s exit button will) stamps the target version, '
      'resets the step position, and is not offered again',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpRevisionRun(
            tester,
            registry: [_entry(1), _entry(2)],
          );

          // Reach page 3 — a genuinely mid-flow abort, not one from page 1.
          await _tapNext(tester);
          await _tapNext(tester);

          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingOverlay)),
          );
          await container
              .read(onboardingRevisionRunProvider.notifier)
              .complete();

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
