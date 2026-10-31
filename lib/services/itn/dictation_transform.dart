/// Shared contract of the written-form rules (inverse text normalization).
///
/// Each rule turns one kind of spoken form ("max at gmail dot com", "zehn
/// Uhr dreißig") into its written form ("max@gmail.com", "10:30 Uhr"). Rules
/// are pure string functions: no state, no I/O, safe to run on any isolate.
library;

/// The language a dictation runs in, reduced to the base code the rules
/// branch on. Only `de` and `en` have rules; every other value gets none.
class TransformContext {
  const TransformContext({required this.languageCode});

  /// Base language code, lowercase (`de`, `en`, ...).
  final String languageCode;

  bool get isGerman => languageCode == 'de';
  bool get isEnglish => languageCode == 'en';
}

/// One written-form rule. [id] names the rule in logs and tests and matches
/// the [WrittenFormKind] it is switched by.
abstract interface class DictationTransform {
  String get id;

  /// Returns [text] with every unambiguous spoken form replaced. Text without
  /// such a form comes back unchanged, the same instance when possible.
  String apply(String text, TransformContext ctx);
}

/// Words that never start or join a spoken address or host: articles,
/// prepositions and conjunctions in both languages. "look at example dot
/// com" and "an max at gmx punkt de" therefore keep their leading word.
const labelStopWords = <String>{
  'a',
  'an',
  'the',
  'this',
  'that',
  'my',
  'your',
  'our',
  'their',
  'and',
  'or',
  'to',
  'of',
  'in',
  'on',
  'for',
  'from',
  'with',
  'look',
  'be',
  'der',
  'die',
  'das',
  'ein',
  'eine',
  'einen',
  'mein',
  'meine',
  'dein',
  'deine',
  'unser',
  'unsere',
  'zu',
  'im',
  'auf',
  'für',
  'bei',
  'mit',
  'von',
};

/// Runs a rule's German or English pass for [ctx], after the cheap [hint]
/// check. Other languages get [text] back unchanged.
String applyByLanguage(
  String text,
  TransformContext ctx, {
  required RegExp hint,
  required String Function(String text) german,
  required String Function(String text) english,
}) {
  if (!hint.hasMatch(text)) return text;
  if (ctx.isGerman) return german(text);
  if (ctx.isEnglish) return english(text);
  return text;
}
