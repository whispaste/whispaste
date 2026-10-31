/// Continuity prompt between two pieces of one long recording, with a loop
/// guard.
///
/// The tail of a piece's text is sent as the prompt of the next piece, so the
/// decoder keeps names and sentence style. A decoder that falls into a repeat
/// loop would feed that loop forward and keep it going, so a looping piece
/// carries nothing, and a prompt the decoder echoes back is stripped.
library;

import 'transcript_seam.dart';

/// Characters of text carried into the next piece's prompt at most.
const int kContinuityContextChars = 200;

/// Longest phrase (in words) checked for back-to-back repetition.
const int _maxLoopPeriodWords = 12;

/// Trailing words of [text] to carry forward as continuity context. Bounded
/// so a degraded piece poisons at most this much of the next prompt.
String continuityContextFrom(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= kContinuityContextChars) return trimmed;
  var start = trimmed.length - kContinuityContextChars;
  // A cut inside a surrogate pair (emoji, rare CJK) would leave a lone low
  // surrogate that UTF-8 encoding turns into U+FFFD in the next prompt.
  final first = trimmed.codeUnitAt(start);
  if (first >= 0xDC00 && first <= 0xDFFF) start++;
  // Cut inside a word: start at the next word when the window holds a space,
  // so the prompt never begins with a fragment. Without a space, keep the cut.
  if (!_isSpace(trimmed.codeUnitAt(start - 1)) &&
      !_isSpace(trimmed.codeUnitAt(start))) {
    var next = start;
    while (next < trimmed.length && !_isSpace(trimmed.codeUnitAt(next))) {
      next++;
    }
    if (next < trimmed.length) {
      start = next;
      while (start < trimmed.length && _isSpace(trimmed.codeUnitAt(start))) {
        start++;
      }
    }
  }
  return trimmed.substring(start);
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09;

/// Whether [text] repeats one phrase back to back, the signature of a decoder
/// loop. A single word must repeat five times, a phrase of `p` words at least
/// three times (`2p` words after the first copy). Ordinary speech such as
/// "ja ja ja" does not reach either bound.
bool isRepetitionLoop(String text) {
  final words = [
    for (final m in RegExp(r'\S+').allMatches(text))
      normalizeTranscriptWord(m.group(0)!),
  ];
  final n = words.length;
  for (var p = 1; p <= _maxLoopPeriodWords && 2 * p <= n; p++) {
    var run = 0;
    var longestRun = 0;
    for (var i = p; i < n; i++) {
      if (words[i].isNotEmpty && words[i] == words[i - p]) {
        run++;
        if (run > longestRun) longestRun = run;
      } else {
        run = 0;
      }
    }
    final required = p == 1 ? 4 : 2 * p;
    if (longestRun >= required) return true;
  }
  return false;
}

/// Prompt tail to carry from a finished piece [pieceText] into the next one,
/// or `null` when nothing may be carried (empty tail, or the piece is a loop).
String? continuityCarryFor(String pieceText) {
  final tail = continuityContextFrom(pieceText);
  if (tail.isEmpty || isRepetitionLoop(pieceText)) return null;
  return tail;
}

/// [text] without a leading copy of the [carry] prompt that the decoder
/// repeated. Text without such an echo comes back unchanged.
String stripPromptEcho(String carry, String text) =>
    dropLeadingEcho(carry, text);
