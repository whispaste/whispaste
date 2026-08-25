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
/// Matching uses a case-insensitive `RegExp`. Unlike `WpFindReplace.locate`,
/// this never reports match *offsets* back into the original string, so the
/// handful of code points that lowercase into a different number of characters
/// (e.g. Turkish `İ`) cannot misalign anything here. Using a precompiled
/// `RegExp` here prevents large GC spikes from repeatedly calling
/// `toLowerCase` on every row string.
List<SidePanelRow> filterSidePanelRows(List<SidePanelRow> rows, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return rows;

  // Precompiled outside the loop - vastly more memory-efficient than calling
  // .toLowerCase().contains() on every row's title and subtitle, bypassing
  // the need to allocate lowercased string copies and preventing GC spikes.
  final queryRegex = RegExp(RegExp.escape(trimmed), caseSensitive: false);
  return [
    for (final row in rows)
      if (queryRegex.hasMatch(row.title) || queryRegex.hasMatch(row.subtitle))
        row,
  ];
}
