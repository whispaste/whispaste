/// Line-based diff between two note versions, for the version panel (WP-31a).
///
/// Plain longest-common-subsequence over lines. Notes are short, so the
/// quadratic cost is bounded by [maxLines]: larger inputs return `null`, and
/// the panel then shows the two versions without a diff.
library;

enum NoteDiffKind { same, added, removed }

class NoteDiffLine {
  const NoteDiffLine(this.kind, this.text);

  final NoteDiffKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is NoteDiffLine && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '$kind:$text';
}

/// Diffs [before] (older) against [after] (newer). Returns `null` when either
/// side has more than [maxLines] lines.
List<NoteDiffLine>? diffNoteLines(
  String before,
  String after, {
  int maxLines = 1500,
}) {
  final a = before.split('\n');
  final b = after.split('\n');
  if (a.length > maxLines || b.length > maxLines) return null;

  // LCS table over suffixes, so the walk below emits lines in order.
  final n = a.length;
  final m = b.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final out = <NoteDiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(NoteDiffLine(NoteDiffKind.same, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(NoteDiffLine(NoteDiffKind.removed, a[i]));
      i++;
    } else {
      out.add(NoteDiffLine(NoteDiffKind.added, b[j]));
      j++;
    }
  }
  while (i < n) {
    out.add(NoteDiffLine(NoteDiffKind.removed, a[i++]));
  }
  while (j < m) {
    out.add(NoteDiffLine(NoteDiffKind.added, b[j++]));
  }
  return out;
}
