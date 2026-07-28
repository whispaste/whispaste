import '../../core/config/build_config.dart';
import '../../core/config/settings_enums.dart';

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
