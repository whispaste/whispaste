/// The one place that answers "is the onboarding surface currently on top?".
///
/// `AppSettings.onboarding.onboardingCompleted` used to answer two different
/// questions at once: *has this user ever finished the first-run setup?* and
/// *is the onboarding flow currently covering the app, so please keep
/// competing dialogs away?* The two came apart the moment the five-step flow
/// became reopenable from Settings — a returning user has completed
/// onboarding **and** can have the flow on screen.
///
/// This library owns the second question. The flag keeps the first, narrower
/// one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import 'onboarding_revision.dart';

/// Whether the five-step onboarding flow is currently in front of the app —
/// for any of the three reasons it can be: first-run onboarding is still in
/// progress, the introduction was manually reopened from Settings, or an
/// onboarding revision run (`.scratch/onboarding-revisions/issues/02`) is in
/// progress.
///
/// Pure function so the surfaces that consult it stay unit-testable without a
/// provider container.
bool onboardingSurfaceActive({
  required bool onboardingCompleted,
  required bool manuallyOpen,
  bool revisionRunning = false,
}) => !onboardingCompleted || manuallyOpen || revisionRunning;

/// Whether the user reopened the introduction from Settings — session state,
/// **never persisted**.
///
/// That is a correctness requirement, not a shortcut. The only durable record
/// of "this user set the app up" is `onboardingCompleted`, and a manually
/// reopened review must not be able to touch it: a crash, a force-quit or a
/// closed window halfway through a review would otherwise be able to leave a
/// long-standing user marked as never-set-up and drop them into the first-run
/// flow on the next launch. A flag that only lives in memory cannot survive
/// long enough to do that — the worst a crash can do is end the review.
class OnboardingManuallyOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Opens the review. Called from the Settings entry only.
  void open() => state = true;

  /// Leaves the review — the visible exit, the last step's action, and any
  /// other way out all land here.
  void close() => state = false;
}

final onboardingManuallyOpenProvider =
    NotifierProvider<OnboardingManuallyOpenNotifier, bool>(
      OnboardingManuallyOpenNotifier.new,
    );

/// Whether an onboarding revision run (`.scratch/onboarding-revisions/
/// issues/02`, started by `.scratch/onboarding-revisions/issues/03`) is
/// currently in progress — session state, **never persisted**, for the
/// exact same reason [OnboardingManuallyOpenNotifier] isn't (see its doc
/// comment): a crash, force-quit or closed window mid-run must never be
/// able to leave `onboardingCompleted` in a wrong state, and the only way to
/// guarantee that is to never let "a run is happening" survive past the
/// session that started it. [complete] stamps `onboardingContentVersion` and
/// clears this flag in the same breath — there is no persisted "run in
/// progress" state to resume; a run that never reaches [complete] (crash,
/// force-quit, window close — which quits during a revision run exactly as
/// it does during a first run, see `shouldHideToTrayOnClose`) is simply
/// offered again on the next start.
class OnboardingRevisionRunNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Starts a run. Forces the shared step-position field
  /// (`onboardingCurrentStep`) back to zero first — belt-and-suspenders
  /// against a value left over from an interrupted first run, or from a
  /// revision run that didn't end cleanly (crash, force-quit): a revision
  /// run always begins at step one, regardless of what happens to be
  /// stored. That field otherwise belongs entirely to the first-run resume
  /// mechanism (`.scratch/onboarding-redesign/issues/05`); the overlay
  /// neither reads nor writes it again for the rest of a revision run.
  Future<void> start() async {
    state = true;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(onboardingCurrentStep: 0),
          ),
        );
  }

  /// Ends a run — reaching the last step's completion action and the
  /// visible exit (`.scratch/onboarding-revisions/issues/04`) both call this
  /// and nothing else: the PRD treats the two identically ("Abbruch
  /// stempelt ebenfalls"). Stamps the registry's current target version so
  /// this run is never offered again, resets the shared step-position field
  /// back to zero, and clears the flag — in that order, so a failure
  /// between the settings write and the flag clear leaves the run still
  /// "in progress" rather than silently losing the stamp.
  Future<void> complete() async {
    final registry = ref.read(onboardingRevisionRegistryProvider);
    final target = targetOnboardingContentVersion(
      registry,
      currentOnboardingPlatform(),
    );
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(
              onboardingContentVersion: target,
              onboardingCurrentStep: 0,
            ),
          ),
        );
    state = false;
  }
}

final onboardingRevisionRunProvider =
    NotifierProvider<OnboardingRevisionRunNotifier, bool>(
      OnboardingRevisionRunNotifier.new,
    );

/// [onboardingSurfaceActive] wired to live app state.
///
/// Watch this from anything that must stay out of the flow's way; keep
/// reading `onboardingCompleted` directly where the question really is "did
/// this user ever finish setup" (the recording preflight, the readiness
/// provider, the status bar's Auto-Paste-off hint, the factory reset, and the
/// onboarding window geometry).
final onboardingSurfaceActiveProvider = Provider<bool>((ref) {
  final completed = ref.watch(
    settingsProvider.select(
      (s) => s.value?.onboarding.onboardingCompleted ?? false,
    ),
  );
  return onboardingSurfaceActive(
    onboardingCompleted: completed,
    manuallyOpen: ref.watch(onboardingManuallyOpenProvider),
    revisionRunning: ref.watch(onboardingRevisionRunProvider),
  );
});

/// Leaves whichever onboarding surface is currently on top — first-run,
/// manual review, or an onboarding revision run — the same terminal state
/// change each one's own "finish"/"exit" action already makes. A no-op if
/// none of the three is active.
///
/// Needed by anything that lives *behind* the overlay and must make its own
/// navigation actually visible: the final step's test recording
/// (`TestRecordingStep`) runs the real recording pipeline, whose toasts can
/// carry an "Open Settings"/"Open Snippets" action (`recording_behavior.dart`).
/// Those only flip `activePageProvider` — which the overlay, still on top per
/// [onboardingSurfaceActiveProvider], keeps invisible. Calling this first
/// makes the overlay unmount so the requested page is actually seen.
Future<void> leaveOnboardingSurface(WidgetRef ref) async {
  if (ref.read(onboardingManuallyOpenProvider)) {
    ref.read(onboardingManuallyOpenProvider.notifier).close();
    return;
  }
  if (ref.read(onboardingRevisionRunProvider)) {
    await ref.read(onboardingRevisionRunProvider.notifier).complete();
    return;
  }
  final onboarding = ref.read(settingsProvider).value?.onboarding;
  if (onboarding == null || onboarding.onboardingCompleted) return;
  final registry = ref.read(onboardingRevisionRegistryProvider);
  final targetVersion = targetOnboardingContentVersion(
    registry,
    currentOnboardingPlatform(),
  );
  await ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWithSections(
          onboarding: s.onboarding.copyWith(
            onboardingCompleted: true,
            onboardingCurrentStep: 0,
            onboardingContentVersion: targetVersion,
          ),
        ),
      );
}
