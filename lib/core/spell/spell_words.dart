/// Splits editor text into the words the spell check looks at (#670).
///
/// Pure logic, no platform calls: the native checker only ever sees the
/// words this file hands it, so what counts as "a word" is decided here once
/// for macOS, Windows and Linux alike.
library;

/// One word of the text with its position.
class SpellWord {
  const SpellWord(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SpellWord &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'SpellWord($start, $end, $text)';
}

final RegExp _token = RegExp(
  r"[\p{L}\p{M}\p{N}_]+(?:['’][\p{L}\p{M}]+)*",
  unicode: true,
);

// Regions that are not prose: fenced code, inline code, URLs, e-mail
// addresses and Markdown link targets.
final RegExp _skipRegion = RegExp(
  r'```[\s\S]*?(?:```|$)'
  r'|`[^`\n]*`'
  r'|(?:https?://|www\.)\S+'
  r'|[\w.+-]+@[\w-]+(?:\.[\w-]+)+'
  r'|\]\([^)\n]*\)',
);

final RegExp _hasDigitOrUnderscore = RegExp(r'[\p{N}_]', unicode: true);

// Scripts without spaces between words; a word-level check is meaningless.
final RegExp _unsegmentedScript = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}]',
  unicode: true,
);

/// The words of [text] worth checking, in text order.
///
/// Skips single letters, ALL-CAPS acronyms, tokens with digits or
/// underscores, scripts written without spaces, and the regions listed in
/// [_skipRegion]. Hyphenated compounds are checked part by part.
List<SpellWord> spellWords(String text) {
  if (text.isEmpty) return const [];
  final skipped = <(int, int)>[
    for (final m in _skipRegion.allMatches(text)) (m.start, m.end),
  ];
  var skipIndex = 0;
  final words = <SpellWord>[];
  for (final m in _token.allMatches(text)) {
    while (skipIndex < skipped.length && skipped[skipIndex].$2 <= m.start) {
      skipIndex++;
    }
    if (skipIndex < skipped.length && skipped[skipIndex].$1 < m.end) {
      continue;
    }
    final word = m[0]!;
    if (!_worthChecking(word)) continue;
    words.add(SpellWord(m.start, m.end, word));
  }
  return words;
}

bool _worthChecking(String word) {
  if (word.runes.length < 2) return false;
  if (_hasDigitOrUnderscore.hasMatch(word)) return false;
  if (_unsegmentedScript.hasMatch(word)) return false;
  if (word == word.toUpperCase() && word != word.toLowerCase()) return false;
  return true;
}

/// The word in [words] that contains [offset], or `null`.
///
/// An offset right at the end of a word counts as inside it, so the caret
/// parked after the last letter still finds the word.
SpellWord? spellWordAt(List<SpellWord> words, int offset) {
  for (final w in words) {
    if (offset >= w.start && offset <= w.end) return w;
    if (w.start > offset) break;
  }
  return null;
}

/// [errors] carried across an edit from [oldText] to [newText] until the
/// next check: errors before the edit stay, errors after it move by the
/// length change, errors touching the edit are dropped. Keeps the underline
/// from sliding onto the wrong letters while the user types.
List<SpellWord> shiftSpellErrors(
  List<SpellWord> errors,
  String oldText,
  String newText,
) {
  if (errors.isEmpty || identical(oldText, newText) || oldText == newText) {
    return errors;
  }
  final maxPrefix = oldText.length < newText.length
      ? oldText.length
      : newText.length;
  var prefix = 0;
  while (prefix < maxPrefix &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < maxPrefix - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  final oldEditEnd = oldText.length - suffix;
  final newEditEnd = newText.length - suffix;
  final delta = newText.length - oldText.length;
  // An edit right at a word's edge only leaves the word alone when the
  // character now touching it is no word character ("wrot" + "!" keeps the
  // error, "wrot" + "e" changes the word).
  final keepBefore = prefix >= newText.length || !_isWordChar(newText, prefix);
  final keepAfter = newEditEnd <= 0 || !_isWordChar(newText, newEditEnd - 1);
  return [
    for (final e in errors)
      if (e.end < prefix || (e.end == prefix && keepBefore))
        e
      else if (e.start > oldEditEnd || (e.start == oldEditEnd && keepAfter))
        SpellWord(e.start + delta, e.end + delta, e.text),
  ];
}

final RegExp _wordChar = RegExp(r"[\p{L}\p{M}\p{N}_'’]", unicode: true);

bool _isWordChar(String text, int index) => _wordChar.hasMatch(text[index]);

/// The error after (or, with `forward: false`, before) [caret], wrapping
/// around the text. An error the caret sits in counts as the current one
/// and is skipped, so repeated presses walk on. `null` without errors.
SpellWord? nextSpellError(
  List<SpellWord> errors,
  int caret, {
  required bool forward,
}) {
  if (errors.isEmpty) return null;
  if (forward) {
    for (final e in errors) {
      if (e.start > caret) return e;
    }
    return errors.first;
  }
  for (final e in errors.reversed) {
    if (e.end < caret) return e;
  }
  return errors.last;
}
