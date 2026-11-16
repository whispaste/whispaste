/// Pure word-level helpers for joining transcripts of neighbouring audio pieces.
///
/// A hard cut inside speech leaves the same words at the end of one piece and
/// at the start of the next (the audio overlap is transcribed twice). These
/// helpers remove that repeat deterministically; they never look at audio.
library;

import 'dart:math' as math;

/// Longest word run checked at a seam. A 2 s overlap holds about 4-6 words.
const int kSeamMaxRepeatWords = 8;

final RegExp _wordPattern = RegExp(r'\S+');
final RegExp _nonWordChars = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Lower-cased word with punctuation removed, so `Hallo,` and `hallo` match.
String normalizeTranscriptWord(String token) =>
    token.toLowerCase().replaceAll(_nonWordChars, '');

/// Returns [next] without the words at its start that repeat the end of
/// [previous]. The longest suffix of [previous] that equals a prefix of [next]
/// wins (up to [maxWords] words). Returns [next] unchanged when nothing
/// repeats. Whitespace after the removed words is kept.
String dropSeamRepeat(
  String previous,
  String next, {
  int maxWords = kSeamMaxRepeatWords,
}) {
  final tail = _wordPattern.allMatches(previous).toList(growable: false);
  final head = _wordPattern.allMatches(next).toList(growable: false);
  final longest = math.min(maxWords, math.min(tail.length, head.length));
  for (var k = longest; k >= 1; k--) {
    if (_sameWords(tail, tail.length - k, head, k)) {
      return next.substring(head[k - 1].end);
    }
  }
  return next;
}

/// Whether the [count] words of [a] from [aStart] equal the first [count]
/// words of [b] after normalisation. An empty normalised word never matches.
bool _sameWords(
  List<RegExpMatch> a,
  int aStart,
  List<RegExpMatch> b,
  int count,
) {
  for (var i = 0; i < count; i++) {
    final x = normalizeTranscriptWord(a[aStart + i].group(0)!);
    if (x.isEmpty || x != normalizeTranscriptWord(b[i].group(0)!)) return false;
  }
  return true;
}

/// Removes [text]'s leading words only when they are exactly the whole of
/// [echo] (its last [echo] words, normalised). Used to strip a continuity
/// prompt that a decoder repeated at the start of its output. Returns [text]
/// unchanged otherwise.
String dropLeadingEcho(String echo, String text) {
  final echoWords = _wordPattern.allMatches(echo).toList(growable: false);
  final head = _wordPattern.allMatches(text).toList(growable: false);
  if (echoWords.isEmpty || head.length < echoWords.length) return text;
  if (!_sameWords(echoWords, 0, head, echoWords.length)) return text;
  return text.substring(head[echoWords.length - 1].end);
}

/// Joins the texts of neighbouring pieces in order. A piece flagged in
/// [overlapsPrevious] starts with audio the previous piece ends with, so its
/// repeated leading words are removed against the last kept text. Empty texts
/// are skipped and the rest are trimmed, so the join never doubles a space.
String joinSeamTexts(List<String> texts, List<bool> overlapsPrevious) {
  final kept = <String>[];
  for (var i = 0; i < texts.length; i++) {
    var text = texts[i];
    if (text.isEmpty) continue;
    if (kept.isNotEmpty && i < overlapsPrevious.length && overlapsPrevious[i]) {
      text = dropSeamRepeat(kept.last, text);
    }
    text = text.trim();
    if (text.isNotEmpty) kept.add(text);
  }
  return kept.join(' ');
}
