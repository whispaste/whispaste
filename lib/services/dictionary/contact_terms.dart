/// The contact names of the dictionary (#2036) as a hint for the local
/// engines only. They never enter `SttSettings.customVocabulary`, the text
/// every engine reads, cloud engines included: contact names stay on the
/// device. On-device Whisper reads them behind the own terms (its budget
/// cuts from the end, so the own terms always win), and the local term
/// matching of the text steps uses them as terms.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'vocabulary_terms.dart';

/// Most contact names handed to the dictation path. The local term
/// matching compares every term with every word of a dictation, so a
/// contact list of thousands would cost time on the hotkey path; the most
/// used names come first and survive the cut.
const int kContactTermsMax = 200;

/// One contact name entry as the hint sees it.
typedef ContactTermSource = ({String name, int usageCount, DateTime changed});

/// The contact names for the local engines: most used first, then newest
/// change, then [entries] order; each once (case ignored), without texts
/// the term separator would split, at most [kContactTermsMax].
List<String> contactHintTerms(List<ContactTermSource> entries) {
  final order = [for (var i = 0; i < entries.length; i++) i]
    ..sort((a, b) {
      final byUse = entries[b].usageCount.compareTo(entries[a].usageCount);
      if (byUse != 0) return byUse;
      final byRecency = entries[b].changed.compareTo(entries[a].changed);
      return byRecency != 0 ? byRecency : a.compareTo(b);
    });
  final seen = <String>{};
  final out = <String>[];
  for (final i in order) {
    final name = entries[i].name.trim();
    if (name.isEmpty || name.contains(RegExp(r'[,\n]'))) continue;
    if (!seen.add(name.toLowerCase())) continue;
    out.add(name);
    if (out.length >= kContactTermsMax) break;
  }
  return out;
}

/// The term text for a local engine: the own terms of [own] first, then
/// the [contacts] not already among them (case ignored), in the style of
/// [own].
String localVocabularyHint(String own, List<String> contacts) {
  final terms = vocabularyTerms(own);
  if (contacts.isEmpty) return vocabularyPrompt(own);
  final seen = {for (final t in terms) t.toLowerCase()};
  return encodeVocabulary([
    ...terms,
    for (final c in contacts)
      if (c.trim().isNotEmpty && seen.add(c.trim().toLowerCase())) c.trim(),
  ], style: own);
}

/// The terms for the local term matching: the own terms of [own], then the
/// [contacts].
List<String> localVocabularyTerms(String own, List<String> contacts) =>
    vocabularyTerms(localVocabularyHint(own, contacts));

/// The current contact names for the local engines, kept by the term sync
/// (`auto_terms_sync.dart`) from the dictionary. In memory only.
final contactTermsProvider = NotifierProvider<ContactTerms, List<String>>(
  ContactTerms.new,
);

class ContactTerms extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> terms) {
    if (_same(state, terms)) return;
    state = List.unmodifiable(terms);
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
