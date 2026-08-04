/// Trigger matching for the Snippet-Picker (dictation-automations ticket 06).
///
/// The picker has exactly one global trigger word
/// (`BehaviorSettings.snippetPickerTrigger`), matched via the same
/// [normalizeForExactMatch] comparison used elsewhere for trigger phrases.
library;

import '../exact_match_normalization.dart' show normalizeForExactMatch;

/// Returns `true` when [transcript] exactly matches [trigger] after
/// [normalizeForExactMatch] normalization.
///
/// An empty (or whitespace-only) [trigger] means the feature is off and
/// never matches; likewise an empty normalized [transcript] never matches
/// (guards against matching on silence).
bool snippetPickerTriggerMatches(String trigger, String transcript) {
  final normalizedTrigger = normalizeForExactMatch(trigger);
  if (normalizedTrigger.isEmpty) return false;
  final normalizedTranscript = normalizeForExactMatch(transcript);
  if (normalizedTranscript.isEmpty) return false;
  return normalizedTrigger == normalizedTranscript;
}
