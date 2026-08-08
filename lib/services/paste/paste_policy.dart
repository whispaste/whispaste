import '../../core/config/build_config.dart';
import '../../core/config/settings_enums.dart';
import '../../core/onboarding/onboarding_surface.dart';

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
/// forced-restart / manual-grant modal may fire for the current state.
/// Extracted from the widget listener so the guard set is unit-testable —
/// the missing [userPastes] condition here is exactly the bug that showed
/// Auto-Paste dialogs to clipboard-only users.
///
/// [onboardingCompleted] and [onboardingManuallyOpen] together form the
/// "is the onboarding surface on top" predicate (see
/// `core/onboarding/onboarding_surface.dart`): the flow carries its own
/// inline restart banner on the Auto-Paste step, so a native modal on top of
/// it would be a second, competing voice — during the first run *and* during
/// a review reopened from Settings.
bool shouldShowAutoPasteRestartSurface({
  required bool needsRestart,
  required bool onboardingCompleted,
  required bool userPastes,
  bool onboardingManuallyOpen = false,
}) {
  return needsRestart &&
      !onboardingSurfaceActive(
        onboardingCompleted: onboardingCompleted,
        manuallyOpen: onboardingManuallyOpen,
      ) &&
      userPastes;
}
