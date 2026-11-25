/// Layout model of the long-note editor (#641, ADR 0035): display rows with
/// their character ranges in the note text, and the height index that places
/// them on screen. Pure logic — no widgets — so jumps and offsets are tested
/// without a frame.
library;

import 'dart:math' as math;

import 'package:whispaste/features/notes/blocks/block_document.dart';

/// Prefix sums over a list of values (Fenwick tree).
///
/// Reading the sum before an index, changing one value and finding the index
/// at a position all cost O(log n), so a keystroke or a measured row never
/// walks the whole document.
class PrefixSums {
  PrefixSums(Iterable<double> values) : _values = List.of(values) {
    _tree = List.filled(_values.length + 1, 0);
    for (var i = 1; i <= _values.length; i++) {
      _tree[i] += _values[i - 1];
      final parent = i + (i & -i);
      if (parent <= _values.length) _tree[parent] += _tree[i];
    }
  }

  final List<double> _values;
  late final List<double> _tree;

  int get length => _values.length;

  double operator [](int index) => _values[index];

  /// Sets the value at [index].
  void set(int index, double value) {
    final delta = value - _values[index];
    if (delta == 0) return;
    _values[index] = value;
    for (var i = index + 1; i < _tree.length; i += i & -i) {
      _tree[i] += delta;
    }
  }

  /// Sum of the values before [index] (`0 <= index <= length`).
  double sumBefore(int index) {
    var sum = 0.0;
    for (var i = index; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }

  double get total => sumBefore(length);

  /// Index whose range `[sumBefore(i), sumBefore(i + 1))` holds [position],
  /// clamped to `[0, length - 1]`. Zero-sized entries are skipped forward.
  /// Returns 0 for an empty list.
  int indexAt(double position) {
    if (_values.isEmpty) return 0;
    var index = 0;
    var rest = position;
    var step = 1;
    while (step * 2 <= _values.length) {
      step *= 2;
    }
    for (; step > 0; step >>= 1) {
      final next = index + step;
      if (next <= _values.length && _tree[next] <= rest) {
        index = next;
        rest -= _tree[next];
      }
    }
    return math.min(index, _values.length - 1);
  }
}

/// The display rows of a note: one row per block, or per display segment
/// when a block is longer than [BlockDocument.softSplitChars]. A row covers
/// `[startOf(row), endOf(row))` of the note text; the separator after a block
/// (line break and blank lines) belongs to no row.
///
/// The note text stays the only truth: rows are recomputed from it and never
/// written back, so the soft split at sentence ends changes nothing stored.
class NoteRows {
  NoteRows._(
    this.leading,
    this._lengths,
    this._gaps,
    this._cuts,
    this._lineBreaks,
    this._blocks,
    this._headingLevels,
    this.blockCount,
  ) : _spans = PrefixSums([
        for (var i = 0; i < _lengths.length; i++)
          (_lengths[i] + _gaps[i]).toDouble(),
      ]);

  /// Splits [text] into rows. An empty text has one empty row, so there is
  /// always a place for the caret.
  factory NoteRows.of(String text) {
    final doc = BlockDocument.parse(text);
    final lengths = <int>[];
    final gaps = <int>[];
    final cuts = <bool>[];
    final lineBreaks = <int>[];
    final blocks = <int>[];
    final headings = <int>[];
    for (var b = 0; b < doc.blocks.length; b++) {
      final block = doc.blocks[b];
      final bounds = BlockDocument.segmentBounds(block.content);
      for (var k = 0; k + 1 < bounds.length; k++) {
        final last = k + 2 == bounds.length;
        lengths.add(bounds[k + 1] - bounds[k]);
        gaps.add(last ? block.separator.length : 0);
        cuts.add(last && block.separator.endsWith('\n'));
        lineBreaks.add(
          _countLineBreaks(block.content, bounds[k], bounds[k + 1]),
        );
        blocks.add(b);
        headings.add(
          k == 0 && block.kind == BlockKind.heading ? block.headingLevel : 0,
        );
      }
    }
    var leading = doc.leading.length;
    if (lengths.isEmpty) {
      // Only blank lines (or nothing): one empty row at the very end.
      lengths.add(0);
      gaps.add(0);
      cuts.add(false);
      lineBreaks.add(0);
      blocks.add(0);
      headings.add(0);
      leading = text.length;
    }
    return NoteRows._(
      leading,
      lengths,
      gaps,
      cuts,
      lineBreaks,
      blocks,
      headings,
      math.max(1, doc.blocks.length),
    );
  }

  /// Characters before the first row (blank lines at the top of the note).
  final int leading;
  final List<int> _lengths;
  final List<int> _gaps;
  final List<bool> _cuts;
  final List<int> _lineBreaks;
  final List<int> _blocks;
  final List<int> _headingLevels;
  final PrefixSums _spans;

  /// Number of blocks (paragraphs, headings, list items, code blocks).
  final int blockCount;

  int get length => _lengths.length;

  int startOf(int row) => leading + _spans.sumBefore(row).round();

  int endOf(int row) => startOf(row) + _lengths[row];

  int lengthOf(int row) => _lengths[row];

  /// Characters of the separator after the row (0 inside a split block).
  int gapOf(int row) => _gaps[row];

  /// Start of the row's editable segment. Segments tile the whole text: the
  /// first starts at 0 (leading blank lines included), every other one where
  /// its row starts.
  int segmentStart(int row) => row == 0 ? 0 : startOf(row);

  /// End (exclusive) of the row's editable segment in a text of
  /// [textLength]. A segment keeps its separator except the final line
  /// break, which the row boundary itself stands for — so a row shows exactly
  /// the lines a single text field would. The last segment runs to the end.
  int segmentEnd(int row, int textLength) {
    if (row == length - 1) return textLength;
    return startOf(row + 1) - (_cuts[row] ? 1 : 0);
  }

  /// Row whose segment holds the text [offset]; on a soft split (no line
  /// break between the rows) the shared border belongs to the later row.
  int segmentOf(int offset) => rowOf(offset);

  /// Line breaks inside the row (a block of consecutive lines keeps them).
  int lineBreaksOf(int row) => _lineBreaks[row];

  /// 1 to 6 for the first row of a heading block, otherwise 0.
  int headingLevelOf(int row) => _headingLevels[row];

  /// Block the row belongs to (a long block spans several rows).
  int blockOf(int row) => _blocks[row];

  /// First row of [block] (rows are sorted by block).
  int firstRowOfBlock(int block) {
    var lo = 0;
    var hi = _blocks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_blocks[mid] < block) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return math.min(lo, _blocks.length - 1);
  }

  /// Row holding the text [offset]. An offset inside a separator belongs to
  /// the row before it, an offset in the leading blank lines to the first.
  int rowOf(int offset) {
    if (offset <= leading) return 0;
    return _spans.indexAt((offset - leading).toDouble());
  }

  /// The row's text grew or shrank by typing inside it; later rows move by
  /// the same amount without a re-parse.
  void resize(int row, int newLength) {
    _lengths[row] = newLength;
    _spans.set(row, (newLength + _gaps[row]).toDouble());
  }

  /// Whether rows [row] of this and [other] cover the same text shape, used
  /// to keep measured heights over a re-parse.
  bool sameShape(int row, NoteRows other, int otherRow) =>
      _lengths[row] == other._lengths[otherRow] &&
      _gaps[row] == other._gaps[otherRow] &&
      _cuts[row] == other._cuts[otherRow] &&
      _lineBreaks[row] == other._lineBreaks[otherRow] &&
      _headingLevels[row] == other._headingLevels[otherRow];

  static int _countLineBreaks(String s, int from, int to) {
    var n = 0;
    for (var i = from; i < to; i++) {
      if (s.codeUnitAt(i) == 0x0A) n++;
    }
    return n;
  }
}

/// A scroll position expressed as row plus pixel offset into that row. It
/// survives a change of every row height (window width, text scale): the
/// view keeps the same text at the top instead of the same pixel offset.
class HeightAnchor {
  const HeightAnchor(this.row, this.offset);

  final int row;
  final double offset;

  @override
  bool operator ==(Object other) =>
      other is HeightAnchor && other.row == row && other.offset == offset;

  @override
  int get hashCode => Object.hash(row, offset);

  @override
  String toString() => 'HeightAnchor($row, $offset)';
}

/// What the row heights depend on. A change of any field makes every
/// measured height stale.
class LayoutKey {
  const LayoutKey({
    required this.width,
    required this.textScale,
    required this.devicePixelRatio,
    this.lineHeight = defaultLineHeight,
  });

  /// Line height factor of the editor's text when nothing else is chosen —
  /// the same as the single text field's (WpTextFieldVariant.bare), so both
  /// editors look alike.
  static const defaultLineHeight = 1.65;

  /// Width available to the text.
  final double width;

  /// Font size of 1 logical pixel after the system text scale.
  final double textScale;

  /// Physical zoom of the window (display scale factor).
  final double devicePixelRatio;

  /// Line height factor chosen in the editor text view (#648).
  final double lineHeight;

  @override
  bool operator ==(Object other) =>
      other is LayoutKey &&
      (other.width - width).abs() < 0.5 &&
      other.textScale == textScale &&
      other.devicePixelRatio == devicePixelRatio &&
      other.lineHeight == lineHeight;

  @override
  int get hashCode =>
      Object.hash(width.round(), textScale, devicePixelRatio, lineHeight);
}

/// Height of every row: estimated from its text length until it is laid out
/// once, then measured. Offsets of rows and the row at a scroll offset come
/// from prefix sums, so a jump to any row costs O(log n) regardless of how
/// many rows were never built.
class HeightIndex {
  HeightIndex();

  LayoutKey? _key;
  PrefixSums _heights = PrefixSums(const []);
  List<bool> _measured = const [];

  /// Heights as estimated or measured, also for hidden rows.
  List<double> _real = const [];

  /// Rows inside a folded section (#1344): they keep their [_real] height
  /// but take no room, so offsets, anchors and jumps skip them.
  List<bool> _hidden = const [];

  int get length => _heights.length;

  bool isMeasured(int row) => _measured[row];

  /// Height the row takes on screen: 0 while it is hidden.
  double heightOf(int row) => _heights[row];

  bool isHidden(int row) => row < _hidden.length && _hidden[row];

  double offsetOf(int row) => _heights.sumBefore(row);

  /// Hides the rows marked in [hidden] (one flag per row) and shows all
  /// others. A mask of another length than the rows is kept for the next
  /// layout and applied once it fits.
  void setHidden(List<bool> hidden) {
    _hidden = List.of(hidden);
    if (_hidden.length != _real.length) return;
    for (var i = 0; i < _real.length; i++) {
      _heights.set(i, _hidden[i] ? 0 : _real[i]);
    }
  }

  void _rebuild(List<double> real, List<bool> measured) {
    _real = real;
    _measured = measured;
    final hide = _hidden.length == real.length;
    _heights = PrefixSums([
      for (var i = 0; i < real.length; i++) hide && _hidden[i] ? 0.0 : real[i],
    ]);
  }

  /// Re-estimates every row when [key] differs from the key the heights were
  /// taken with (zoom, window width, text scale). Returns whether it did.
  bool ensureLayout(LayoutKey key, NoteRows rows, double fontSize) {
    if (key == _key && rows.length == length) return false;
    _key = key;
    _rebuild([
      for (var i = 0; i < rows.length; i++) estimate(rows, i, key, fontSize),
    ], List.filled(rows.length, false));
    return true;
  }

  /// Takes over the heights of [oldRows] for rows of [newRows] whose shape
  /// did not change at the start and end of the document; rows in between
  /// are estimated. Keeps a re-parse after an edit from throwing away what
  /// was measured.
  void rebase(NoteRows oldRows, NoteRows newRows, double fontSize) {
    final key = _key;
    if (key == null || oldRows.length != length) {
      _key = null;
      if (key != null) ensureLayout(key, newRows, fontSize);
      return;
    }
    var head = 0;
    final common = math.min(oldRows.length, newRows.length);
    while (head < common && oldRows.sameShape(head, newRows, head)) {
      head++;
    }
    var tail = 0;
    while (tail < common - head &&
        oldRows.sameShape(
          oldRows.length - 1 - tail,
          newRows,
          newRows.length - 1 - tail,
        )) {
      tail++;
    }
    final heights = <double>[];
    final measured = <bool>[];
    for (var i = 0; i < newRows.length; i++) {
      if (i < head) {
        heights.add(_real[i]);
        measured.add(_measured[i]);
      } else if (i >= newRows.length - tail) {
        final old = oldRows.length - (newRows.length - i);
        heights.add(_real[old]);
        measured.add(_measured[old]);
      } else {
        heights.add(estimate(newRows, i, key, fontSize));
        measured.add(false);
      }
    }
    _rebuild(heights, measured);
  }

  /// Records the laid-out height of [row]. Returns whether the index changed
  /// (the list then has to lay out again with the corrected extent).
  bool measure(int row, double height) {
    if (row >= length) return false;
    _measured[row] = true;
    if ((_real[row] - height).abs() < 0.5) return false;
    _real[row] = height;
    if (isHidden(row)) return false;
    _heights.set(row, height);
    return true;
  }

  /// Corrects the estimate of a row whose text changed while it was not
  /// laid out (the active row is measured anyway).
  void reestimate(NoteRows rows, int row, double fontSize) {
    final key = _key;
    if (key == null || row >= length || _measured[row]) return;
    _real[row] = estimate(rows, row, key, fontSize);
    if (!isHidden(row)) _heights.set(row, _real[row]);
  }

  /// Row and offset into it at [scrollOffset].
  HeightAnchor anchorAt(double scrollOffset) {
    if (length == 0) return const HeightAnchor(0, 0);
    final row = _heights.indexAt(math.max(0, scrollOffset));
    return HeightAnchor(row, math.max(0, scrollOffset - offsetOf(row)));
  }

  /// Scroll offset that shows [anchor] at the top.
  double offsetFor(HeightAnchor anchor) {
    if (length == 0) return 0;
    final row = anchor.row.clamp(0, length - 1);
    return offsetOf(row) + anchor.offset.clamp(0, heightOf(row));
  }

  /// Estimated height of [row] (vertical padding included).
  static double estimate(
    NoteRows rows,
    int row,
    LayoutKey key,
    double fontSize,
  ) {
    final size = fontSize * key.textScale;
    final charsPerLine = math.max(1, (key.width / (size * 0.5)).floor());
    final wrapped = (rows.lengthOf(row) / charsPerLine).ceil();
    // Blank lines of the separator show inside the row (see segmentEnd).
    final blank = math.max(0, rows.gapOf(row) - 1);
    final lines = math.max(1, wrapped) + rows.lineBreaksOf(row) + blank;
    return lines * size * key.lineHeight;
  }
}

/// Length thresholds of a note, in characters (UTF-16 code units).
abstract final class LongNoteLimits {
  /// From this length on the notes page edits with the long-note editor.
  static const enterLongMode = 30000;

  /// Below this length it returns to the single text field. The gap to
  /// [enterLongMode] keeps a note at the threshold from flipping editors on
  /// every keystroke.
  static const leaveLongMode = 24000;

  /// From this length on the page suggests splitting the note. There is no
  /// upper limit: editing goes on, the notice only offers the way out.
  static const editingLimit = 1000000;

  /// Whether a note of [length] characters uses the long-note editor, given
  /// whether it [currentlyLong] does.
  static bool useLongMode(int length, {required bool currentlyLong}) =>
      currentlyLong ? length >= leaveLongMode : length >= enterLongMode;
}

/// Where "Split note" cuts [text]: the block boundary at or before [caret]
/// (the next one if that is the very start), or without a caret the block
/// boundary nearest the middle. A text of a single block is cut softly at a
/// sentence end or space near the middle. Returns null when no cut leaves
/// text on both sides.
///
/// The cut lies at the start of a block, so the separator stays with the
/// head; the caller trims the head's trailing line breaks.
int? splitOffset(String text, {int? caret}) {
  if (text.trim().isEmpty) return null;
  final rows = NoteRows.of(text);
  final starts = <int>[
    for (var b = 1; b < rows.blockCount; b++)
      rows.startOf(rows.firstRowOfBlock(b)),
  ];
  if (starts.isNotEmpty) {
    if (caret != null) {
      int? before;
      for (final s in starts) {
        if (s <= caret) before = s;
      }
      return before ?? starts.first;
    }
    final middle = text.length ~/ 2;
    return starts.reduce(
      (a, b) => (a - middle).abs() <= (b - middle).abs() ? a : b,
    );
  }
  // One block: soft cut after a sentence end, else after a space.
  final middle = text.length ~/ 2;
  int? best;
  for (var i = 1; i < text.length; i++) {
    final prev = text.codeUnitAt(i - 1);
    final sentence =
        (prev == 0x2E || prev == 0x21 || prev == 0x3F) &&
        text.codeUnitAt(i) == 0x20;
    if (sentence &&
        (best == null || (i - middle).abs() < (best - middle).abs())) {
      best = i + 1;
    }
  }
  if (best == null) {
    for (var i = 1; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x20 &&
          (best == null || (i - middle).abs() < (best - middle).abs())) {
        best = i + 1;
      }
    }
  }
  if (best == null || best <= 0 || best >= text.length) return null;
  if (text.substring(best).trim().isEmpty) return null;
  return best;
}
