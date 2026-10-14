/// Tail-anchored truncation for the live-transcript overlay text.
///
/// The overlay paints text single-line with a trailing ellipsis, which keeps
/// the START of a long string. For a live transcript that is backwards: the
/// newest words are the point of the preview, and they were the ones cut off
/// as soon as the recognized text outgrew the pill (a few words in).
library;

const String _ellipsis = '…';

/// Returns [text] (whitespace-collapsed) when [fits] accepts it, otherwise
/// the longest word-aligned tail of it behind a leading `…` that [fits]
/// accepts. When even the last word alone does not fit, that word is trimmed
/// from its start instead.
///
/// [fits] must be monotonic: if a string fits, every shorter suffix of it
/// (with the same `…` prefix) fits too — true for a width measurement.
String tailThatFits(String text, bool Function(String candidate) fits) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.length == 1 && words.first.isEmpty) return '';
  final whole = words.join(' ');
  if (fits(whole)) return whole;

  String wordTail(int from) => '$_ellipsis${words.sublist(from).join(' ')}';

  // Smallest word index whose tail fits (binary search, fits is monotonic).
  var lo = 1;
  var hi = words.length - 1;
  int? best;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (fits(wordTail(mid))) {
      best = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }
  if (best != null) return wordTail(best);

  final last = words.last;
  String charTail(int from) => '$_ellipsis${last.substring(from)}';
  lo = 0;
  hi = last.length;
  var bestChar = last.length;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (fits(charTail(mid))) {
      bestChar = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }
  return charTail(bestChar);
}
