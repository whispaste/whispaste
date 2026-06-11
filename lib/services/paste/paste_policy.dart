import '../../core/config/build_config.dart';
import '../../core/config/settings_enums.dart';

/// Resolves the effective "after transcription" action for the current build.
///
/// In builds where simulated-keystroke auto-paste is unavailable (the sandboxed
/// Mac App Store variant — see [kAutoPasteSupported]), any action that would
/// inject a paste keystroke is downgraded to [AfterTranscriptionAction.clipboard]
/// so the transcript still lands on the clipboard and the user can paste it
/// manually with ⌘V. On every other platform/build the user's choice is honoured
/// unchanged.
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
