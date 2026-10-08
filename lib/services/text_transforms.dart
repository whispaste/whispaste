/// Pure text-transform helpers applied to a finished transcript before it
/// is saved/pasted. Kept free-standing (not private methods on
/// [RecordingOrchestrator]) so they are directly unit-testable without any
/// pipeline/provider setup.
library;

/// Punctuation marks that are always sentence-level — never legitimately
/// part of a number: terminal marks, clause separators, and the em/en dash
/// + ellipsis some STT engines use as a clause connector.
///
/// Deliberately excludes:
/// - the apostrophe (`'`/`'`) — word-internal (e.g. "don't", "Silvio's"),
///   changes word meaning rather than sentence structure;
/// - the hyphen (`-`) — word-internal (e.g. compound words), same reason;
/// - the period/comma — see [_ambiguousPunctuation] below;
/// - digits and letters — never touched.
final _alwaysStrip = RegExp(r'[!?;:…—–]');

/// The period and comma are ambiguous: both are legitimate inside a number
/// (decimal point OR thousands separator — either can be `.` or `,`
/// depending on locale, e.g. "3.14" vs "3,14", "1,000" vs "1.000") as well
/// as ordinary sentence punctuation ("Hello.", "Wait, actually"). Stripping
/// them unconditionally would corrupt numbers, not just formatting — "2.5
/// kilograms" becoming "25 kilograms" changes the actual value, which is
/// worse than leaving punctuation in.
///
/// Resolution: only strip a period/comma when it is NOT flanked by a digit
/// on both sides. This keeps decimal points, thousands separators, version
/// numbers ("1.2.53"), and prices ("$19.99") fully intact, while a
/// sentence-ending period after a number ("The answer is 42.") is still
/// removed.
final _ambiguousPunctuation = RegExp(r'[.,](?!\d)|(?<!\d)[.,]');

/// Deterministically removes [_alwaysStrip] and [_ambiguousPunctuation]
/// matches from [text] and collapses the whitespace left behind, so
/// `"Hello, world."` becomes `"Hello world"` rather than `"Hello  world"`.
///
/// Engine-independent by construction — this is plain string processing on
/// the already-transcribed text, applied uniformly regardless of which STT
/// engine or provider produced it. See [SttSettings.stripPunctuation].
String stripPunctuation(String text) {
  return text
      .replaceAll(_alwaysStrip, '')
      .replaceAll(_ambiguousPunctuation, '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

/// Collapses the extraneous whitespace STT engines insert into a raw
/// transcript: line breaks become single spaces, runs of spaces collapse,
/// and the ends are trimmed. Always applied to a finished transcript, so
/// the result is clean for copy/paste.
String collapseTranscriptWhitespace(String transcript) {
  return transcript
      .replaceAll(RegExp(r'\r\n|\r'), '\n')
      .replaceAll(RegExp(r'\n+'), ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

/// Appends [addition] to a quick note's [existing] content as a new
/// paragraph — exactly one blank line as separator, regardless of how many
/// trailing newlines [existing] already has. No timestamp is inserted, and
/// an empty (or whitespace-only) [existing] note gets no leading whitespace
/// at all — [addition] becomes the entire content.
String appendToQuickNoteContent(String existing, String addition) {
  final trimmed = existing.replaceAll(RegExp(r'\s+$'), '');
  return trimmed.isEmpty ? addition : '$trimmed\n\n$addition';
}

/// German filler tokens: pure hesitation sounds that never carry meaning.
const germanFillerWords = ['äh', 'ähm', 'öh', 'öhm', 'hm', 'hmm', 'ehm'];

/// English filler tokens. "um" is English-only on purpose: in German it is a
/// preposition ("um 8 Uhr"), in Portuguese an article.
const englishFillerWords = ['uh', 'uhm', 'um', 'umm', 'erm', 'hmm'];

/// Tokens that are fillers in one language but real words in another — only
/// removed when the transcription language is explicitly one where they are
/// unambiguous (see [_fillerWordsFor]).
const _languageSpecificFillerWords = {'um'};

/// Filler tokens for [languageCode] (`de`, `en`, `en-US`, `auto`, ...). Any
/// language other than German/English — including auto-detection — gets the
/// union of both lists minus the tokens that are real words elsewhere.
List<String> _fillerWordsFor(String languageCode) {
  final base = languageCode.toLowerCase().split(RegExp('[-_]')).first;
  return switch (base) {
    'de' => germanFillerWords,
    'en' => englishFillerWords,
    _ => {
      ...germanFillerWords,
      ...englishFillerWords,
    }.difference(_languageSpecificFillerWords).toList(),
  };
}

/// Letters, digits and word-internal joiners: a filler token directly next
/// to one of these is part of a larger word ("Ähmlich", "uh-huh") and kept.
const _wordChar = r"[\p{L}\p{N}_'’\-]";

const _sentenceEnd = '.!?';

/// Removes hesitation fillers ("äh", "ähm", "uh", "um", ...) for
/// [languageCode] from a finished transcript — see [germanFillerWords] and
/// [englishFillerWords]. Whole words only, case-insensitive. Commas and
/// ellipses that only existed around the filler go with it, a sentence-ending
/// mark after a trailing filler stays, a filler that formed its own sentence
/// ("Ähm.") disappears completely, and a sentence start left behind is
/// capitalised.
///
/// Never makes things worse than the raw transcript: if the transform throws
/// or leaves nothing (a dictation of only fillers), [text] is returned as is.
/// See [SttSettings.removeFillerWords].
String removeFillerWords(String text, {required String languageCode}) {
  try {
    final result = _removeFillerWords(text, _fillerWordsFor(languageCode));
    return result.trim().isEmpty ? text : result;
  } on Object {
    return text;
  }
}

String _removeFillerWords(String text, List<String> fillers) {
  final tokens = [...fillers]..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?<!$_wordChar)(?:${tokens.map(RegExp.escape).join('|')})(?!$_wordChar)',
    caseSensitive: false,
    unicode: true,
  );
  var result = text;
  // Right to left, so earlier match offsets stay valid while later matches
  // are cut out (a later removal never reaches left of the earlier match's
  // end — at most back to the comma right after it).
  for (final match in pattern.allMatches(text).toList().reversed) {
    result = _cutFiller(result, match.start, match.end);
  }
  return result.trim();
}

int _skipSpacesRight(String s, int i) {
  while (i < s.length && s[i] == ' ') {
    i++;
  }
  return i;
}

int _skipSpacesLeft(String s, int i) {
  while (i > 0 && s[i - 1] == ' ') {
    i--;
  }
  return i;
}

/// Cuts the filler at [start]..[end] out of [s], together with the
/// punctuation and whitespace that only existed because of it.
String _cutFiller(String s, int start, int end) {
  // Right side: a pause mark the engine put after the filler.
  var right = end;
  final afterFiller = _skipSpacesRight(s, end);
  if (s.startsWith('...', afterFiller)) {
    right = _skipSpacesRight(s, afterFiller + 3);
  } else if (afterFiller < s.length && ',…'.contains(s[afterFiller])) {
    right = _skipSpacesRight(s, afterFiller + 1);
  }

  // Left side: the comma the engine put before the filler.
  var left = start;
  final beforeFiller = _skipSpacesLeft(s, start);
  if (beforeFiller > 0 && s[beforeFiller - 1] == ',') {
    left = beforeFiller - 1;
  }

  final beforeLeft = _skipSpacesLeft(s, left);
  final atSentenceStart =
      beforeLeft == 0 || _sentenceEnd.contains(s[beforeLeft - 1]);

  if (atSentenceStart) {
    // A filler that is its own sentence ("Ähm.") takes its mark with it.
    final next = _skipSpacesRight(s, right);
    if (right == end && next < s.length && _sentenceEnd.contains(s[next])) {
      right = next + 1;
    }
    final from = beforeLeft == 0 ? 0 : left;
    final to = _skipSpacesRight(s, right);
    final rest = s.substring(to);
    final capitalised = rest.isEmpty
        ? rest
        : rest[0].toUpperCase() + rest.substring(1);
    return s.substring(0, from) + capitalised;
  }

  final next = _skipSpacesRight(s, right);
  final from = _skipSpacesLeft(s, left);
  if (next >= s.length || '.!?,;:…'.contains(s[next])) {
    // Nothing (or only punctuation) follows: no separating space needed.
    return s.substring(0, from) + s.substring(next);
  }
  return '${s.substring(0, from)} ${s.substring(next)}';
}
