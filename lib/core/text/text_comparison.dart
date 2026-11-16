/// Comparison of two versions of a running text, down to single words (#637).
///
/// Pure Dart, so it can run in a background isolate: the result holds only
/// strings, numbers and enums.
///
/// The text is cut into sections first (paragraphs, and for a long paragraph
/// without blank lines chunks cut by content, not by position, so an insertion
/// does not shift every later cut). Sections are matched with each other, and
/// only the stretches that differ ("hunks") get a word diff. A text of 20,000
/// words therefore costs a few small tables instead of one huge one.
///
/// Cost bounds: a table is never larger than [maxTableCells]. A stretch that
/// would need more is shown as one removed and one added block (coarse); it
/// can still be taken over as a whole.
library;

enum DiffKind { same, added, removed }

/// A run of words of one kind. Words are joined by a single space.
class DiffSpan {
  const DiffSpan(this.kind, this.text);

  final DiffKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffSpan && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}:$text';
}

/// Most cells of one comparison table (a few MB).
const int maxTableCells = 4 * 1000 * 1000;

/// A paragraph longer than this is cut into chunks.
const int _longParagraphChars = 1200;
const int _chunkMinWords = 24;
const int _chunkMaxWords = 400;
const int _chunkCutModulus = 40;

final RegExp _blankLine = RegExp(r'\n[ \t]*\n(?:[ \t]*\n)*[ \t]*');
final RegExp _word = RegExp(r'\S+');

/// Word-level diff of [before] against [after]. Whitespace is not compared.
/// [coarse] is set when the size limit forced one removed and one added block.
({List<DiffSpan> spans, bool coarse}) diffWords(String before, String after) {
  final a = _wordsOf(before);
  final b = _wordsOf(after);
  return _diffWordLists(a, b);
}

List<String> _wordsOf(String text) => [
  for (final m in _word.allMatches(text)) m.group(0)!,
];

({List<DiffSpan> spans, bool coarse}) _diffWordLists(
  List<String> a,
  List<String> b,
) {
  final pairs = _matchPairs(a, b);
  if (pairs == null) {
    return (
      spans: [
        if (a.isNotEmpty) DiffSpan(DiffKind.removed, a.join(' ')),
        if (b.isNotEmpty) DiffSpan(DiffKind.added, b.join(' ')),
      ],
      coarse: true,
    );
  }
  final spans = <DiffSpan>[];
  final run = <String>[];
  DiffKind? runKind;
  void flush() {
    if (run.isNotEmpty) spans.add(DiffSpan(runKind!, run.join(' ')));
    run.clear();
  }

  void add(DiffKind kind, String word) {
    if (runKind != kind) {
      flush();
      runKind = kind;
    }
    run.add(word);
  }

  var i = 0;
  var j = 0;
  for (final (pi, pj) in [...pairs, (a.length, b.length)]) {
    while (i < pi) {
      add(DiffKind.removed, a[i++]);
    }
    while (j < pj) {
      add(DiffKind.added, b[j++]);
    }
    if (pi < a.length) {
      add(DiffKind.same, a[i]);
      i++;
      j++;
    }
  }
  flush();
  return (spans: spans, coarse: false);
}

/// Longest common subsequence of [a] and [b] as index pairs in order, or
/// `null` when the table would exceed [maxTableCells]. Common head and tail are
/// matched without a table.
List<(int, int)>? _matchPairs(List<String> a, List<String> b) {
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final n = a.length - head - tail;
  final m = b.length - head - tail;
  final pairs = <(int, int)>[for (var k = 0; k < head; k++) (k, k)];
  if (n > 0 && m > 0) {
    if ((n + 1) * (m + 1) > maxTableCells) return null;
    // Suffix table: lcs[i * (m + 1) + j] for a[head+i..], b[head+j..].
    final w = m + 1;
    final lcs = List<int>.filled((n + 1) * w, 0);
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i * w + j] = a[head + i] == b[head + j]
            ? lcs[(i + 1) * w + j + 1] + 1
            : (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]
                  ? lcs[(i + 1) * w + j]
                  : lcs[i * w + j + 1]);
      }
    }
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[head + i] == b[head + j]) {
        pairs.add((head + i, head + j));
        i++;
        j++;
      } else if (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
        i++;
      } else {
        j++;
      }
    }
  }
  for (var k = tail; k > 0; k--) {
    pairs.add((a.length - k, b.length - k));
  }
  return pairs;
}

/// Cuts [text] into sections that concatenate back to exactly [text]. Each
/// section ends with the whitespace that follows it.
List<String> splitSections(String text) {
  final out = <String>[];
  var start = 0;
  void paragraph(int from, int to, int sepEnd) {
    final body = text.substring(from, to);
    if (body.length <= _longParagraphChars) {
      out.add(text.substring(from, sepEnd));
      return;
    }
    // Long paragraph: cut after words whose hash says so (content-defined).
    var chunkStart = from;
    var words = 0;
    for (final m in _word.allMatches(body)) {
      words++;
      final cut =
          words >= _chunkMaxWords ||
          (words >= _chunkMinWords &&
              _hash(m.group(0)!) % _chunkCutModulus == 0);
      if (cut) {
        final end = from + m.end;
        // Include the whitespace after the word with this chunk.
        var e = end;
        while (e < to && _isSpace(text.codeUnitAt(e))) {
          e++;
        }
        if (e < to) {
          out.add(text.substring(chunkStart, e));
          chunkStart = e;
          words = 0;
        }
      }
    }
    out.add(text.substring(chunkStart, sepEnd));
  }

  for (final m in _blankLine.allMatches(text)) {
    paragraph(start, m.start, m.end);
    start = m.end;
  }
  if (start < text.length) paragraph(start, text.length, text.length);
  return out;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// A stretch where the two texts differ. Sections `[oldStart, oldEnd)` of the
/// old text stand against `[newStart, newEnd)` of the current text; either side
/// can be empty.
class TextHunk {
  const TextHunk({
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
    required this.spans,
    required this.coarse,
  });

  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;
  final List<DiffSpan> spans;

  /// Too large for a word diff: the spans are one removed and one added block.
  final bool coarse;

  /// Only in the current text (taking over from the old one deletes it).
  bool get onlyInCurrent => oldStart == oldEnd;

  /// Only in the old text (taking over brings it back).
  bool get onlyInOld => newStart == newEnd;

  int _words(DiffKind kind) => spans
      .where((s) => s.kind == kind)
      .fold(0, (n, s) => n + _word.allMatches(s.text).length);

  int get addedWords => _words(DiffKind.added);
  int get removedWords => _words(DiffKind.removed);
}

/// The result of comparing an older text with the current one.
class TextComparison {
  const TextComparison._(this._oldSections, this._newSections, this.hunks);

  final List<String> _oldSections;
  final List<String> _newSections;

  /// Differing stretches in text order; empty when the texts are the same.
  final List<TextHunk> hunks;

  bool get identical => hunks.isEmpty;

  /// Sections that are the same in both texts.
  int get unchangedSections =>
      _newSections.length -
      hunks.fold(0, (n, h) => n + (h.newEnd - h.newStart));

  /// The current text with hunk [index] replaced by the old text's version.
  String takeOver(int index) {
    final h = hunks[index];
    final buf = StringBuffer();
    for (var i = 0; i < h.newStart; i++) {
      buf.write(_newSections[i]);
    }
    // Appending after a last section that has no closing blank line.
    if (h.newStart > 0 &&
        h.oldEnd > h.oldStart &&
        !_endsWithBreak(_newSections[h.newStart - 1])) {
      buf.write('\n\n');
    }
    final hasAfter = h.newEnd < _newSections.length;
    for (var i = h.oldStart; i < h.oldEnd; i++) {
      final s = _oldSections[i];
      buf.write(s);
      // The last old section may lack its closing blank line.
      if (i == h.oldEnd - 1 && hasAfter && !_endsWithBreak(s)) {
        buf.write('\n\n');
      }
    }
    for (var i = h.newEnd; i < _newSections.length; i++) {
      buf.write(_newSections[i]);
    }
    return buf.toString();
  }

  static bool _endsWithBreak(String s) => s.endsWith('\n');
}

/// Compares [older] with [current]. The sections are matched by their words
/// (surrounding whitespace is ignored), so a changed line break alone is no
/// difference.
TextComparison compareTexts(String older, String current) {
  final oldSections = splitSections(older);
  final newSections = splitSections(current);
  final oldKeys = [for (final s in oldSections) s.trim()];
  final newKeys = [for (final s in newSections) s.trim()];
  var pairs = _matchPairs(oldKeys, newKeys);
  // Too many sections for a table: treat the whole text as one stretch.
  pairs ??= const [];
  final hunks = <TextHunk>[];
  var i = 0;
  var j = 0;
  void hunk(int oi, int oj) {
    // [i, oi) of old against [j, oj) of new.
    final r = _diffWordLists(
      _wordsOf(oldSections.sublist(i, oi).join()),
      _wordsOf(newSections.sublist(j, oj).join()),
    );
    // Only whitespace differs: not a difference.
    if (r.spans.every((s) => s.kind == DiffKind.same)) return;
    hunks.add(
      TextHunk(
        oldStart: i,
        oldEnd: oi,
        newStart: j,
        newEnd: oj,
        spans: r.spans,
        coarse: r.coarse,
      ),
    );
  }

  for (final (pi, pj) in [...pairs, (oldSections.length, newSections.length)]) {
    if (i < pi || j < pj) hunk(pi, pj);
    i = pi + 1;
    j = pj + 1;
  }
  return TextComparison._(oldSections, newSections, hunks);
}
