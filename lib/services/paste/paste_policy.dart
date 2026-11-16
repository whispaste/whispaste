import '../../core/config/build_config.dart';
import '../../core/config/settings_enums.dart';
import '../../core/onboarding/onboarding_surface.dart';
import 'paster.dart' show PasteCapabilityStatus;

/// Resolves the effective "after transcription" action for the current build.
///
/// In builds where synthetic-keystroke injection is unavailable — see
/// [kAutoPasteSupported] — any action that would insert the transcript at
/// the cursor is downgraded to [AfterTranscriptionAction.clipboard] so the
/// transcript still lands on the clipboard and the user can paste it
/// manually with ⌘V. On every other platform/build the user's choice is
/// honoured unchanged.
///
/// [kAutoPasteSupported] is `true` on every current build, including the Mac
/// App Store variant — synthetic Unicode/paste keystrokes post via the
/// sandbox-compatible PostEvent TCC service (see `DesktopPasteHost.swift`).
/// The `false` branch stays here as the deliberate kill switch for App
/// Review Guideline 2.4.5: if a future submission is rejected over the
/// keystroke-injection feature, flipping [kAutoPasteSupported] back to
/// `false` cleanly downgrades every build to the clipboard-only behaviour
/// that already shipped before this feature existed.
AfterTranscriptionAction resolveAfterTranscriptionAction(
  AfterTranscriptionAction action, {
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  if (autoPasteSupported) return action;
  return switch (action) {
    AfterTranscriptionAction.paste ||
    AfterTranscriptionAction.clipboardAndPaste =>
      AfterTranscriptionAction.clipboard,
    AfterTranscriptionAction.clipboard ||
    AfterTranscriptionAction.nothing => action,
  };
}

/// The single "does this user even use Auto-Paste" predicate.
///
/// Every *proactive* Auto-Paste permission surface — the startup gate, the
/// app-level restart watch, and the TCC-reset notice — must consult this
/// before showing any UI. A user whose resolved after-transcription action
/// never injects keystrokes (clipboard-only / nothing, which is also the
/// factory default) has no use for the permission, and per Apple's HIG a
/// permission may only be requested "when people are using features that
/// clearly need" it. Centralized here so the check cannot drift apart
/// between surfaces again.
bool afterTranscriptionActionPastes(
  AfterTranscriptionAction action, {
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  return switch (resolveAfterTranscriptionAction(
    action,
    autoPasteSupported: autoPasteSupported,
  )) {
    AfterTranscriptionAction.paste ||
    AfterTranscriptionAction.clipboardAndPaste => true,
    AfterTranscriptionAction.clipboard ||
    AfterTranscriptionAction.nothing => false,
  };
}

/// Pure decision for the app-level Auto-Paste restart watch: whether the
/// restart / manual-grant dialog may fire for the current state.
/// Extracted from the widget listener so the guard set is unit-testable —
/// the missing [userPastes] condition here is exactly the bug that showed
/// Auto-Paste dialogs to clipboard-only users.
///
/// [onboardingCompleted], [onboardingManuallyOpen] and
/// [onboardingRevisionRunning] together form the "is the onboarding surface
/// on top" predicate (see `core/onboarding/onboarding_surface.dart`): the
/// flow carries its own inline restart banner on the Auto-Paste step, so a
/// native modal on top of it would be a second, competing voice — during the
/// first run, during a review reopened from Settings, *and* during an
/// onboarding revision run.
bool shouldShowAutoPasteRestartSurface({
  required bool needsRestart,
  required bool onboardingCompleted,
  required bool userPastes,
  bool onboardingManuallyOpen = false,
  bool onboardingRevisionRunning = false,
}) {
  return needsRestart &&
      !onboardingSurfaceActive(
        onboardingCompleted: onboardingCompleted,
        manuallyOpen: onboardingManuallyOpen,
        revisionRunning: onboardingRevisionRunning,
      ) &&
      userPastes;
}

/// Whether the onboarding's Auto-Paste step switches Auto-Paste on after a
/// capability change (maintainer 2026-10-31, 1a). Only a grant the user asked
/// for in this step counts ([grantRequestedHere]: macOS "Allow", the Linux
/// setup command), and only the change to ready proves it: a permission that
/// was already there, or a hoped-for one, never flips the setting. A user who
/// already pastes keeps their choice.
///
/// Only a fresh first-run onboarding may set the choice ([freshOnboarding],
/// maintainer 2026-11-02): a revision run or a review reopened from Settings
/// belongs to an existing install, whose stored choice is never changed.
///
/// [alreadyGrantedAtStart] (macOS only, maintainer 2026-11-02): the
/// Accessibility permission was already granted when the step first probed
/// it. That counts as the user's enabling, like a grant asked for here.
bool shouldEnableAutoPasteAfterGrant({
  required bool grantRequestedHere,
  required PasteCapabilityStatus? previous,
  required PasteCapabilityStatus? next,
  required AfterTranscriptionAction current,
  required bool freshOnboarding,
  bool alreadyGrantedAtStart = false,
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  return autoPasteSupported &&
      freshOnboarding &&
      (grantRequestedHere || alreadyGrantedAtStart) &&
      previous != PasteCapabilityStatus.ready &&
      next == PasteCapabilityStatus.ready &&
      !afterTranscriptionActionPastes(
        current,
        autoPasteSupported: autoPasteSupported,
      );
}

/// Whether the first-run onboarding of the Mac App Store build turns direct
/// paste on, so its last page shows it preselected (#431). The paste
/// permission is there ([status]) and nobody chose otherwise: only the factory
/// `clipboard` is replaced, and not after the user went on without the
/// permission ([declined]), which is the one way to say no in this flow. A
/// fresh install without the grant stays on the clipboard.
///
/// Reads the status rather than its change to ready, because the restart a
/// grant can need ends this process: the fresh one simply starts out ready.
bool shouldPreselectDirectPaste({
  required PasteCapabilityStatus? status,
  required AfterTranscriptionAction current,
  required bool freshOnboarding,
  required bool declined,
  bool masBuild = kIsMasBuild,
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  return masBuild &&
      autoPasteSupported &&
      freshOnboarding &&
      !declined &&
      status == PasteCapabilityStatus.ready &&
      current == AfterTranscriptionAction.clipboard;
}

/// Whether a dictation that was only copied gets the one-time hint that
/// WhisPaste can paste it too (maintainer 2026-10-31, point 3). Only for the
/// clipboard-only setting (not "nothing"), after the onboarding, and once per
/// installation ([alreadyShown]). Never in a build where Auto-Paste is
/// switched off, since the hint would lead nowhere, and never after the user
/// closed the status bar's "Auto-Paste off" chip ([offHintDismissed]): that
/// already said "I know".
bool shouldOfferPasteSetupHint({
  required AfterTranscriptionAction action,
  required bool onboardingCompleted,
  required bool alreadyShown,
  required bool offHintDismissed,
  bool autoPasteSupported = kAutoPasteSupported,
}) {
  return autoPasteSupported &&
      onboardingCompleted &&
      !alreadyShown &&
      !offHintDismissed &&
      action == AfterTranscriptionAction.clipboard;
}
