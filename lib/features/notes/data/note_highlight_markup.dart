/// Highlight markup for notes (WP-31a): `==text==` marks a passage for the
/// amber marker role. Stored as plain text in the note body, so it survives
/// the Markdown-style editor and export unchanged.
library;

final RegExp _highlightPattern = RegExp(r'==([^\n=]+?)==');

/// One highlighted range. [start] and [end] index the full source text;
/// [start..end) includes the `==` delimiters, [innerStart..innerEnd) is the
/// marked text.
class NoteHighlightSpan {
  const NoteHighlightSpan({
    required this.start,
    required this.end,
    required this.innerStart,
    required this.innerEnd,
  });

  final int start;
  final int end;
  final int innerStart;
  final int innerEnd;
}

/// All highlight spans in [text], in order and non-overlapping.
List<NoteHighlightSpan> noteHighlightSpans(String text) {
  final spans = <NoteHighlightSpan>[];
  for (final match in _highlightPattern.allMatches(text)) {
    final inner = match.group(1)!;
    if (inner.trim().isEmpty) continue;
    spans.add(
      NoteHighlightSpan(
        start: match.start,
        end: match.end,
        innerStart: match.start + 2,
        innerEnd: match.end - 2,
      ),
    );
  }
  return spans;
}
