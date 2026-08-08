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
/// issues/02`) is currently in progress — session state, **never
/// persisted**, for the exact same reason [OnboardingManuallyOpenNotifier]
/// isn't (see its doc comment): a crash, force-quit or closed window
/// mid-run must never be able to leave `onboardingCompleted` in a wrong
/// state, and the only way to guarantee that is to never let "a run is
/// happening" survive past the session that started it. A completed or
/// aborted run stamps `onboardingContentVersion` and clears this flag in the
/// same breath — there is no persisted "run in progress" state to resume.
///
/// Nothing in this repository sets this to `true` yet.
/// `.scratch/onboarding-revisions/issues/03` owns starting a run (once
/// `onboardingRevisionDue` — see `onboarding_revision.dart` — fires) and
/// ending one; this provider is the seam it plugs into. The surface-active
/// predicate below already reads it, so nothing here needs to change once a
/// run can actually start.
class OnboardingRevisionRunNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // loam-ignore: unused-public-exports – the seam for issue 03; no caller exists until that ticket lands.
  void start() => state = true;

  // loam-ignore: unused-public-exports – see start() above.
  void end() => state = false;
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
