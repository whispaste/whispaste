/// Pure title-derivation helper for history entries.
///
/// A history entry's title starts as an automatic derivation of its content
/// (`DriftRecordingStore.save`) and is recomputed on every content edit
/// (`HistoryDetailNotifier.updateContent`) as long as the user has never
/// manually renamed the entry (`HistoryEntry.titleEdited == false`, see the
/// `title_edited` column doc comment in `lib/core/data/tables.dart`). Once
/// `titleEdited` flips true the title is user-owned and this function is no
/// longer applied to that entry.
library;

const _maxTitleLength = 60;

/// Trims [content], then cuts at the last word boundary within
/// [_maxTitleLength] characters — the word boundary is only honored past
/// position 20, so a title with no early space (e.g. a long single "word")
/// doesn't get cut down to an unhelpfully short fragment.
String deriveHistoryTitle(String content) {
  // A title is one line: line breaks from spoken "new paragraph" commands
  // become spaces here, the content itself keeps them.
  final trimmed = content.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  if (trimmed.length <= _maxTitleLength) return trimmed;
  final cut = trimmed.substring(0, _maxTitleLength);
  final lastSpace = cut.lastIndexOf(' ');
  return lastSpace > 20 ? '${cut.substring(0, lastSpace)}…' : '$cut…';
}
