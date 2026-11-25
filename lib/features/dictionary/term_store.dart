import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../services/dictionary/vocabulary_terms.dart';
import '../replacements/replacements_page.dart';

/// Adds [terms] to the dictionary (#1969): there is no separate term list
/// any more, a term is the replacement entry "term → term" (matching as for
/// any new entry, so a longer term also catches near misspellings). A term
/// that already is a trigger (case ignored) is skipped. The term hint for
/// the recogniser follows from the replacements (`auto_terms_sync.dart`).
/// Returns the terms that were added.
Future<List<String>> addDictionaryTerms(
  ProviderContainer container,
  Iterable<String> terms,
) async {
  final notifier = container.read(replacementsProvider.notifier);
  final existing = await container.read(replacementsProvider.future);
  final taken = {
    for (final r in existing)
      for (final t in r.triggers) t.trim().toLowerCase(),
  };
  final added = <String>[];
  for (final raw in terms) {
    final term = raw.trim();
    if (term.isEmpty || !taken.add(term.toLowerCase())) continue;
    await notifier.add([term], term);
    added.add(term);
  }
  return added;
}

/// Removes the term entry "[term] → [term]" again (the undo of a taken-over
/// suggestion). Other entries with that trigger stay.
Future<void> removeDictionaryTerm(
  ProviderContainer container,
  String term,
) async {
  final key = term.trim().toLowerCase();
  final existing = await container.read(replacementsProvider.future);
  for (final r in existing) {
    if (r.triggers.length == 1 &&
        r.triggers.single.trim().toLowerCase() == key &&
        r.replacement.trim().toLowerCase() == key) {
      await container.read(replacementsProvider.notifier).remove(r.id);
    }
  }
}

/// Applies a change of the term text the old way callers phrase it: the
/// terms [change] adds become term entries, the ones it drops are removed.
/// The text itself is no longer written; it follows the replacements.
Future<void> saveDictionaryVocabulary(
  ProviderContainer container,
  String Function(String current) change,
) async {
  final settings = await container.read(settingsProvider.future);
  final current = settings.stt.customVocabulary;
  final before = {for (final t in vocabularyTerms(current)) t.toLowerCase()};
  final next = vocabularyTerms(change(current));
  final after = {for (final t in next) t.toLowerCase()};
  await addDictionaryTerms(container, [
    for (final t in next)
      if (!before.contains(t.toLowerCase())) t,
  ]);
  for (final t in vocabularyTerms(current)) {
    if (!after.contains(t.toLowerCase())) {
      await removeDictionaryTerm(container, t);
    }
  }
}
