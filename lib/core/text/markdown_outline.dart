/// The outline of a Markdown text (#645): its ATX headings in text order,
/// with level and place, for the outline panel of the editors and the
/// next/previous heading keys.
///
/// Pure and synchronous, so the panel, the keys and the tests share one
/// reading of what a heading is. The rule is the one the block model and the
/// read view use: `#` to `######` after at most three spaces, followed by a
/// space, a tab or the line end. Lines inside a fenced code block are never
/// headings, and an escaped `\#` (a plain note taken into Markdown) is none
/// either.
library;

import 'markdown_plain_text.dart';

/// One heading of the outline.
class OutlineHeading {
  const OutlineHeading({
    required this.level,
    required this.title,
    required this.start,
    required this.end,
  });

  /// 1 to 6: the number of `#`.
  final int level;

  /// The heading as read: markers and inline formatting removed, trimmed.
  /// Empty for a bare `#` line.
  final String title;

  /// Offset of the heading line's first character.
  final int start;

  /// Offset of the heading line's end (before `\r\n` or `\n`): where a jump
  /// puts the caret, as folding a section does (#1344).
  final int end;

  @override
  bool operator ==(Object other) =>
      other is OutlineHeading &&
      other.level == level &&
      other.title == title &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(level, title, start, end);

  @override
  String toString() => 'OutlineHeading($level, "$title", $start..$end)';
}

final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]|$)');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Every heading of [text], in text order.
List<OutlineHeading> markdownOutline(String text) {
  final out = <OutlineHeading>[];
  String? fence;
  var start = 0;
  final length = text.length;
  while (start <= length) {
    var nl = text.indexOf('\n', start);
    if (nl < 0) nl = length;
    var end = nl;
    if (end > start && text.codeUnitAt(end - 1) == 0x0D) end--;
    final line = text.substring(start, end);
    if (fence != null) {
      final m = _fence.firstMatch(line);
      if (m != null &&
          m.group(1)!.startsWith(fence) &&
          line.trim().length == m.group(1)!.length) {
        fence = null;
      }
    } else if (_fence.firstMatch(line) case final open?) {
      fence = open.group(1);
    } else if (_heading.firstMatch(line) case final m?) {
      out.add(
        OutlineHeading(
          level: m.group(1)!.length,
          title: markdownToPlainText(line).trim(),
          start: start,
          end: end,
        ),
      );
    }
    if (nl >= length) break;
    start = nl + 1;
  }
  return out;
}

/// Index of the heading the [caret] belongs to: the last one that starts at
/// or before it. -1 before the first heading.
int outlineIndexAt(List<OutlineHeading> outline, int caret) {
  var lo = 0;
  var hi = outline.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (outline[mid].start <= caret) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo - 1;
}

/// Index of the first heading after the line of [caret], or null when none
/// follows.
int? nextHeadingIndex(List<OutlineHeading> outline, int caret) {
  final i = outlineIndexAt(outline, caret) + 1;
  return i < outline.length ? i : null;
}

/// Index of the heading before the line of [caret]: in a section's body that
/// is the section's own heading, on a heading line the one before it. Null
/// when none comes before.
int? previousHeadingIndex(
  List<OutlineHeading> outline,
  String text,
  int caret,
) {
  final c = caret.clamp(0, text.length);
  final lineStart = c == 0 ? 0 : text.lastIndexOf('\n', c - 1) + 1;
  final i = outlineIndexAt(outline, lineStart - 1);
  return i >= 0 ? i : null;
}
