// ---------------------------------------------------------------------------
// Search snippet for the notes hit list (#872): the piece of a note's text
// around the first match of the search term, split into the text before, the
// match itself and the text after, so the list tile can mark the match
// without opening the note.
// ---------------------------------------------------------------------------

/// The excerpt around one search match. [before] + [match] + [after] is the
/// shown text; [leadingCut]/[trailingCut] tell whether the excerpt starts or
/// ends inside the note (the tile shows an ellipsis there).
class NoteSearchSnippet {
  const NoteSearchSnippet({
    required this.before,
    required this.match,
    required this.after,
    required this.leadingCut,
    required this.trailingCut,
  });

  final String before;

  /// The matched text exactly as written in the note (original casing).
  final String match;
  final String after;
  final bool leadingCut;
  final bool trailingCut;
}

/// Characters kept before the match. Small enough that the match sits on the
/// first of the tile's two preview lines.
const kNoteSnippetContextBefore = 40;

/// Characters kept after the match — more than fit into two lines; the tile's
/// ellipsis trims the rest.
const kNoteSnippetContextAfter = 160;

/// The excerpt around the first case-insensitive match of [query] in
/// [content] at or after [searchFrom] (the excerpt never reaches back before
/// it), or null when the query is blank or
/// does not occur there. Line breaks and runs of whitespace collapse to one
/// space; the excerpt starts at a word boundary, never mid-word.
///
/// [pattern], when given, is matched instead of [query] (the search over
/// every area marks the first word that starts with a query word, #628).
NoteSearchSnippet? noteSearchSnippet(
  String content,
  String query, {
  int searchFrom = 0,
  int contextBefore = kNoteSnippetContextBefore,
  int contextAfter = kNoteSnippetContextAfter,
  RegExp? pattern,
}) {
  final needle = query.trim();
  final from = searchFrom < 0 ? 0 : searchFrom;
  if ((pattern == null && needle.isEmpty) || from >= content.length) {
    return null;
  }
  final hit = (pattern ?? RegExp(RegExp.escape(needle), caseSensitive: false))
      .firstMatch(content.substring(from));
  if (hit == null || hit.end == hit.start) return null;
  final matchStart = hit.start + from;
  final matchEnd = hit.end + from;

  // Window start: [contextBefore] characters back (never before [from]), then
  // forward to the next word start so the excerpt does not open with a word
  // fragment.
  var start = matchStart - contextBefore;
  if (start <= from) {
    start = from;
  } else if (!_isSpace(content.codeUnitAt(start - 1))) {
    while (start < matchStart && !_isSpace(content.codeUnitAt(start))) {
      start++;
    }
  }
  final end = matchEnd + contextAfter < content.length
      ? matchEnd + contextAfter
      : content.length;

  return NoteSearchSnippet(
    before: _collapse(content.substring(start, matchStart)).trimLeft(),
    match: _collapse(content.substring(matchStart, matchEnd)),
    after: _collapse(content.substring(matchEnd, end)).trimRight(),
    leadingCut: _hasText(content, from, start),
    trailingCut: _hasText(content, end, content.length),
  );
}

final _whitespaceRun = RegExp(r'\s+');

String _collapse(String s) => s.replaceAll(_whitespaceRun, ' ');

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

bool _hasText(String s, int from, int to) =>
    s.substring(from, to).trim().isNotEmpty;
