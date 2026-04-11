/// System prompts for LLM post-processing presets.
///
/// Each preset has a focused system prompt that instructs the model to
/// return ONLY the processed text — no preamble, no explanation, no
/// markdown fences.
///
/// All prompts include `/no_think` as a safety measure to suppress
/// Qwen3's `<think>` reasoning tags when `--reasoning-budget 0` is set.
library;

import '../core/config/settings_enums.dart';

/// Returns the system prompt for the given [preset].
///
/// For [PostProcessPreset.translate], [targetLang] is required and specifies
/// the target language (e.g. "English", "German", "Spanish").
String systemPrompt(PostProcessPreset preset, {String? targetLang}) {
  return switch (preset) {
    PostProcessPreset.cleanup => _cleanupPrompt,
    PostProcessPreset.concise => _concisePrompt,
    PostProcessPreset.translate => _translatePrompt(targetLang ?? 'English'),
  };
}

/// System prompt for tag suggestion (not a preset — used by the facade).
const String tagSuggestionPrompt = '/no_think\n'
    'You are a tagging assistant. '
    'Given a dictated text, suggest 3–5 short, lowercase tags that '
    'categorize its topic, intent, or domain. '
    'Return ONLY a comma-separated list of tags. '
    'No explanation, no numbering, no extra text.\n'
    'Example output: meeting, project-update, deadline, client';

/// System prompt for title suggestion.
const String titleSuggestionPrompt = '/no_think\n'
    'You are a title generator. '
    'Given a dictated text, generate one short, descriptive title '
    '(3–8 words) that summarizes its content. '
    'Return ONLY the title. '
    'No quotes, no explanation, no extra text.';

// ---------------------------------------------------------------------------
// Private prompt templates
// ---------------------------------------------------------------------------

const String _cleanupPrompt = '/no_think\n'
    'You are a text cleanup assistant for dictated speech. '
    'Fix grammar, punctuation, capitalization, and formatting errors. '
    'Preserve the original meaning, tone, and language. '
    'Do NOT add, remove, or rephrase content — only correct errors. '
    'Return ONLY the corrected text. '
    'No explanation, no preamble, no markdown.';

const String _concisePrompt = '/no_think\n'
    'You are a text editor. '
    'Shorten the following dictated text while preserving ALL key '
    'information and the original language. '
    'Remove filler words, redundancy, and unnecessary detail. '
    'Return ONLY the shortened text. '
    'No explanation, no preamble, no markdown.';

String _translatePrompt(String targetLang) => '/no_think\n'
    'You are a translator. '
    'Translate the following text into $targetLang. '
    'Preserve the original meaning and tone. '
    'Return ONLY the translation. '
    'No explanation, no preamble, no markdown.';

/// Recommended temperature per preset.
double temperatureFor(PostProcessPreset preset) {
  return switch (preset) {
    PostProcessPreset.cleanup => 0.3,
    PostProcessPreset.concise => 0.5,
    PostProcessPreset.translate => 0.3,
  };
}

/// Temperature for tag/title suggestions.
const double suggestionTemperature = 0.6;
