/// Three-way merge of two edits of the same text, line by line (#676).
///
/// The text writer uses it when a document changed outside the editor (a
/// quick-note append from the recording flow, the automation API, a second
/// window) while the user was typing: `base` is the last state the editor
/// saved, `ours` what the editor holds now, `theirs` what is stored now.
/// Edits on different paragraphs both survive; an overlap keeps both
/// versions one after the other and reports a conflict — text is never
/// silently dropped.
library;

/// Result of [mergeParagraphs].
class ParagraphMergeResult {
  const ParagraphMergeResult(this.text, {required this.conflict});

  final String text;

  /// True when both sides changed the same lines; [text] then carries both
  /// versions (ours first) so nothing is lost.
  final bool conflict;
}

/// Upper bound for the LCS table (rows × columns) before falling back to a
/// whole-block conflict. Keeps a merge of two huge rewrites bounded.
const _maxLcsCells = 4000000;

ParagraphMergeResult mergeParagraphs(String base, String ours, String theirs) {
  if (ours == theirs) return ParagraphMergeResult(ours, conflict: false);
  if (theirs == base) return ParagraphMergeResult(ours, conflict: false);
  if (ours == base) return ParagraphMergeResult(theirs, conflict: false);

  final b = base.split('\n');
  final o = ours.split('\n');
  final t = theirs.split('\n');

  final mo = _matchLines(b, o);
  final mt = _matchLines(b, t);
  if (mo == null || mt == null) {
    return ParagraphMergeResult(_both(ours, theirs), conflict: true);
  }

  // Merge changed base intervals. Adjacent changes do not overlap: an
  // append after the last line must not conflict with editing that line.
  final edits = [..._edits(b, o, mo, true), ..._edits(b, t, mt, false)]
    ..sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start != 0 ? start : a.end.compareTo(b.end);
    });
  final out = <String>[];
  var conflict = false;
  var cursor = 0;
  var index = 0;
  while (index < edits.length) {
    final first = edits[index++];
    final start = first.start;
    var end = first.end;
    final group = [first];
    while (index < edits.length) {
      final next = edits[index];
      final sameInsertion =
          start == end && next.start == start && next.end == start;
      if (next.start >= end && !sameInsertion) break;
      group.add(next);
      if (next.end > end) end = next.end;
      index++;
    }
    out.addAll(b.sublist(cursor, start));
    final cb = b.sublist(start, end);
    final co = _apply(b, start, end, group.where((e) => e.ours));
    final ct = _apply(b, start, end, group.where((e) => !e.ours));
    if (_eq(co, cb)) {
      out.addAll(ct);
    } else if (_eq(ct, cb) || _eq(co, ct)) {
      out.addAll(co);
    } else {
      conflict = true;
      out
        ..addAll(co)
        ..addAll(ct);
    }
    cursor = end;
  }
  out.addAll(b.sublist(cursor));
  return ParagraphMergeResult(out.join('\n'), conflict: conflict);
}

class _Edit {
  const _Edit(this.start, this.end, this.lines, this.ours);
  final int start;
  final int end;
  final List<String> lines;
  final bool ours;
}

List<_Edit> _edits(
  List<String> base,
  List<String> other,
  List<int> matches,
  bool ours,
) {
  final edits = <_Edit>[];
  var ib = 0, io = 0;
  for (var anchor = 0; anchor <= base.length; anchor++) {
    if (anchor < base.length && matches[anchor] < 0) continue;
    final end = anchor < base.length ? matches[anchor] : other.length;
    if (anchor > ib || end > io) {
      edits.add(_Edit(ib, anchor, other.sublist(io, end), ours));
    }
    ib = anchor + 1;
    io = end + 1;
  }
  return edits;
}

List<String> _apply(
  List<String> base,
  int start,
  int end,
  Iterable<_Edit> edits,
) {
  final out = <String>[];
  var cursor = start;
  for (final edit in edits) {
    out
      ..addAll(base.sublist(cursor, edit.start))
      ..addAll(edit.lines);
    cursor = edit.end;
  }
  out.addAll(base.sublist(cursor, end));
  return out;
}

String _both(String ours, String theirs) => '$ours\n\n$theirs';

// Lines come from split('\n') and hold no '\n', so the join is unambiguous
// once the lengths match.
bool _eq(List<String> a, List<String> b) =>
    a.length == b.length && a.join('\n') == b.join('\n');

/// For every line of [base], the index of the matching line in [other]
/// (longest common subsequence), or -1 when it was removed/changed.
/// Returns null when the changed middle is too large to diff.
List<int>? _matchLines(List<String> base, List<String> other) {
  final m = List<int>.filled(base.length, -1);
  var pre = 0;
  while (pre < base.length && pre < other.length && base[pre] == other[pre]) {
    m[pre] = pre;
    pre++;
  }
  var suf = 0;
  while (suf < base.length - pre &&
      suf < other.length - pre &&
      base[base.length - 1 - suf] == other[other.length - 1 - suf]) {
    m[base.length - 1 - suf] = other.length - 1 - suf;
    suf++;
  }
  final n = base.length - pre - suf;
  final k = other.length - pre - suf;
  if (n == 0 || k == 0) return m;
  if (n * k > _maxLcsCells) return null;

  // dp[i][j] = LCS length of base[pre+i..] and other[pre+j..].
  final w = k + 1;
  final dp = List<int>.filled((n + 1) * w, 0);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = k - 1; j >= 0; j--) {
      dp[i * w + j] = base[pre + i] == other[pre + j]
          ? dp[(i + 1) * w + j + 1] + 1
          : (dp[(i + 1) * w + j] >= dp[i * w + j + 1]
                ? dp[(i + 1) * w + j]
                : dp[i * w + j + 1]);
    }
  }
  var i = 0, j = 0;
  while (i < n && j < k) {
    if (base[pre + i] == other[pre + j]) {
      m[pre + i] = pre + j;
      i++;
      j++;
    } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return m;
}
