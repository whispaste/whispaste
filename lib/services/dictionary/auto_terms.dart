/// Terms come from the replacements (#1969): the dictionary keeps one list,
/// the replacements, and the recogniser's term hint is filled from the
/// replacement texts used most. Pure, so the rules are tested without a
/// database.
library;

import 'entry_validation.dart';
import 'vocabulary_terms.dart';

/// Upper bound of terms handed on. Each engine still cuts its own budget
/// (`term_budget.dart`), in this order, so the most used ones get in.
const int kAutoTermsMax = 50;

/// One replacement as the term hint sees it. [isTerm]: a term entry, its
/// trigger is its replacement (case ignored). [changed]: its last change
/// (or creation), the tie-break between equally used entries.
typedef AutoTermSource = ({
  String replacement,
  int usageCount,
  bool isTerm,
  DateTime changed,
});

/// Whether [triggers] → [replacement] is a term entry.
bool isTermEntry(List<String> triggers, String replacement) => triggers.any(
  (t) => t.trim().toLowerCase() == replacement.trim().toLowerCase(),
);

/// The term hint for [entries], in their list order: the term entries and
/// the replacements used at least once (an unused sample such as a phone
/// number never reaches the recogniser), ordered by use (most first), then
/// by recency (newest change first), then list order; each once (case
/// ignored), at most [kAutoTermsMax]. Every engine cuts this text from the
/// end in whole terms (`term_budget.dart`), so the order decides what
/// survives a small budget such as Whisper's 63 tokens.
/// Texts the hint cannot carry are left out: empty, several lines, longer
/// than a dictionary entry, a comma (the term separator) or a snippet
/// variable (`{…}`).
String autoTermsVocabulary(List<AutoTermSource> entries) {
  final order = [for (var i = 0; i < entries.length; i++) i]
    ..sort((a, b) {
      final byUse = entries[b].usageCount.compareTo(entries[a].usageCount);
      if (byUse != 0) return byUse;
      final byRecency = entries[b].changed.compareTo(entries[a].changed);
      return byRecency != 0 ? byRecency : a.compareTo(b);
    });
  final seen = <String>{};
  final terms = <String>[];
  for (final i in order) {
    final text = entries[i].replacement.trim();
    if (!entries[i].isTerm && entries[i].usageCount == 0) continue;
    if (text.isEmpty ||
        text.contains('\n') ||
        text.contains(',') ||
        text.contains('{') ||
        text.runes.length > kDictionaryEntryMaxLength) {
      continue;
    }
    if (!seen.add(text.toLowerCase())) continue;
    terms.add(text);
    if (terms.length == kAutoTermsMax) break;
  }
  return terms.join(', ');
}

/// The one-time step of the hand-kept term list into replacements (#1969,
/// maintainer decision): each term of [manualVocabulary] becomes one entry
/// "term → term". With the matching of a new entry (`newEntryMatch`) a term
/// of four or more characters gets "Similar", so the entry still corrects
/// near misspellings to the term, like the term hint did. A term that is
/// already a trigger (case ignored), a repeat, or not a valid entry is
/// skipped. Returns the terms to add, in list order.
List<String> termMigrationPlan(
  String manualVocabulary, {
  required Iterable<String> existingTriggers,
}) {
  final taken = {for (final t in existingTriggers) t.trim().toLowerCase()};
  return [
    for (final term in vocabularyTerms(manualVocabulary))
      if (checkDictionaryEntry(term, existing: const []) == null &&
          taken.add(term.toLowerCase()))
        term,
  ];
}
