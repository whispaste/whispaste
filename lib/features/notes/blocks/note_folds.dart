/// Heading sections of a long note and which rows a fold hides (#1344,
/// ADR 0035). Pure logic over [NoteRows], so folding, revealing and the
/// carry-over across an edit are tested without a frame.
///
/// A fold is a view state only: it names a section by the ordinal of its
/// heading (0 for the first ATX heading of the note) and never touches the
/// text. The ordinals are what [EditorViewState.folded] stores per entry.
library;

import 'dart:math' as math;

import 'package:whispaste/features/notes/blocks/long_note_layout.dart';

/// The sections of a note: every ATX heading opens one that runs to the next
/// heading of the same or a higher level (fewer `#`), or to the end.
class NoteSections {
  NoteSections._(this._headingRows, this._bodyStarts, this._ends);

  factory NoteSections.of(NoteRows rows) {
    final headingRows = <int>[];
    final levels = <int>[];
    for (var row = 0; row < rows.length; row++) {
      final level = rows.headingLevelOf(row);
      if (level > 0) {
        headingRows.add(row);
        levels.add(level);
      }
    }
    final bodyStarts = <int>[];
    for (final row in headingRows) {
      // A heading longer than the display split spans several rows; they
      // all stay visible, the body starts after them.
      var body = row + 1;
      while (body < rows.length && rows.blockOf(body) == rows.blockOf(row)) {
        body++;
      }
      bodyStarts.add(body);
    }
    // Next heading of the same or a higher level ends a section: a stack of
    // still open sections walks the headings once.
    final ends = List<int>.filled(headingRows.length, rows.length);
    final open = <int>[];
    for (var i = 0; i < headingRows.length; i++) {
      while (open.isNotEmpty && levels[open.last] >= levels[i]) {
        ends[open.removeLast()] = headingRows[i];
      }
      open.add(i);
    }
    return NoteSections._(headingRows, bodyStarts, ends);
  }

  final List<int> _headingRows;
  final List<int> _bodyStarts;
  final List<int> _ends;

  /// Number of headings, foldable or not.
  int get count => _headingRows.length;

  /// Row of the heading of section [section].
  int headingRow(int section) => _headingRows[section];

  /// Row after the section's last row.
  int endOf(int section) => _ends[section];

  /// Whether the section has a body to fold away.
  bool isFoldable(int section) => _ends[section] > _bodyStarts[section];

  bool get hasFoldable {
    for (var i = 0; i < count; i++) {
      if (isFoldable(i)) return true;
    }
    return false;
  }

  /// Every foldable section.
  Set<int> get foldable => {
    for (var i = 0; i < count; i++)
      if (isFoldable(i)) i,
  };

  /// The section whose heading sits in [row], or null.
  int? sectionOfHeadingRow(int row) {
    final i = _lowerBound(_headingRows, row);
    return i < count && _headingRows[i] == row ? i : null;
  }

  /// The innermost foldable section [row] belongs to (its heading included),
  /// or null before the first heading.
  int? innermostAt(int row) {
    var i = _lowerBound(_headingRows, row + 1) - 1;
    for (; i >= 0; i--) {
      if (row < _ends[i] && isFoldable(i)) return i;
    }
    return null;
  }

  /// The outermost section whose body holds [row], or null when no section
  /// body does (rows before the first heading, and top-level headings).
  int? outermostAround(int row) {
    int? found;
    var i = _lowerBound(_headingRows, row + 1) - 1;
    for (; i >= 0; i--) {
      if (row >= _bodyStarts[i] && row < _ends[i]) found = i;
    }
    return found;
  }

  /// One flag per row of [rowCount]: whether a folded section hides it. A
  /// section inside a folded one is hidden with it, whatever its own state.
  List<bool> hiddenRows(Set<int> folded, int rowCount) {
    final hidden = List<bool>.filled(rowCount, false);
    if (folded.isEmpty) return hidden;
    var hiddenEnd = 0;
    for (var i = 0; i < count; i++) {
      if (_headingRows[i] < hiddenEnd) continue;
      if (!folded.contains(i) || !isFoldable(i)) continue;
      final end = math.min(_ends[i], rowCount);
      for (var r = _bodyStarts[i]; r < end; r++) {
        hidden[r] = true;
      }
      hiddenEnd = end;
    }
    return hidden;
  }

  /// The folded sections whose body holds [row]; unfolding them shows it.
  Set<int> foldedAround(int row, Set<int> folded) => {
    for (final i in folded)
      if (i < count && row >= _bodyStarts[i] && row < _ends[i]) i,
  };

  /// Folded ordinals that still name a foldable section.
  Set<int> valid(Iterable<int> folded) => {
    for (final i in folded)
      if (i >= 0 && i < count && isFoldable(i)) i,
  };

  static int _lowerBound(List<int> values, int target) {
    var lo = 0;
    var hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Carries [folded] (section ordinals in [oldText]) over an edit to
/// [newText]: a heading keeps its fold when it is still a heading at the
/// same place, shifted by what was inserted or removed before it. The edit
/// is taken as the span between the common prefix and suffix of both texts,
/// so headings above and below it keep their folds while ordinals shift.
Set<int> carryFolds({
  required Set<int> folded,
  required String oldText,
  required NoteRows oldRows,
  required String newText,
  required NoteRows newRows,
}) {
  if (folded.isEmpty) return const {};
  final oldSections = NoteSections.of(oldRows);
  final newSections = NoteSections.of(newRows);
  final common = math.min(oldText.length, newText.length);
  var prefix = 0;
  while (prefix < common &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < common - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }
  final delta = newText.length - oldText.length;
  final byStart = <int, int>{
    for (var i = 0; i < newSections.count; i++)
      newRows.startOf(newSections.headingRow(i)): i,
  };
  final carried = <int>{};
  for (final i in folded) {
    if (i < 0 || i >= oldSections.count) continue;
    final start = oldRows.startOf(oldSections.headingRow(i));
    final moved = start < prefix
        ? start
        : start >= oldText.length - suffix
        ? start + delta
        : start;
    final next = byStart[moved];
    if (next != null && newSections.isFoldable(next)) carried.add(next);
  }
  return carried;
}
