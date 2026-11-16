/// Word-level diff of one correction (issue #144). Pure logic: no database,
/// no UI, no clock. Turns "the text before" and "the text after" into the
/// changed spans ([CorrectionHunk]s) that candidate detection works on.
library;

import 'package:flutter/foundation.dart' show listEquals;

/// Changed words per correction above which it counts as a rewrite
/// ("Umformulierung") and is dropped: a correction is a fix of one to four
/// words, not a re-dictated sentence.
const int correctionMaxChangedWords = 4;

/// Upper bound for the dynamic-programming table of the middle part of two
/// texts (after the common prefix and suffix are cut off). Above it the diff
/// is refused instead of spending memory and time on a rewrite of a long
/// transcript. 250 000 cells is about 1 MB of table.
const int correctionMaxDiffCells = 250000;

/// Trailing and leading punctuation that belongs to the sentence, not to the
/// word ("Kubernetes." -> "Kubernetes"). Symbols inside a word and symbols that
/// start one (".NET", "@handle", "C++") are not in these sets.
const String _trailingPunctuation = '.,;:!?"\')]}>»“”’…';
const String _leadingPunctuation = '"\'([{<«„“‚‘¡¿';

/// One changed span: the words the text had and the words the user corrected
/// them to. Both lists keep the original spelling and case.
class CorrectionHunk {
  const CorrectionHunk({required this.sourceWords, required this.targetWords});

  final List<String> sourceWords;
  final List<String> targetWords;

  /// How many words the user had to touch for this span.
  int get changedWords => sourceWords.length > targetWords.length
      ? sourceWords.length
      : targetWords.length;

  @override
  bool operator ==(Object other) =>
      other is CorrectionHunk &&
      listEquals(sourceWords, other.sourceWords) &&
      listEquals(targetWords, other.targetWords);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(sourceWords), Object.hashAll(targetWords));

  @override
  String toString() => 'CorrectionHunk($sourceWords -> $targetWords)';
}

/// Result of the diff: the changed spans, or `null` when the texts are too
/// different in size to compare word by word (see [correctionMaxDiffCells]).
/// An empty list means no word changed (only case, punctuation or spacing).
List<CorrectionHunk>? diffCorrectionWords(String before, String after) {
  final a = wordsOf(before);
  final b = wordsOf(after);

  var prefix = 0;
  while (prefix < a.length &&
      prefix < b.length &&
      a[prefix].key == b[prefix].key) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix].key == b[b.length - 1 - suffix].key) {
    suffix++;
  }

  final midA = a.sublist(prefix, a.length - suffix);
  final midB = b.sublist(prefix, b.length - suffix);
  if (midA.isEmpty && midB.isEmpty) return const [];
  if (midA.isEmpty || midB.isEmpty) {
    // Pure insertion or deletion: one hunk with an empty side.
    return [
      CorrectionHunk(
        sourceWords: [for (final w in midA) w.text],
        targetWords: [for (final w in midB) w.text],
      ),
    ];
  }
  if (midA.length * midB.length > correctionMaxDiffCells) return null;

  final pairs = longestCommonWordPairs(midA, midB);
  final hunks = <CorrectionHunk>[];
  var ia = 0;
  var ib = 0;
  for (final match in [...pairs, (midA.length, midB.length)]) {
    final (ma, mb) = match;
    if (ia < ma || ib < mb) {
      hunks.add(
        CorrectionHunk(
          sourceWords: [for (var i = ia; i < ma; i++) midA[i].text],
          targetWords: [for (var j = ib; j < mb; j++) midB[j].text],
        ),
      );
    }
    ia = ma + 1;
    ib = mb + 1;
  }
  return hunks;
}

/// Splits [text] into words. A word is a run of non-space characters whose
/// trimmed form still contains a letter or a digit; pure punctuation tokens
/// ("—", "...") are not words and do not take part in the diff.
List<({String text, String key})> wordsOf(String text) {
  final words = <({String text, String key})>[];
  for (final raw in text.split(_whitespace)) {
    if (raw.isEmpty) continue;
    final core = _trimPunctuation(raw);
    if (!_hasLetterOrDigit.hasMatch(core)) continue;
    words.add((text: core, key: core.toLowerCase()));
  }
  return words;
}

final RegExp _whitespace = RegExp(r'\s+', unicode: true);
final RegExp _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

String _trimPunctuation(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && _leadingPunctuation.contains(token[start])) {
    start++;
  }
  while (end > start && _trailingPunctuation.contains(token[end - 1])) {
    end--;
  }
  return token.substring(start, end);
}

/// Matched index pairs of a longest common subsequence over the word keys,
/// in order. Classic dynamic programming; [midA] and [midB] are non-empty and
/// their product is bounded by [correctionMaxDiffCells] by the caller. Also
/// used by `target_field_span.dart` to find pasted words in a read span.
List<(int, int)> longestCommonWordPairs(
  List<({String text, String key})> midA,
  List<({String text, String key})> midB,
) {
  final n = midA.length;
  final m = midB.length;
  final width = m + 1;
  final table = List<int>.filled((n + 1) * width, 0);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i * width + j] = midA[i].key == midB[j].key
          ? table[(i + 1) * width + j + 1] + 1
          : _max(table[(i + 1) * width + j], table[i * width + j + 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (midA[i].key == midB[j].key) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (table[(i + 1) * width + j] >= table[i * width + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

int _max(int x, int y) => x > y ? x : y;
