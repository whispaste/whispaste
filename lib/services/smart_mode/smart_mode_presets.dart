/// Smart-Mode-v2 preset prompts (`.scratch/smart-mode-v2/PRODUCT-SPEC.md` §1).
///
/// Mirrors [SmartModeSettings.standardPreset]'s four string values ('off',
/// 'cleanup', 'concise', 'translate') as a proper enum for callers that run
/// the engine. Only [cleanup] has a live prompt today (ticket 02) — Concise
/// and Translate are wired up by later tickets (03+); selecting them as the
/// standard preset today is a no-op until then.
library;

/// The four values ticket 01's `SmartModeSettings.standardPreset` accepts.
enum SmartModePreset { off, cleanup, concise, translate }

/// Parses a [SmartModeSettings.standardPreset] string into a [SmartModePreset],
/// defaulting to [SmartModePreset.off] for any unrecognized value (forward
/// compatibility with a settings file from a newer app version).
SmartModePreset smartModePresetFromSettingsValue(String value) {
  switch (value) {
    case 'cleanup':
      return SmartModePreset.cleanup;
    case 'concise':
      return SmartModePreset.concise;
    case 'translate':
      return SmartModePreset.translate;
    default:
      return SmartModePreset.off;
  }
}

/// System prompt for [SmartModePreset.cleanup].
///
/// Deliberately **language-neutral** (PRODUCT-SPEC §2): STT can produce text
/// in dozens of source languages, and hard-coding "this German text" (as the
/// prototype's `main_smart_mode_debug.dart` sandbox does — that file is a
/// throwaway debug harness, not production wiring) would silently misbehave
/// for every other language. "Do not translate" is stated explicitly because
/// small instruct models otherwise sometimes translate unprompted when the
/// input is in a language other than English.
const String smartModeCleanupSystemPrompt =
    'Clean up this dictated text: remove filler words (like "um", "uh", '
    '"like"), and fix punctuation and capitalization. Do not change the '
    'content, wording, or meaning, and do not translate it — keep the exact '
    'same language as the input. Output ONLY the cleaned text, no '
    'explanation.';
