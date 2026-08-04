/// Pure title-derivation helper for the sidebar Notizen area.
///
/// Notes have no title column (see `Notes` table doc comment) — the list and
/// editor derive a display title from the content instead.
library;

const _maxTitleLength = 80;

/// Returns the first non-blank line of [content], trimmed and capped at
/// [_maxTitleLength] characters. Returns `null` when [content] has no
/// non-blank line — callers fall back to `l10n.notesUntitled`.
String? deriveNoteTitle(String content) {
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    return trimmed.length <= _maxTitleLength
        ? trimmed
        : '${trimmed.substring(0, _maxTitleLength)}…';
  }
  return null;
}
