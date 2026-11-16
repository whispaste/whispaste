import 'dart:math' show max;

/// Normalized similarity of [a] and [b] in the range 0.0..1.0.
///
/// Computed as `2 * LCS(a, b) / (len(a) + len(b))`, where LCS is the longest
/// common subsequence over Unicode code points. This equals
/// `1 - indelDistance / (len(a) + len(b))`, i.e. the Levenshtein distance
/// that allows only insertions and deletions, normalized by the combined
/// length. Two empty strings are identical (1.0).
///
/// Case is not folded here; callers lowercase when they want case-insensitive
/// matching. Runs in O(n*m) time and O(min(n, m)) memory.
double stringSimilarity(String a, String b) {
  final ra = a.runes.toList(growable: false);
  final rb = b.runes.toList(growable: false);
  final total = ra.length + rb.length;
  if (total == 0) return 1.0;

  // Keep the DP row as short as possible.
  final (short, long) = ra.length <= rb.length ? (ra, rb) : (rb, ra);
  var prev = List<int>.filled(short.length + 1, 0);
  var curr = List<int>.filled(short.length + 1, 0);
  for (final c in long) {
    for (var j = 1; j <= short.length; j++) {
      curr[j] = c == short[j - 1] ? prev[j - 1] + 1 : max(prev[j], curr[j - 1]);
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return 2 * prev[short.length] / total;
}
