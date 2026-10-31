/// Pure title-derivation helper for the sidebar Notizen area.
///
/// Notes have no title column (see `Notes` table doc comment) — the list and
/// editor derive a display title from the content instead.
library;

const _maxTitleLength = 80;

/// Returns the first non-blank line of [content], trimmed and capped at
/// [maxLength] characters. Returns `null` when [content] has no non-blank
/// line — callers fall back to `l10n.notesUntitled`.
///
/// [maxLength] defaults to the editor/export cap; the notes list tile passes
/// a larger bound because it can show two wrapped title lines.
String? deriveNoteTitle(String content, {int maxLength = _maxTitleLength}) {
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    return trimmed.length <= maxLength
        ? trimmed
        : '${trimmed.substring(0, maxLength)}…';
  }
  return null;
}
