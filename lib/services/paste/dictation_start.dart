/// Fits the start of a dictation to the text in front of the caret (#401):
/// upper case after a sentence end or in an empty field, lower case inside a
/// sentence, exactly one space in between.
///
/// Only the first letter and the gap to the text before it ever change.
/// Without a part-of-speech model a capitalised word cannot be told from a
/// name or a German noun, so lower-casing is limited to a closed list of
/// function words per language: a word that is not listed stays as it is.
/// Languages without a list keep the capital letter, and the formal German
/// "Sie" and "Ihr" as well as the English "I" are left out on purpose.
library;

/// Text in front of the caret that decides the start.
const int kDictationStartContextChars = 64;

const Map<String, Set<String>> _functionWords = {
  'de': {
    'aber', 'als', 'am', 'an', 'auch', 'auf', 'aus', 'bei', 'da', 'dann', //
    'das', 'dass', 'dein', 'deine', 'dem', 'den', 'denn', 'der', 'des', //
    'die', 'diese', 'dieser', 'dieses', 'doch', 'dort', 'du', 'durch', //
    'ein', 'eine', 'einem', 'einen', 'einer', 'eines', 'er', 'es', 'für', //
    'gegen', 'hat', 'haben', 'hier', 'ich', 'im', 'in', 'ist', 'kann', //
    'können', 'man', 'mein', 'meine', 'mit', 'muss', 'müssen', 'nach', //
    'nicht', 'noch', 'nur', 'ob', 'oder', 'ohne', 'schon', 'sehr', 'sind', //
    'so', 'soll', 'sollen', 'über', 'um', 'und', 'unser', 'unsere', //
    'unter', 'vom', 'von', 'vor', 'war', 'waren', 'weil', 'wenn', 'werden', //
    'wie', 'wir', 'wird', 'will', 'wollen', 'zu', 'zum', 'zur',
  },
  'en': {
    'also', 'an', 'and', 'are', 'as', 'at', 'because', 'but', 'by', //
    'can', 'could', 'for', 'from', 'had', 'has', 'have', 'he', 'her', //
    'here', 'his', 'if', 'in', 'is', 'it', 'its', 'my', 'not', 'of', 'on', //
    'or', 'our', 'she', 'should', 'so', 'that', 'the', 'their', 'then', //
    'there', 'these', 'they', 'this', 'those', 'to', 'was', 'we', 'were', //
    'when', 'while', 'with', 'would', 'you', 'your',
  },
  'es': {
    'a', 'al', 'como', 'con', 'de', 'del', 'el', 'en', 'es', 'esta', //
    'este', 'la', 'las', 'lo', 'los', 'mi', 'no', 'o', 'para', 'pero', //
    'por', 'porque', 'que', 'se', 'si', 'su', 'un', 'una', 'y',
  },
  'fr': {
    'à', 'au', 'aux', 'avec', 'ce', 'cette', 'dans', 'de', 'des', 'du', //
    'elle', 'en', 'est', 'et', 'il', 'je', 'la', 'le', 'les', 'mais', //
    'mon', 'nous', 'ou', 'par', 'pas', 'pour', 'que', 'qui', 'sur', 'un', //
    'une', 'vous',
  },
  'it': {
    'a', 'al', 'che', 'con', 'di', 'e', 'è', 'il', 'in', 'la', 'le', 'lo', //
    'ma', 'mi', 'non', 'o', 'per', 'perché', 'se', 'si', 'su', 'un', 'una', //
    'uno',
  },
  'pt': {
    'a', 'ao', 'as', 'com', 'como', 'da', 'de', 'do', 'e', 'é', 'em', //
    'este', 'esta', 'mas', 'na', 'no', 'não', 'o', 'os', 'ou', 'para', //
    'pela', 'pelo', 'por', 'porque', 'que', 'se', 'um', 'uma',
  },
};

final RegExp _sentenceEnd = RegExp(r'[.!?…]["»“”’)\]]*$');
final RegExp _lineStart = RegExp(r'\n[ \t]*$');
final RegExp _plainWord = RegExp(r'^\p{L}+$', unicode: true);
final RegExp _wordEdge = RegExp(r'^(\p{L}+)(\p{P}*)$', unicode: true);
final RegExp _noSpaceAfter = RegExp(r'''[(\[{„“‘«"'/\-–—]$''');
final RegExp _noSpaceBefore = RegExp(r'^[.,;:!?…)\]}»”’]');
final RegExp _noGapScript = RegExp(r'[　-ヿ㐀-鿿豈-﫿＀-￯]');

/// What stands in front of the caret, as far as the first letter cares.
enum _Position { sentenceStart, insideSentence, undecided }

_Position _positionAfter(String before) {
  final trimmed = before.trimRight();
  if (trimmed.isEmpty || _lineStart.hasMatch(before)) {
    return _Position.sentenceStart;
  }
  if (_sentenceEnd.hasMatch(trimmed)) return _Position.sentenceStart;
  // After a colon both cases are right, after an opening quote the speaker
  // decides. The text keeps what the recognition wrote.
  if (trimmed.endsWith(':') || _noSpaceAfter.hasMatch(trimmed)) {
    return _Position.undecided;
  }
  return _Position.insideSentence;
}

/// [text] without the blanks at the start of each line (#2088): recognition
/// engines hand back a leading space, which sits visibly at the start of every
/// line in fields like YouTube comments. Line breaks and the text stay.
String stripLeadingLineBlanks(String text) =>
    text.replaceAllMapped(RegExp(r'(^|\n)[ \t\u00A0]+'), (m) => m.group(1)!);

/// [text] as it should go in behind [before]. [languageCode] is the dictation
/// language (`de`, `en-US`, …); [protectedTerms] are dictionary terms, whose
/// spelling never changes.
String adaptDictationStart(
  String text, {
  required String before,
  String? languageCode,
  Set<String> protectedTerms = const {},
}) {
  final body = text.trimLeft();
  if (body.isEmpty) return text;

  final position = _positionAfter(before);
  final fitted = _fitCase(body, position, languageCode, protectedTerms);

  final hasGap = before.isEmpty || before.trimRight() != before;
  if (hasGap) return fitted;
  return _needsSpace(before, fitted) ? ' $fitted' : fitted;
}

bool _needsSpace(String before, String body) {
  if (_noSpaceAfter.hasMatch(before) || _noSpaceBefore.hasMatch(body)) {
    return false;
  }
  final last = String.fromCharCode(before.runes.last);
  final first = String.fromCharCode(body.runes.first);
  return !_noGapScript.hasMatch(last) && !_noGapScript.hasMatch(first);
}

String _fitCase(
  String body,
  _Position position,
  String? languageCode,
  Set<String> protectedTerms,
) {
  if (position == _Position.undecided) return body;
  final end = body.indexOf(RegExp(r'\s'));
  final raw = end < 0 ? body : body.substring(0, end);
  final match = _wordEdge.firstMatch(raw);
  if (match == null) return body;
  final word = match.group(1)!;
  final lower = word.toLowerCase();
  if (protectedTerms.any((term) => term.toLowerCase() == lower)) return body;

  final fitted = position == _Position.sentenceStart
      ? _capitalised(word)
      : _lowered(word, languageCode);
  return fitted == word ? body : fitted + body.substring(word.length);
}

/// Only an all-lower-case word: `iPhone` or `eBay` keep their spelling.
String _capitalised(String word) {
  if (word != word.toLowerCase() || !_plainWord.hasMatch(word)) return word;
  final first = String.fromCharCode(word.runes.first);
  final upper = first.toUpperCase();
  // `ß` has no single upper-case letter.
  if (upper.runes.length != 1) return word;
  return upper + word.substring(first.length);
}

/// Only a listed word in plain sentence case: `DAS` stays an acronym.
String _lowered(String word, String? languageCode) {
  final language = languageCode?.split(RegExp('[-_]')).first.toLowerCase();
  final words = _functionWords[language];
  final lower = word.toLowerCase();
  if (words == null || !words.contains(lower)) return word;
  return word == _capitalised(lower) ? lower : word;
}
