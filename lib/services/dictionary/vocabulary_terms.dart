/// How the stored custom vocabulary is split into terms and written back.
/// One place for the dictionary list, the term budget and the recognition,
/// so the list and the engine count the same text (issue #145).
library;

/// The terms of the custom vocabulary [stored], split like the recogniser
/// reads them (commas and line breaks).
List<String> vocabularyTerms(String stored) => [
  for (final t in stored.split(RegExp(r'[,\n]')))
    if (t.trim().isNotEmpty) t.trim(),
];

/// [terms] written back in the style of [style], the text they came from:
/// one term per line if it had a line break, otherwise joined with ", ".
String encodeVocabulary(Iterable<String> terms, {required String style}) =>
    terms.join(style.contains('\n') ? '\n' : ', ');

/// The vocabulary as the recognition receives it: the terms of [stored] in
/// their order of priority, without empty entries or stray spaces. The
/// dictionary list counts this exact text against the prompt budget.
String vocabularyPrompt(String stored) =>
    encodeVocabulary(vocabularyTerms(stored), style: stored);
