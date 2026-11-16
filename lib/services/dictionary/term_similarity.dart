/// Strict similarity matching of dictionary terms (#147) for engines that
/// take no prompt hint (on-device Parakeet): a recognised word that is almost
/// exactly a term is corrected to the term.
///
/// The measure is the normalised Levenshtein similarity
/// `1 - distance / max(length)` on lowercased text. At [termSimilarityThreshold]
/// a word of up to 12 characters has to match exactly (apart from case); one
/// typo is accepted from 13 characters on. That is intended (Silvio
/// 2026-11-10): short terms stay practically uncorrected rather than risking
/// a wrong replacement. See `internal-notes`.
library;

import '../replacements/text_replacement_matcher.dart'
    show fuzzyMinTriggerLength, isOtherWordForm;

/// Strict threshold; deliberately not staggered by length.
const double termSimilarityThreshold = 0.92;

/// Words and terms shorter than this many characters are never matched.
const int termSimilarityMinLength = fuzzyMinTriggerLength;

/// Common words that are never corrected to a term and never act as a term:
/// a name such as "Will" or "Bill" must not turn every "will" into a name.
const Set<String> termSimilarityStopwords = {
  // de
  'aber', 'also', 'auch', 'dann', 'dass', 'dein', 'denn', 'dies', 'diese',
  'doch', 'eine', 'einen', 'einer', 'euch', 'euer', 'habe', 'haben', 'hast',
  'hatte', 'hier', 'ihre', 'jetzt', 'kann', 'kein', 'keine', 'macht', 'mein',
  'mich', 'mehr', 'muss', 'nach', 'nicht', 'noch', 'oder', 'sehr', 'sein',
  'seine', 'sich', 'sind', 'soll', 'über', 'unser', 'viel', 'vom', 'wann',
  'warum', 'weil', 'wenn', 'werden', 'wird', 'wir', 'wurde', 'zum', 'zur',
  // en
  'about', 'after', 'been', 'before', 'could', 'does', 'from', 'have',
  'here', 'into', 'just', 'like', 'make', 'more', 'must', 'only', 'other',
  'over', 'some', 'than', 'that', 'their', 'them', 'then', 'there', 'these',
  'they', 'this', 'very', 'want', 'well', 'were', 'what', 'when', 'where',
  'which', 'will', 'with', 'would', 'your',
  // es / pt
  'como', 'para', 'pero', 'porque', 'este', 'esta', 'esto', 'muy', 'tiene',
  'também', 'mais', 'está', 'você', 'isso', 'uma', 'com', 'não', 'por',
};

/// Normalised Levenshtein similarity of [a] and [b] (case-insensitive), in
/// `0..1`; 1 for equal strings, 1 for two empty strings.
double normalizedLevenshteinSimilarity(String a, String b) {
  final x = a.toLowerCase().runes.toList();
  final y = b.toLowerCase().runes.toList();
  final longest = x.length > y.length ? x.length : y.length;
  if (longest == 0) return 1;
  var prev = List<int>.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i++) {
    final cur = List<int>.filled(y.length + 1, 0)..[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      var best = prev[j - 1] + cost;
      if (prev[j] + 1 < best) best = prev[j] + 1;
      if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
      cur[j] = best;
    }
    prev = cur;
  }
  return 1 - prev[y.length] / longest;
}

/// Whether [heard] is to be corrected to [term]: both long enough, neither a
/// stopword, [heard] is not just another inflected form of [term]
/// ("Projektmanagements" for "Projektmanagement"), and the similarity reaches
/// [threshold]. An exact match only counts when it changes the spelling of a
/// term written with an inner capital ("github" for "GitHub"); plain
/// lowercase/uppercase differences of ordinary words are left alone.
bool termSimilarityMatches(
  String heard,
  String term, {
  double threshold = termSimilarityThreshold,
}) {
  if (heard == term) return false;
  final h = heard.toLowerCase();
  final t = term.toLowerCase();
  if (h.runes.length < termSimilarityMinLength ||
      t.runes.length < termSimilarityMinLength) {
    return false;
  }
  if (termSimilarityStopwords.contains(h) ||
      termSimilarityStopwords.contains(t)) {
    return false;
  }
  if (h == t) return _hasInnerCapital(term);
  if (isOtherWordForm(h, t)) return false;
  return normalizedLevenshteinSimilarity(h, t) >= threshold;
}

bool _hasInnerCapital(String term) {
  final runes = term.runes.toList();
  for (var i = 1; i < runes.length; i++) {
    final c = String.fromCharCode(runes[i]);
    if (c != c.toLowerCase()) return true;
  }
  return false;
}

final _word = RegExp(r"[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*", unicode: true);
final _onlySpace = RegExp(r'^\s+$');

class _Hit {
  _Hit(this.start, this.end, this.term, this.score);
  final int start;
  final int end;
  final String term;
  final double score;
}

/// Corrects words of [text] that match one of [terms] strictly, see
/// [termSimilarityMatches]. A term of several words matches the same number
/// of consecutive words. The better match wins where two overlap. Returns
/// [text] unchanged when nothing matches; the hit count goes to [onHits].
String applyTermSimilarity(
  String text,
  Iterable<String> terms, {
  double threshold = termSimilarityThreshold,
  void Function(int hits)? onHits,
}) {
  final wanted = <String>{
    for (final t in terms)
      if (t.trim().isNotEmpty) t.trim().replaceAll(RegExp(r'\s+'), ' '),
  };
  if (wanted.isEmpty || text.isEmpty) return text;
  final words = _word.allMatches(text).toList();
  if (words.isEmpty) return text;
  final hits = <_Hit>[];
  for (final term in wanted) {
    final n = term.split(' ').length;
    for (var i = 0; i + n <= words.length; i++) {
      var contiguous = true;
      for (var k = i; k < i + n - 1; k++) {
        if (!_onlySpace.hasMatch(
          text.substring(words[k].end, words[k + 1].start),
        )) {
          contiguous = false;
          break;
        }
      }
      if (!contiguous) continue;
      final start = words[i].start;
      final end = words[i + n - 1].end;
      final heard = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
      if (termSimilarityMatches(heard, term, threshold: threshold)) {
        hits.add(
          _Hit(start, end, term, normalizedLevenshteinSimilarity(heard, term)),
        );
      }
    }
  }
  if (hits.isEmpty) return text;
  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0
        ? byScore
        : (b.end - b.start).compareTo(a.end - a.start);
  });
  final accepted = <_Hit>[];
  for (final h in hits) {
    if (accepted.every((a) => h.end <= a.start || h.start >= a.end)) {
      accepted.add(h);
    }
  }
  accepted.sort((a, b) => b.start.compareTo(a.start));
  var out = text;
  for (final h in accepted) {
    out = out.replaceRange(h.start, h.end, h.term);
  }
  onHits?.call(accepted.length);
  return out;
}
