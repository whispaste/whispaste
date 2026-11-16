/// The rules a new dictionary entry (a term, or the trigger of a replacement)
/// must pass before it is written. Pure, so each rule is tested without UI.
library;

/// Longest entry the dictionary accepts, in characters (runes).
const int kDictionaryEntryMaxLength = 60;

/// Why an entry was refused.
enum DictionaryEntryProblem {
  /// More than [kDictionaryEntryMaxLength] characters.
  tooLong,

  /// No letter and no digit, only punctuation or symbols.
  onlyPunctuation,

  /// Already in the list (case ignored).
  duplicate,

  /// Already the trigger of a replacement (case ignored).
  triggerConflict,
}

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

String _key(String s) => s.trim().toLowerCase();

/// The first problem of [entry], or null when it may be added. [existing] are
/// the entries of the same list, [triggers] the triggers of all replacements
/// (only checked when given: a replacement trigger may equal a term).
/// An empty entry is not a problem here: nothing is added for it.
DictionaryEntryProblem? checkDictionaryEntry(
  String entry, {
  required Iterable<String> existing,
  Iterable<String> triggers = const [],
}) {
  final text = entry.trim();
  if (text.isEmpty) return null;
  if (text.runes.length > kDictionaryEntryMaxLength) {
    return DictionaryEntryProblem.tooLong;
  }
  if (!_letterOrDigit.hasMatch(text)) {
    return DictionaryEntryProblem.onlyPunctuation;
  }
  final key = _key(text);
  if (existing.any((e) => _key(e) == key)) {
    return DictionaryEntryProblem.duplicate;
  }
  if (triggers.any((t) => _key(t) == key)) {
    return DictionaryEntryProblem.triggerConflict;
  }
  return null;
}

/// Why the replacement dialog refuses a draft (#892, aligned with #623).
enum ReplacementDraftProblem {
  /// A trigger has more than [kDictionaryEntryMaxLength] characters.
  tooLong,

  /// The same trigger twice in one entry (case ignored).
  duplicateTrigger,

  /// A trigger is exactly the replacement text, so nothing would change.
  sameAsReplacement,
}

/// The first problem of a replacement dialog draft and the trigger it is
/// about, or null when the draft may be saved. The same length and duplicate
/// rules as [checkDictionaryEntry]; unlike a term, a trigger may be symbols
/// only (`->`, `:)`), which the dialog offers on purpose. A trigger that only
/// differs from the replacement in case is allowed: it fixes the case.
({ReplacementDraftProblem problem, String trigger})? checkReplacementDraft(
  List<String> triggers,
  String replacement,
) {
  final seen = <String>{};
  final target = replacement.trim();
  for (final raw in triggers) {
    final trigger = raw.trim();
    if (trigger.isEmpty) continue;
    if (trigger.runes.length > kDictionaryEntryMaxLength) {
      return (problem: ReplacementDraftProblem.tooLong, trigger: trigger);
    }
    if (!seen.add(_key(trigger))) {
      return (
        problem: ReplacementDraftProblem.duplicateTrigger,
        trigger: trigger,
      );
    }
    if (trigger == target) {
      return (
        problem: ReplacementDraftProblem.sameAsReplacement,
        trigger: trigger,
      );
    }
  }
  return null;
}
