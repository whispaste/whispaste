import 'dart:math' as math;

/// Optimal-string-alignment distance between [a] and [b] (insert, delete,
/// substitute, swap two neighbours), or null as soon as it must exceed
/// [max]. The early exit keeps typo matching cheap: a search compares every
/// query word against every word of every item on each keystroke, and most
/// pairs are rejected after the length check or the first rows.
int? boundedEditDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return null;
  if (a == b) return 0;
  final n = b.length;
  var prevPrev = List<int>.filled(n + 1, 0);
  var prev = List<int>.generate(n + 1, (j) => j);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var d = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        d = math.min(d, prevPrev[j - 2] + 1);
      }
      cur[j] = d;
      if (d < rowMin) rowMin = d;
    }
    if (rowMin > max) return null;
    final spare = prevPrev;
    prevPrev = prev;
    prev = cur;
    cur = spare;
  }
  final result = prev[n];
  return result > max ? null : result;
}
