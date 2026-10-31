/// Spoken line-break commands ("new paragraph", "neue Zeile", ...) turned
/// into real line breaks in a finished transcript — the another app-style
/// behaviour for longer dictations such as emails. Pure string processing,
/// see [applyVoiceLineBreaks].
library;

import 'dart:math' as math;

enum _BreakKind { line, paragraph }

/// Spoken forms per transcription language (base code). Multi-word phrases
/// only: "newline" written as one word is deliberately not a command, since
/// it is common as a technical term.
const _commandsByLanguage = <String, Map<_BreakKind, List<String>>>{
  'en': {
    _BreakKind.paragraph: ['new paragraph', 'paragraph break'],
    _BreakKind.line: ['new line', 'line break'],
  },
  'de': {
    _BreakKind.paragraph: ['neuer Absatz', 'neuen Absatz'],
    _BreakKind.line: ['neue Zeile'],
  },
  'es': {
    _BreakKind.paragraph: ['nuevo párrafo', 'nuevo parrafo'],
    _BreakKind.line: ['nueva línea', 'nueva linea'],
  },
  'pt': {
    _BreakKind.paragraph: ['novo parágrafo', 'quebra de parágrafo'],
    _BreakKind.line: ['nova linha', 'quebra de linha'],
  },
  'ru': {
    _BreakKind.paragraph: ['новый абзац', 'новый параграф'],
    _BreakKind.line: ['новая строка', 'новая строчка'],
  },
  'he': {
    _BreakKind.paragraph: ['פסקה חדשה'],
    _BreakKind.line: ['שורה חדשה', 'ירידת שורה'],
  },
};

/// Punctuation a transcriber puts around a command: a comma/period/… right
/// after the spoken phrase, and the spaces around it. The mark *before* the
/// phrase is kept (it closes the preceding clause), only the spaces go.
const _trailingGlue = r'[.,;:!?…]*[ \t]*';
const _leadingSpaces = r'[ \t]*';
const _sentenceEnd = '.!?…';

/// Command sets that apply for [languageCode] (`de`, `en-US`, `auto`, ...).
///
/// A known transcription language uses its own set only. Auto-detection uses
/// the union of all sets, because the language is not known in advance. A
/// language without a set (e.g. `fr`) gets no commands at all — applying
/// another language's phrases there would only add false positives.
List<Map<_BreakKind, List<String>>> _setsFor(String languageCode) {
  final base = languageCode.toLowerCase().split(RegExp('[-_]')).first;
  if (base == 'auto') return _commandsByLanguage.values.toList();
  final set = _commandsByLanguage[base];
  return set == null ? const [] : [set];
}

/// Turns one spoken phrase into a regex fragment that tolerates the
/// punctuation and hyphens a transcriber may put between its words
/// ("neuer-Absatz", "new. line"), mirroring the trigger matching of the
/// text replacements.
String _phrasePattern(String phrase) => phrase
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((word) => word.isNotEmpty)
    .map(RegExp.escape)
    .join(r'[^\p{L}\p{N}]+');

/// Replaces the spoken line-break commands in [text] for [languageCode].
///
/// Rules:
/// - Whole words only, case-insensitive; punctuation and capitalisation
///   Whisper/Parakeet add are tolerated ("Neuer Absatz." / ", new line,").
/// - Spaces before a command and punctuation directly after it are dropped.
///   "Hello, new paragraph. Next" gives "Hello,\n\nNext".
/// - A paragraph break, or a break after a sentence end (`.!?…`), capitalises
///   the first letter of the following word (same as text_transforms does
///   after a removed filler at a sentence start).
/// - Consecutive commands merge into the largest break ("new line new
///   paragraph" gives one blank line, not three newlines).
/// - A break at the very start or the very end of the transcript is dropped.
///
/// Never makes things worse: if the transform throws or would leave nothing,
/// [text] is returned unchanged.
String applyVoiceLineBreaks(String text, {required String languageCode}) {
  try {
    final sets = _setsFor(languageCode);
    if (sets.isEmpty) return text;
    final paragraphs = [for (final s in sets) ...s[_BreakKind.paragraph]!];
    final lines = [for (final s in sets) ...s[_BreakKind.line]!];
    final result = _replaceCommands(text, paragraphs, lines);
    return result.trim().isEmpty ? text : result;
  } on Object {
    return text;
  }
}

String _replaceCommands(
  String text,
  List<String> paragraphs,
  List<String> lines,
) {
  String alternation(List<String> phrases) =>
      phrases.map(_phrasePattern).join('|');

  final pattern = RegExp(
    '$_leadingSpaces(?<![\\p{L}\\p{N}])'
    '(?:(?<p>${alternation(paragraphs)})|(?<l>${alternation(lines)}))'
    '(?![\\p{L}\\p{N}])$_trailingGlue',
    caseSensitive: false,
    unicode: true,
  );

  final out = StringBuffer();
  // 0 = no break pending, 1 = line break, 2 = paragraph break.
  var pendingLevel = 0;
  var pendingCapitalise = false;
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    final before = text.substring(last, m.start);
    final isParagraph = m.namedGroup('p') != null;
    final endsSentence =
        before.isNotEmpty && _sentenceEnd.contains(before[before.length - 1]);
    if (before.isNotEmpty) {
      _writeSegment(out, before, pendingLevel, pendingCapitalise);
      pendingLevel = 0;
      pendingCapitalise = false;
    }
    pendingLevel = math.max(pendingLevel, isParagraph ? 2 : 1);
    pendingCapitalise = pendingCapitalise || isParagraph || endsSentence;
    last = m.end;
  }
  final tail = text.substring(last);
  if (tail.isNotEmpty) {
    _writeSegment(out, tail, pendingLevel, pendingCapitalise);
  }
  return out.toString();
}

/// Writes [segment], preceded by the pending break unless nothing has been
/// written yet (no break at the very start).
void _writeSegment(
  StringBuffer out,
  String segment,
  int breakLevel,
  bool capitalise,
) {
  if (breakLevel > 0 && out.isNotEmpty) {
    out.write(breakLevel == 2 ? '\n\n' : '\n');
  }
  if (breakLevel > 0 && capitalise && segment.isNotEmpty) {
    out.write(segment[0].toUpperCase() + segment.substring(1));
  } else {
    out.write(segment);
  }
}
