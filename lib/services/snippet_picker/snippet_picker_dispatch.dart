/// Trigger matching for the Snippet-Picker (dictation-automations ticket 06).
///
/// Deliberately separate from [AutomationDispatchService.findMatch]: the
/// picker has exactly one global trigger word
/// (`BehaviorSettings.snippetPickerTrigger`), not a list of user-defined
/// [Automation] rows, but it reuses the same [normalizeForExactMatch]
/// comparison so the two features feel identical to dictate against.
library;

import '../automation_dispatch_service.dart' show normalizeForExactMatch;

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
