/// Smart-Mode-v2 preset prompts (`.scratch/smart-mode-v2/PRODUCT-SPEC.md` §1).
///
/// Mirrors [SmartModeSettings.standardPreset]'s four string values ('off',
/// 'cleanup', 'concise', 'translate') as a proper enum for callers that run
/// the engine.
library;

/// The four values ticket 01's `SmartModeSettings.standardPreset` accepts.
enum SmartModePreset { off, cleanup, concise, translate }

/// The seven official Smart-Mode-Translate target languages
/// (PRODUCT-SPEC §5), modeled generically so the pipeline and settings
/// schema need no changes as later languages clear their ticket-09
/// validation spike. [languageName] is the English name embedded in the
/// translation prompt (kept in English regardless of app UI locale — the
/// model was validated against English-worded prompts, ADR 0006).
enum SmartModeTargetLanguage {
  german('de', 'German'),
  english('en', 'English'),
  spanish('es', 'Spanish'),
  french('fr', 'French'),
  portuguese('pt', 'Portuguese'),
  mandarin('zh', 'Mandarin Chinese'),
  russian('ru', 'Russian');

  const SmartModeTargetLanguage(this.code, this.languageName);

  /// ISO 639-1 code — matches [SmartModeSettings.targetLanguage]'s stored
  /// value.
  final String code;

  /// English name of the language, used in [smartModeTranslateSystemPrompt].
  final String languageName;
}

/// The subset of [SmartModeTargetLanguage] that has passed its ticket-09
/// validation spike and may be shown as a choosable option in the UI.
/// German is validated as part of ticket 03 (18-sentence batch test,
/// `spike-test-results.md`) — the other six are gated behind their own
/// spike in ticket 09 and are deliberately absent here, not just hidden, so
/// a settings value of e.g. `zh` from a future build downgrading to this one
/// falls back safely (see [smartModeTargetLanguageFromSettingsValue]).
const List<SmartModeTargetLanguage> smartModeValidatedTargetLanguages = [
  SmartModeTargetLanguage.german,
];

/// Parses a [SmartModeSettings.targetLanguage] code into a
/// [SmartModeTargetLanguage], defaulting to [SmartModeTargetLanguage.german]
/// for any unrecognized or not-yet-validated code (forward/backward
/// compatibility, and the only currently-validated language).
SmartModeTargetLanguage smartModeTargetLanguageFromSettingsValue(String value) {
  for (final lang in smartModeValidatedTargetLanguages) {
    if (lang.code == value) return lang;
  }
  return SmartModeTargetLanguage.german;
}

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

/// System prompt for [SmartModePreset.concise].
///
/// Same language-neutrality rationale as [smartModeCleanupSystemPrompt] —
/// explicitly forbids translating so a non-English dictation is shortened in
/// place rather than shortened-and-translated.
const String smartModeConciseSystemPrompt =
    'Shorten this dictated text: remove redundancy and filler while '
    'preserving the core meaning and every important fact. Do not translate '
    'it — keep the exact same language as the input. Output ONLY the '
    'shortened text, no explanation.';

/// System prompt for [SmartModePreset.translate] into [target].
///
/// Accepts dictation in any source language (the model detects it from the
/// input, no separate source-language setting exists — PRODUCT-SPEC §5) and
/// translates into [target]. The known lexical-bias model limit for certain
/// source/target pairs is an accepted constraint, not handled here (ADR
/// 0006).
String smartModeTranslateSystemPrompt(SmartModeTargetLanguage target) =>
    'Translate this dictated text into ${target.languageName}. If it is '
    'already in ${target.languageName}, return it unchanged (only fix '
    'obvious dictation artifacts). Output ONLY the translated text, no '
    'explanation.';

/// Resolves the system prompt for [preset], shared by the live pipeline
/// (`RecordingOrchestrator._runSmartModeRefine`, tickets 02/03) and the
/// retroactive on-a-history-entry path (`SmartModeRetroactiveService`,
/// ticket 05) so both stay in sync automatically.
///
/// [targetLanguage] is required for [SmartModePreset.translate] and ignored
/// otherwise. [preset] must not be [SmartModePreset.off] — callers already
/// filter that out before reaching the engine.
String smartModeSystemPromptFor(
  SmartModePreset preset, {
  SmartModeTargetLanguage? targetLanguage,
}) => switch (preset) {
  SmartModePreset.cleanup => smartModeCleanupSystemPrompt,
  SmartModePreset.concise => smartModeConciseSystemPrompt,
  SmartModePreset.translate => smartModeTranslateSystemPrompt(
    targetLanguage ?? SmartModeTargetLanguage.german,
  ),
  SmartModePreset.off => throw StateError(
    'smartModeSystemPromptFor called with preset off',
  ),
};
