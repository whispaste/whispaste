/// Matching for the "Learn correction" hotkey (#934).
///
/// The user selects the corrected word in another app and presses the
/// hotkey. WhisPaste copies the selection and looks for the place in the last
/// dictation that the selection corrects: the word window (one word shorter,
/// as long, or one word longer than the selection) whose letters come closest
/// to it, case and spaces ignored. Joined words ("Whis Paste" → "WhisPaste")
/// and pure case fixes are found as well. Pure function, no I/O; the
/// candidate rules decide whether the pair is learned.
library;

import '../../core/utils/string_similarity.dart';
import 'correction_word_diff.dart' show wordsOf;

/// Longest selection that counts as a correction, in words; matches the
/// candidate rules (1 to 4 changed words).
const int selectionMatchMaxWords = 4;

/// Fewest letters a selection needs; shorter ones fit too many words.
const int selectionMatchMinLetters = 3;

/// Lowest similarity of letters between selection and dictated words.
const double selectionMatchMinSimilarity = 0.5;

/// Words kept in front of the match, as in target-app learning.
const int selectionMatchContextWords = 3;

/// The dictated words [sourceText] the selection [targetText] corrects, with
/// up to [selectionMatchContextWords] dictated words in front.
typedef SelectionCorrectionMatch = ({
  String sourceText,
  String targetText,
  String contextBefore,
});

/// The place in [dictation] that [selection] corrects, or null when there is
/// nothing to learn: empty, too short or too long selection, the selection already
/// stands in the dictation, no window is similar enough, two different
/// windows fit equally well, or only the case of a word at a sentence start
/// changed.
SelectionCorrectionMatch? matchSelectionToDictation(
  String selection,
  String dictation,
) {
  final selected = [for (final w in wordsOf(selection)) w.text];
  if (selected.isEmpty || selected.length > selectionMatchMaxWords) {
    return null;
  }
  final targetText = selected.join(' ');
  final targetKey = _letterKey(targetText);
  // "in" or "a" would match almost any short word.
  if (targetKey.length < selectionMatchMinLetters) return null;

  final tokens = _wordTokens(dictation);
  if (tokens.isEmpty) return null;

  var bestScore = -1.0;
  String? bestText;
  var bestStart = 0;
  var ambiguous = false;
  final k = selected.length;
  for (var n = k - 1; n <= k + 1; n++) {
    if (n < 1 || n > selectionMatchMaxWords || n > tokens.length) continue;
    for (var i = 0; i + n <= tokens.length; i++) {
      final text = [for (final t in tokens.sublist(i, i + n)) t.text].join(' ');
      // Already right in the dictation: nothing to learn.
      if (text == targetText) return null;
      final score = stringSimilarity(_letterKey(text), targetKey);
      if (score > bestScore + 1e-9) {
        bestScore = score;
        bestText = text;
        bestStart = i;
        ambiguous = false;
      } else if ((score - bestScore).abs() <= 1e-9 && text != bestText) {
        ambiguous = true;
      }
    }
  }
  if (bestText == null || ambiguous) return null;
  if (bestScore < selectionMatchMinSimilarity) return null;

  final contextStart = bestStart - selectionMatchContextWords < 0
      ? 0
      : bestStart - selectionMatchContextWords;
  final contextBefore = [
    for (final t in tokens.sublist(contextStart, bestStart)) t.raw,
  ].join(' ');
  // A capital at a sentence start is grammar, not a name.
  if (bestText.toLowerCase() == targetText.toLowerCase() &&
      !_isMidSentence(contextBefore)) {
    return null;
  }
  return (
    sourceText: bestText,
    targetText: targetText,
    contextBefore: contextBefore,
  );
}

/// Lower-case letters without spaces, so joined words match.
String _letterKey(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+', unicode: true), '');

/// Word tokens of [text]: the raw token (with punctuation) and its word.
List<({String raw, String text})> _wordTokens(String text) => [
  for (final raw in text.split(RegExp(r'\s+', unicode: true)))
    if (wordsOf(raw) case [final w, ...]) (raw: raw, text: w.text),
];

bool _isMidSentence(String context) {
  final trimmed = context.trimRight();
  if (trimmed.isEmpty) return false;
  return !RegExp(r'[.!?…:]["»“”’)\]]*$').hasMatch(trimmed);
}
