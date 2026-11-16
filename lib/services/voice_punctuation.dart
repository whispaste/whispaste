/// Spoken punctuation commands ("Komma", "comma", "punto", ...) turned into
/// the mark they name, for a finished transcript. Pure string processing,
/// see [applyVoicePunctuation]. Off by default: the caller checks
/// `SttSettings.spokenPunctuation` and skips this function entirely when it
/// is off.
library;

/// The marks a command can name. Index order does not matter.
enum _Mark {
  comma(','),
  period('.'),
  question('?'),
  exclamation('!'),
  colon(':');

  const _Mark(this.glyph);
  final String glyph;

  /// A mark that ends a sentence: the next word starts with a capital.
  bool get endsSentence =>
      this == _Mark.period ||
      this == _Mark.question ||
      this == _Mark.exclamation;
}

/// Spoken forms per transcription language (base code). Only unambiguous
/// phrases: a bare common word such as "period" or "dot" is left out on
/// purpose, because it means something else in ordinary speech.
const _commandsByLanguage = <String, Map<_Mark, List<String>>>{
  'de': {
    _Mark.comma: ['Komma'],
    _Mark.period: ['Punkt'],
    _Mark.question: ['Fragezeichen'],
    _Mark.exclamation: ['Ausrufezeichen'],
    _Mark.colon: ['Doppelpunkt'],
  },
  'en': {
    _Mark.comma: ['comma'],
    _Mark.period: ['full stop'],
    _Mark.question: ['question mark'],
    _Mark.exclamation: ['exclamation mark', 'exclamation point'],
    _Mark.colon: ['colon'],
  },
  'es': {
    _Mark.comma: ['coma'],
    _Mark.period: ['punto'],
    _Mark.question: ['signo de interrogación'],
    _Mark.exclamation: ['signo de exclamación'],
    _Mark.colon: ['dos puntos'],
  },
  'pt': {
    _Mark.comma: ['vírgula'],
    _Mark.period: ['ponto'],
    _Mark.question: ['ponto de interrogação'],
    _Mark.exclamation: ['ponto de exclamação'],
    _Mark.colon: ['dois pontos'],
  },
  'ru': {
    _Mark.comma: ['запятая'],
    _Mark.period: ['точка'],
    _Mark.question: ['вопросительный знак'],
    _Mark.exclamation: ['восклицательный знак'],
    _Mark.colon: ['двоеточие'],
  },
  'he': {
    _Mark.comma: ['פסיק'],
    _Mark.period: ['נקודה'],
    _Mark.question: ['סימן שאלה'],
    _Mark.exclamation: ['סימן קריאה'],
    _Mark.colon: ['נקודתיים'],
  },
};

/// Words that, directly before a command, make it an ordinary noun or idiom
/// ("der Punkt", "en punto", "a comma" is kept as the command itself).
const _wordsBefore = <String, Set<String>>{
  'de': {
    'der',
    'die',
    'das',
    'den',
    'dem',
    'des',
    'ein',
    'eine',
    'einen',
    'einem',
    'einer',
    'mein',
    'dein',
    'sein',
    'ihr',
    'unser',
    'euer',
    'dieser',
    'diese',
    'dieses',
    'diesen',
    'diesem',
    'jeder',
    'jede',
    'jedes',
    'kein',
    'keine',
    'am',
    'im',
    'vom',
    'zum',
    'zur',
    'auf',
    'um',
    'bis',
    'von',
    'ohne',
  },
  'en': {
    'the',
    'a',
    'an',
    'this',
    'that',
    'my',
    'your',
    'his',
    'her',
    'its',
    'our',
    'their',
    'every',
    'no',
  },
  'es': {
    'el',
    'la',
    'los',
    'las',
    'un',
    'una',
    'unos',
    'unas',
    'este',
    'esta',
    'ese',
    'esa',
    'al',
    'del',
    'de',
    'en',
    'por',
    'sin',
    'cada',
    'mi',
    'tu',
    'su',
    'nuestro',
  },
  'pt': {
    'o',
    'a',
    'os',
    'as',
    'um',
    'uma',
    'uns',
    'umas',
    'este',
    'esta',
    'esse',
    'essa',
    'do',
    'da',
    'dos',
    'das',
    'no',
    'na',
    'em',
    'de',
    'ao',
    'sem',
    'cada',
    'meu',
    'seu',
    'nosso',
  },
  'ru': {
    'в',
    'на',
    'с',
    'из',
    'по',
    'эта',
    'этот',
    'эту',
    'этой',
    'этого',
    'моя',
    'мой',
    'мою',
    'одна',
    'каждая',
    'вся',
    'та',
  },
  'he': {'על', 'של', 'את', 'זה', 'זו'},
};

/// Words that, directly after a command, make it an idiom ("punto de vista",
/// "точка зрения", "Punkt für Punkt"). Matched at the start of the following
/// text.
const _idiomsAfter = <String, List<String>>{
  'de': ['für punkt'],
  'es': [
    'de vista',
    'de partida',
    'de referencia',
    'de acceso',
    'de venta',
    'de inflexión',
  ],
  'pt': ['de vista', 'de partida', 'de referência', 'de acesso', 'de venda'],
  'ru': ['зрения', 'доступа', 'отсчёта', 'отсчета', 'входа', 'выхода'],
};

/// Two-word phrases that, directly before a command, make the whole phrase an
/// idiom ("Punkt für Punkt"). Matched against the two words before the command.
const _idiomsBefore = <String, List<String>>{
  'de': ['punkt für'],
};

const _sentenceOrClauseMarks = '.,;:!?…';
const _letterOrDigit = r'[\p{L}\p{N}]';
final _localeSeparator = RegExp('[-_]');
final _blankRun = RegExp(r'[ \t]+');
final _letterOrDigitStart = RegExp('^$_letterOrDigit', unicode: true);
final _wordRune = RegExp(r'^[\p{L}\p{N}]$', unicode: true);

/// Command sets that apply for [languageCode] (`de`, `en-US`, `auto`, ...).
///
/// A known transcription language uses its own set only. Auto-detection uses
/// the union of all sets; a language without a set (e.g. `fr`) gets none.
List<String> _baseCodesFor(String languageCode) {
  final base = languageCode.toLowerCase().split(_localeSeparator).first;
  if (base == 'auto') return _commandsByLanguage.keys.toList();
  return _commandsByLanguage.containsKey(base) ? [base] : const [];
}

/// Replaces spoken punctuation commands in [text] with the marks they name.
///
/// Rules:
/// - Whole words only, case-insensitive. Compounds such as "Kommando" and
///   "Punktzahl" are never touched.
/// - A command needs a word before it. It is skipped when that word is an
///   article or preposition ("der Punkt", "ein Komma", "en punto") or when an
///   idiom follows it ("punto de vista", "точка зрения").
/// - The spaces before the command go; the mark attaches to the word before,
///   followed by one space. A mark Whisper already wrote after the command is
///   absorbed, and no second mark is added after one that is already there.
/// - After `.`, `?` or `!` the next word is capitalised.
///
/// Never makes things worse: if the transform throws, [text] is returned
/// unchanged.
String applyVoicePunctuation(String text, {required String languageCode}) {
  try {
    final codes = _baseCodesFor(languageCode);
    if (codes.isEmpty) return text;
    return _replaceCommands(text, codes);
  } on Object {
    return text;
  }
}

/// Phrase matching tolerates any run of spaces or tabs between words.
String _phrasePattern(String phrase) =>
    phrase.split(RegExp(r'\s+')).map(RegExp.escape).join(r'[ \t]+');

/// Number words per base code, lower case. Digits are recognised separately.
const _numberWordsByLanguage = <String, Set<String>>{
  'de': {
    'null',
    'eins',
    'zwei',
    'drei',
    'vier',
    'fünf',
    'sechs',
    'sieben',
    'acht',
    'neun',
    'zehn',
    'elf',
    'zwölf',
    'zwanzig',
    'dreißig',
    'hundert',
    'tausend',
  },
  'en': {
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'twenty',
    'thirty',
    'hundred',
    'thousand',
  },
  'es': {
    'cero',
    'uno',
    'dos',
    'tres',
    'cuatro',
    'cinco',
    'seis',
    'siete',
    'ocho',
    'nueve',
    'diez',
    'veinte',
    'treinta',
    'cien',
    'mil',
  },
  'pt': {
    'zero',
    'um',
    'dois',
    'três',
    'quatro',
    'cinco',
    'seis',
    'sete',
    'oito',
    'nove',
    'dez',
    'vinte',
    'trinta',
    'cem',
    'mil',
  },
  'ru': {
    'ноль',
    'один',
    'два',
    'три',
    'четыре',
    'пять',
    'шесть',
    'семь',
    'восемь',
    'девять',
    'десять',
    'двадцать',
    'тридцать',
    'сто',
    'тысяча',
  },
  'he': {'אפס', 'אחת', 'שתיים', 'שלוש', 'ארבע', 'חמש', 'עשר', 'מאה', 'אלף'},
};

/// Curated adjectives and ordinals per language. A command right after one of
/// them, or after an article and one of them, is part of a noun phrase
/// ("der erste Punkt", "buen punto") and stays text. Hebrew has no list.
const _adjectivesByLanguage = <String, Set<String>>{
  'de': {
    'erste',
    'erster',
    'erstes',
    'ersten',
    'zweite',
    'zweiter',
    'dritte',
    'dritter',
    'letzte',
    'letzter',
    'letztes',
    'nächste',
    'nächster',
    'gute',
    'guter',
    'gutes',
    'guten',
    'wichtige',
    'wichtiger',
    'wichtiges',
    'wichtigen',
    'entscheidende',
    'entscheidender',
    'große',
    'großer',
    'großes',
    'großen',
    'kleine',
    'kleiner',
    'kleines',
    'kleinen',
    'neue',
    'neuer',
    'neues',
    'neuen',
    'alte',
    'alter',
    'altes',
    'alten',
    'schöne',
    'schöner',
    'schönes',
    'schönen',
    'einzige',
    'einziger',
    'einziges',
    'einzigen',
    'ganze',
    'ganzer',
    'ganzes',
    'ganzen',
    'springende',
    'springender',
    'springendes',
    'springenden',
  },
  'en': {
    'first',
    'second',
    'third',
    'last',
    'next',
    'good',
    'great',
    'important',
    'main',
    'big',
    'small',
    'new',
    'old',
    'best',
    'key',
    'final',
    'single',
  },
  'es': {
    'buen',
    'buena',
    'buenos',
    'buenas',
    'primer',
    'primero',
    'primera',
    'segundo',
    'segunda',
    'último',
    'última',
    'importante',
    'importantes',
    'mejor',
    'nuevo',
    'nueva',
    'mismo',
    'misma',
    'gran',
    'grande',
    'siguiente',
    'próximo',
    'próxima',
    'malo',
    'mala',
    'único',
    'única',
  },
  'pt': {
    'bom',
    'boa',
    'bons',
    'boas',
    'primeiro',
    'primeira',
    'segundo',
    'segunda',
    'último',
    'última',
    'importante',
    'importantes',
    'melhor',
    'novo',
    'nova',
    'mesmo',
    'mesma',
    'grande',
    'próximo',
    'próxima',
    'único',
    'única',
    'mau',
  },
  'ru': {
    'первый',
    'первая',
    'первое',
    'первую',
    'последний',
    'последняя',
    'последнее',
    'главный',
    'главная',
    'главное',
    'важный',
    'важная',
    'важное',
    'хороший',
    'хорошая',
    'хорошее',
    'хорошую',
    'новый',
    'новая',
    'новое',
    'следующий',
    'следующая',
    'следующее',
    'единственный',
    'единственная',
  },
};

/// Phrases that are a mark only between two digit groups. "point" is common
/// English, so it never counts on its own.
const _digitOnlyCommandsByLanguage = <String, Map<_Mark, List<String>>>{
  'en': {
    _Mark.period: ['point'],
  },
};

final _digitsOnly = RegExp(r'^\p{Nd}+$', unicode: true);
final _wordAt = RegExp('$_letterOrDigit+', unicode: true);
const _blankChars = ' \t\r\n';
final _nonLineBreak = RegExp(r'[^\r\n]');

/// Compiled matcher for one set of language codes.
class _Matcher {
  _Matcher({
    required this.pattern,
    required this.markByPhrase,
    required this.digitOnlyPhrases,
    required this.stopWords,
    required this.idioms,
    required this.idiomsBefore,
    required this.numberWords,
    required this.adjectives,
  });

  final RegExp pattern;
  final Map<String, _Mark> markByPhrase;
  final Set<String> digitOnlyPhrases;
  final Set<String> stopWords;
  final List<String> idioms;
  final List<String> idiomsBefore;
  final Set<String> numberWords;
  final Set<String> adjectives;
}

/// Matchers keyed by their joined language codes. Each set is compiled once
/// per process; a dictation session reuses the same few sets.
final _matcherCache = <String, _Matcher>{};

_Matcher _matcherFor(List<String> codes) =>
    _matcherCache.putIfAbsent(codes.join(','), () => _buildMatcher(codes));

_Matcher _buildMatcher(List<String> codes) {
  final markByPhrase = <String, _Mark>{};
  void addPhrases(Map<String, Map<_Mark, List<String>>> table) {
    for (final code in codes) {
      table[code]?.forEach((mark, phrases) {
        for (final phrase in phrases) {
          markByPhrase[phrase.toLowerCase()] = mark;
        }
      });
    }
  }

  addPhrases(_commandsByLanguage);
  addPhrases(_digitOnlyCommandsByLanguage);
  final digitOnlyPhrases = {
    for (final code in codes)
      for (final phrases
          in _digitOnlyCommandsByLanguage[code]?.values ??
              const <List<String>>[])
        for (final phrase in phrases) phrase.toLowerCase(),
  };
  // Longest phrase first, so that "ponto de interrogação" wins over "ponto".
  final phrases = markByPhrase.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final alternation = phrases.map(_phrasePattern).join('|');
  final pattern = RegExp(
    '(?<!$_letterOrDigit)(?<cmd>$alternation)(?!$_letterOrDigit)'
    '[$_sentenceOrClauseMarks]*[ \\t]*',
    caseSensitive: false,
    unicode: true,
  );
  return _Matcher(
    pattern: pattern,
    markByPhrase: markByPhrase,
    digitOnlyPhrases: digitOnlyPhrases,
    stopWords: {for (final c in codes) ...?_wordsBefore[c]},
    idioms: [for (final c in codes) ...?_idiomsAfter[c]],
    idiomsBefore: [for (final c in codes) ...?_idiomsBefore[c]],
    numberWords: {for (final c in codes) ...?_numberWordsByLanguage[c]},
    adjectives: {for (final c in codes) ...?_adjectivesByLanguage[c]},
  );
}

/// What to do with one command match.
enum _Action { keepText, mark, literalMark }

String _replaceCommands(String text, List<String> codes) {
  final matcher = _matcherFor(codes);
  final out = StringBuffer();
  var last = 0;
  var capitaliseNext = false;
  for (final m in matcher.pattern.allMatches(text)) {
    // Segments run from one match to the next, so together they cover the
    // text once and the loop stays linear.
    final before = text.substring(last, m.start);
    final phrase = m
        .namedGroup('cmd')!
        .toLowerCase()
        .replaceAll(_blankRun, ' ');
    final mark = matcher.markByPhrase[phrase];
    final split = _splitTrailingWhitespace(before);
    final action = _actionFor(
      before: before,
      ws: split.ws,
      text: text,
      end: m.end,
      mark: mark,
      digitOnly: matcher.digitOnlyPhrases.contains(phrase),
      start: m.start,
      matcher: matcher,
    );

    switch (action) {
      case _Action.keepText:
        final pending = _writeCapitalised(out, before, capitaliseNext);
        capitaliseNext = _writeCapitalised(
          out,
          text.substring(m.start, m.end),
          pending,
        );
      case _Action.literalMark:
        _writeCapitalised(out, split.body, capitaliseNext);
        out.write(mark!.glyph);
        capitaliseNext = false;
      case _Action.mark:
        capitaliseNext = _writeCapitalised(out, split.body, capitaliseNext);
        final alreadyMarked =
            split.body.isNotEmpty &&
            _sentenceOrClauseMarks.contains(split.body[split.body.length - 1]);
        if (!alreadyMarked) out.write(mark!.glyph);
        if (_hasLineBreak(split.ws)) {
          // The mark stays with the word before. The break after it is kept.
          out.write(split.ws.replaceAll(_nonLineBreak, ''));
        } else if (_letterOrDigitAt(text, m.end)) {
          out.write(' ');
        }
        capitaliseNext = mark!.endsSentence;
    }
    last = m.end;
  }
  _writeCapitalised(out, text.substring(last), capitaliseNext);
  return out.toString();
}

/// Decides between keeping the command as text, writing it as a literal mark
/// between two digit groups ("2 Punkt 0" gives "2.0") and turning it into a
/// mark. Number words and mixed forms stay text.
_Action _actionFor({
  required String before,
  required String ws,
  required String text,
  required int end,
  required _Mark? mark,
  required bool digitOnly,
  required int start,
  required _Matcher matcher,
}) {
  final precedingWord = _lastWord(before);
  if (mark == null || precedingWord == null) return _Action.keepText;
  final lower = precedingWord.toLowerCase();
  if (matcher.stopWords.contains(lower) ||
      matcher.adjectives.contains(lower) ||
      _idiomFollows(text, end, matcher.idioms) ||
      _idiomPrecedes(text, start, matcher.idiomsBefore) ||
      _clockTimeFollows(text, end, matcher)) {
    return _Action.keepText;
  }
  final nextWord = _wordAt.matchAsPrefix(text, end)?.group(0);
  final bothDigits =
      _isDigits(precedingWord) && _isDigits(nextWord) && !_hasLineBreak(ws);
  if (digitOnly) {
    return bothDigits ? _Action.literalMark : _Action.keepText;
  }
  if (nextWord == null ||
      !_isNumeric(precedingWord, matcher) ||
      !_isNumeric(nextWord, matcher)) {
    return _Action.mark;
  }
  final punctuation = mark == _Mark.comma || mark == _Mark.period;
  return punctuation && bothDigits ? _Action.literalMark : _Action.keepText;
}

/// The last word of [before] without surrounding punctuation, or null.
String? _lastWord(String before) {
  final words = _lastWords(before, 1);
  return words.isEmpty ? null : words.first;
}

/// Up to [n] words at the end of [before], nearest first. The segment is
/// walked once from its end, so no window can cut a word in half.
List<String> _lastWords(String before, int n) {
  final runes = before.runes.toList();
  final words = <String>[];
  var i = runes.length;
  while (i > 0 && words.length < n) {
    while (i > 0 && !_isWordRune(runes[i - 1])) {
      i--;
    }
    final end = i;
    while (i > 0 && _isWordRune(runes[i - 1])) {
      i--;
    }
    if (end > i) words.add(String.fromCharCodes(runes.sublist(i, end)));
  }
  return words;
}

bool _isWordRune(int rune) => _wordRune.hasMatch(String.fromCharCode(rune));

bool _isNumeric(String word, _Matcher matcher) =>
    _isDigits(word) || matcher.numberWords.contains(word.toLowerCase());

bool _isDigits(String? word) => word != null && _digitsOnly.hasMatch(word);

({String body, String ws}) _splitTrailingWhitespace(String segment) {
  var end = segment.length;
  while (end > 0 && _blankChars.contains(segment[end - 1])) {
    end--;
  }
  return (body: segment.substring(0, end), ws: segment.substring(end));
}

bool _hasLineBreak(String ws) => ws.contains('\n') || ws.contains('\r');

/// True when [idioms] (lower case, two words) match the two words directly
/// before [start] of [text]. Only a short window is read, so the cost does
/// not depend on the length of the text.
bool _idiomPrecedes(String text, int start, List<String> idioms) {
  if (idioms.isEmpty) return false;
  final window = text.substring(start > 40 ? start - 40 : 0, start);
  final words = _lastWords(window, 2);
  if (words.length < 2) return false;
  final phrase = '${words[1]} ${words[0]}'.toLowerCase();
  return idioms.contains(phrase);
}

/// True when a number directly followed by "Uhr" starts at [index] of [text]:
/// "genau Punkt 12 Uhr" names a time, not a mark.
bool _clockTimeFollows(String text, int index, _Matcher matcher) {
  final number = _wordAt.matchAsPrefix(text, index)?.group(0);
  if (number == null || !_isNumeric(number, matcher)) return false;
  var i = index + number.length;
  while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
    i++;
  }
  return _wordAt.matchAsPrefix(text, i)?.group(0)?.toLowerCase() == 'uhr';
}

/// True when one of [idioms] starts at [index] of [text] (case-insensitive).
/// Compares only the window of each idiom's length, never the rest of the text.
bool _idiomFollows(String text, int index, List<String> idioms) {
  for (final idiom in idioms) {
    final end = index + idiom.length;
    if (end > text.length) continue;
    if (text.substring(index, end).toLowerCase() == idiom) return true;
  }
  return false;
}

/// True when the character at [index] of [text] is a letter or digit. Looks
/// at two code units so that a surrogate pair is seen whole.
bool _letterOrDigitAt(String text, int index) {
  if (index >= text.length) return false;
  final end = index + 2 < text.length ? index + 2 : text.length;
  return _letterOrDigitStart.hasMatch(text.substring(index, end));
}

/// Writes [segment], capitalising its first letter when [capitalise] is set.
/// Leading spaces and line breaks are passed through. Returns whether the
/// capital is still pending, which is the case when the segment has no letter.
bool _writeCapitalised(StringBuffer out, String segment, bool capitalise) {
  if (segment.isEmpty) return capitalise;
  if (!capitalise) {
    out.write(segment);
    return false;
  }
  var i = 0;
  while (i < segment.length && _blankChars.contains(segment[i])) {
    i++;
  }
  out.write(segment.substring(0, i));
  if (i == segment.length) return true;
  out.write(segment[i].toUpperCase() + segment.substring(i + 1));
  return false;
}
