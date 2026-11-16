/// Working state of the Aufnahmen and Notizen pages that outlives a page
/// switch (#1074).
///
/// The app shell builds only the active page, so leaving a page disposes its
/// state. These holders keep what the user was in the middle of — selection,
/// multi-selection, view mode — for the rest of the session: the page reads
/// them in `initState` and writes them back in `dispose`. Search, filter and
/// sort order live in their own session providers (the database reads the
/// sort order, #1663); scroll offsets go through `PageStorage`
/// (`PageStorageKey` on the lists).
///
/// Deliberately not persisted: a fresh start opens a clean page.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aufnahmen page. The view mode is stored by enum name, so this file needs
/// no import from the history feature.
class HistoryWorkState {
  String? selectedEntryId;
  String? focusedEntryId;
  String? lastClickedId;
  bool multiSelectMode = false;
  Set<String> selectedIds = {};
  String? viewMode;
}

final historyWorkStateProvider = Provider<HistoryWorkState>(
  (ref) => HistoryWorkState(),
);

/// Notizen page: the open note. The editor text is reloaded from the
/// database on return, never kept here, so a note changed elsewhere in the
/// meantime opens with its current content.
class NotesWorkState {
  String? selectedNoteId;
}

final notesWorkStateProvider = Provider<NotesWorkState>(
  (ref) => NotesWorkState(),
);
