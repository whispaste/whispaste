import 'side_panel_snapshot.dart';

/// Filters [rows] down to those whose title or subtitle contains [query],
/// case-insensitively (issue 09).
///
/// Pure, and deliberately not a provider: the render engine already holds
/// the rows for the section it's showing, and a provider would only add
/// indirection around a per-keystroke, purely local computation. Mirrors
/// `pendingOnboardingRevisionReasons`'s reasoning for extracting a plain
/// top-level function instead of building the logic into the widget.
///
/// A [query] that is empty after trimming returns [rows] unchanged (in the
/// same order) -- both the PRD's "empty search term shows the full list
/// again" requirement and the natural behaviour before the user has typed
/// anything.
///
/// Matching is a plain `contains` on lowercased text. Unlike
/// `WpFindReplace.locate`, this never reports match *offsets* back into the
/// original string, so the handful of code points that lowercase into a
/// different number of characters (e.g. Turkish `İ`) cannot misalign
/// anything here -- only `WpFindReplace`'s highlight/replace use case needed
/// the offset-preserving `RegExp.escape` rewrite.
List<SidePanelRow> filterSidePanelRows(List<SidePanelRow> rows, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return rows;

  final needle = trimmed.toLowerCase();
  return [
    for (final row in rows)
      if (row.title.toLowerCase().contains(needle) ||
          row.subtitle.toLowerCase().contains(needle))
        row,
  ];
}
