/// How notes and recordings look to the saved-view rules (#658).
library;

import 'dart:convert';

import 'package:whispaste/core/data/database.dart';

import 'smart_view.dart';

/// [note] with its [tags] as the rules read it. [hasAppends] is true when
/// quick-note dictations were added to it; the marked quick note counts as a
/// quick note even before the first one. [folderIds] is the note's folder
/// with its parent, see [SmartViewItem.folderIds].
SmartViewItem noteSmartViewItem(
  Note note,
  List<Tag> tags, {
  required bool hasAppends,
  required bool hasChecklist,
  Set<String> folderIds = const {},
}) => SmartViewItem(
  date: note.updatedAt,
  tagIds: {for (final t in tags) t.id},
  tagNames: {for (final t in tags) t.name.toLowerCase()},
  sources: {
    if (note.isQuickNote || hasAppends) SmartViewSource.quickNote,
    if (note.sourceEntryId != null) SmartViewSource.fromRecording,
  },
  hasChecklist: hasChecklist,
  pinned: note.pinned,
  folderIds: folderIds,
);

/// [entry] as the rules read it. Recordings keep their tags by name.
SmartViewItem recordingSmartViewItem(
  HistoryEntry entry, {
  required bool hasChecklist,
}) => SmartViewItem(
  date: entry.timestamp,
  tagNames: _tagNames(entry.tags),
  sources: {
    entry.source == 'import'
        ? SmartViewSource.audioImport
        : SmartViewSource.dictation,
  },
  hasChecklist: hasChecklist,
  pinned: entry.pinned,
);

Set<String> _tagNames(String raw) {
  if (raw.isEmpty || raw == '[]') return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return {
      for (final t in decoded)
        if (t is String && t.trim().isNotEmpty) t.trim().toLowerCase(),
    };
  } on FormatException {
    return const {};
  }
}
