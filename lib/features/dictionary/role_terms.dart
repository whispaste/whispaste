/// The dictionary's one-time term suggestion for the roles chosen on the
/// "Über dich" page (maintainer 2026-10-31, ticket 2a, part B): a few names
/// and abbreviations the recogniser often misspells for that kind of work.
/// Nothing is added until the user takes them over; taking over or hiding
/// ends the suggestion for good ([OnboardingSettings.roleTermsDone]).
///
/// The packs stay small on purpose: the terms go to the recogniser as a
/// prompt with a budget of a few dozen tokens, and words it already writes
/// correctly only take room. Pure, so the rules are tested without widgets.
library;

import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../services/dictionary/vocabulary_terms.dart';
import '../onboarding/about_answers.dart';

export '../../services/dictionary/vocabulary_terms.dart'
    show encodeVocabulary, vocabularyTerms;

/// Terms per role and app language. Technical names and business
/// abbreviations are the same in every language; law and education are
/// national, so they differ. Roles without a reliable set (writing, other)
/// have none.
const Map<String, Map<String, List<String>>> kRoleTermPacks = {
  'dev': {
    '*': ['GitHub', 'TypeScript', 'Kubernetes', 'PostgreSQL', 'JSON', 'npm'],
  },
  'business': {
    '*': ['KPI', 'CRM', 'OKR', 'B2B', 'SaaS'],
  },
  'legal': {
    'de': ['DSGVO', 'BGB', 'ZPO', 'StGB', 'HGB'],
    'en': ['GDPR', 'NDA', 'LLC'],
    'es': ['RGPD', 'BOE', 'LEC'],
    'pt': ['LGPD', 'RGPD', 'STF', 'STJ'],
    'ru': ['ГК РФ', 'УК РФ', 'ГПК РФ', 'АПК РФ'],
    'he': ['בג״ץ', 'עו״ד', 'ע״א'],
  },
  'education': {
    'de': ['ECTS', 'Moodle', 'Erasmus+', 'MINT'],
    'en': ['Moodle', 'STEM', 'GPA'],
    'es': ['ECTS', 'Moodle', 'ESO', 'EBAU'],
    'pt': ['ENEM', 'Moodle', 'ECTS'],
    'ru': ['ЕГЭ', 'ОГЭ', 'ФГОС', 'Moodle'],
    'he': ['Moodle', 'מל״ג'],
  },
};

/// One role's part of the suggestion: the terms not yet in the list.
class RoleTermGroup {
  const RoleTermGroup(this.role, this.terms);

  final String role;
  final List<String> terms;
}

String _key(String term) => term.trim().toLowerCase();

/// The suggestion for [onboarding] in [languageCode]: one group per chosen
/// role with a pack, in the order of the "Über dich" chips, without terms
/// already in [vocabulary] (case ignored). Empty when the suggestion is
/// finished, no role has a pack, or every term is already there.
List<RoleTermGroup> roleTermSuggestion({
  required OnboardingSettings onboarding,
  required String vocabulary,
  required String languageCode,
}) {
  if (onboarding.roleTermsDone) return const [];
  final roles = aboutRoles(onboarding.userRoles);
  final taken = {for (final t in vocabularyTerms(vocabulary)) _key(t)};
  final groups = <RoleTermGroup>[];
  for (final role in kOnboardingAboutRoles) {
    if (!roles.contains(role)) continue;
    final pack = kRoleTermPacks[role];
    final terms = pack?[languageCode] ?? pack?['*'] ?? pack?['en'];
    if (terms == null) continue;
    final fresh = [
      for (final t in terms)
        if (taken.add(_key(t))) t,
    ];
    if (fresh.isNotEmpty) groups.add(RoleTermGroup(role, fresh));
  }
  return groups;
}

/// [vocabulary] with [add] appended, each term once (case ignored); the
/// existing text is kept as typed. A list written one term per line goes on
/// that way, otherwise terms are joined with ", ".
String mergeVocabulary(String vocabulary, Iterable<String> add) {
  final taken = {for (final t in vocabularyTerms(vocabulary)) _key(t)};
  final fresh = [
    for (final t in add)
      if (t.trim().isNotEmpty && taken.add(_key(t))) t.trim(),
  ];
  if (fresh.isEmpty) return vocabulary;
  final base = vocabulary.trimRight();
  final separator = base.contains('\n') ? '\n' : ', ';
  final joined = fresh.join(separator);
  if (base.isEmpty) return joined;
  final tail = base.endsWith(',') ? ' ' : separator;
  return '$base$tail$joined';
}

// ---------------------------------------------------------------------------
// The terms list: single entries of the stored text
// ---------------------------------------------------------------------------

/// Result of an edit of the terms list: the text to store and, when the edit
/// was refused because the term is already there, the index of that entry.
typedef VocabularyEdit = ({String vocabulary, int? duplicateOf});

/// Index of [term] in the terms of [stored] (case ignored), or null.
int? vocabularyIndexOf(String stored, String term) {
  final key = _key(term);
  final terms = vocabularyTerms(stored);
  for (var i = 0; i < terms.length; i++) {
    if (_key(terms[i]) == key) return i;
  }
  return null;
}

/// [stored] with [term] added at the end. An empty term changes nothing; a
/// term already in the list (case ignored) is not added again and the result
/// names its index. The text already stored is kept as typed.
VocabularyEdit addVocabularyTerm(String stored, String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return (vocabulary: stored, duplicateOf: null);
  final existing = vocabularyIndexOf(stored, trimmed);
  if (existing != null) return (vocabulary: stored, duplicateOf: existing);
  return (vocabulary: mergeVocabulary(stored, [trimmed]), duplicateOf: null);
}

/// Result of adding typed text that may hold several terms: the text to
/// store, the terms that were new (in typed order) and those that were
/// already there.
typedef VocabularyAddition = ({
  String vocabulary,
  List<String> added,
  List<String> duplicates,
});

/// [stored] with every term of [input] added: the input is split at commas
/// and line breaks, each non-empty trimmed part becomes its own entry, and a
/// part already in the list (case ignored, also within the input) is skipped.
VocabularyAddition addVocabularyTerms(String stored, String input) {
  var vocabulary = stored;
  final added = <String>[];
  final duplicates = <String>[];
  for (final term in vocabularyTerms(input)) {
    final result = addVocabularyTerm(vocabulary, term);
    if (result.duplicateOf != null) {
      duplicates.add(term);
    } else {
      vocabulary = result.vocabulary;
      added.add(term);
    }
  }
  return (vocabulary: vocabulary, added: added, duplicates: duplicates);
}

/// Whether [text] would be several entries (a comma or a line break between
/// words), which one entry must not hold.
bool vocabularyTextHoldsSeveral(String text) =>
    vocabularyTerms(text).length > 1;

/// [stored] with the entry at [index] changed to [term]. Refused (the result
/// names the other entry) when another entry already has that spelling; a
/// change of letter case alone is allowed. An empty term or an index outside
/// the list changes nothing.
VocabularyEdit renameVocabularyTerm(String stored, int index, String term) {
  final terms = vocabularyTerms(stored);
  final trimmed = term.trim();
  if (trimmed.isEmpty || index < 0 || index >= terms.length) {
    return (vocabulary: stored, duplicateOf: null);
  }
  final key = _key(trimmed);
  for (var i = 0; i < terms.length; i++) {
    if (i != index && _key(terms[i]) == key) {
      return (vocabulary: stored, duplicateOf: i);
    }
  }
  if (terms[index] == trimmed) return (vocabulary: stored, duplicateOf: null);
  terms[index] = trimmed;
  return (
    vocabulary: encodeVocabulary(terms, style: stored),
    duplicateOf: null,
  );
}

/// [stored] without the entry at [index]; an index outside the list changes
/// nothing.
String removeVocabularyTerm(String stored, int index) {
  final terms = vocabularyTerms(stored);
  if (index < 0 || index >= terms.length) return stored;
  terms.removeAt(index);
  return encodeVocabulary(terms, style: stored);
}

/// [stored] with [term] put back at [index] (clamped to the list), for undoing
/// a removal. Nothing changes when the term is empty or already there.
String insertVocabularyTerm(String stored, int index, String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty || vocabularyIndexOf(stored, trimmed) != null) {
    return stored;
  }
  final terms = vocabularyTerms(stored);
  terms.insert(index.clamp(0, terms.length), trimmed);
  return encodeVocabulary(terms, style: stored);
}

/// [stored] with the entry at [index] moved one place up (the list is in
/// order of priority). The first entry or an index outside the list changes
/// nothing.
String moveVocabularyTermUp(String stored, int index) {
  final terms = vocabularyTerms(stored);
  if (index <= 0 || index >= terms.length) return stored;
  final term = terms.removeAt(index);
  terms.insert(index - 1, term);
  return encodeVocabulary(terms, style: stored);
}
