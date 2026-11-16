/// Where the quick-note margin marks sit in a note's text (#803).
///
/// A mark stores the first line of its dictation (its anchor), not a text
/// offset: the user edits the note freely, and an offset would drift with the
/// first keystroke above it. The marks are matched in the order they were
/// appended, each one searched after the previous match, so two dictations
/// that start with the same words still land on their own lines.
library;

/// A margin mark placed in the text: the [offset] its dictation starts at
/// and the moment it was appended.
class PlacedAppendMark {
  const PlacedAppendMark({required this.offset, required this.appendedAt});

  final int offset;
  final DateTime appendedAt;

  @override
  bool operator ==(Object other) =>
      other is PlacedAppendMark &&
      other.offset == offset &&
      other.appendedAt == appendedAt;

  @override
  int get hashCode => Object.hash(offset, appendedAt);
}

/// Places the marks given as `(anchor, appendedAt)` pairs, oldest first, in
/// [text]. A mark whose anchor is empty or no longer found (the user
/// rewrote or deleted that dictation) is left out instead of being guessed
/// onto another line; it does not move the search position either.
List<PlacedAppendMark> placeAppendMarks(
  String text,
  Iterable<({String anchor, DateTime appendedAt})> marks,
) {
  final placed = <PlacedAppendMark>[];
  var searchFrom = 0;
  for (final mark in marks) {
    if (mark.anchor.isEmpty) continue;
    final at = text.indexOf(mark.anchor, searchFrom);
    if (at < 0) continue;
    placed.add(PlacedAppendMark(offset: at, appendedAt: mark.appendedAt));
    searchFrom = at + mark.anchor.length;
  }
  return placed;
}
