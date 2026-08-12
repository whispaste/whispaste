/// Navigation state providers — shared between [app.dart] and any widget or
/// service that needs to read or drive the active page / settings scroll target.
///
/// Extracted from [app.dart] to break a circular import: previously every file
/// that needed [activePageProvider] or [settingsScrollTargetProvider] imported
/// [app.dart], while [app.dart] itself imports those same files.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Active page provider
// ---------------------------------------------------------------------------

/// Tracks which top-level page is currently shown in the app shell.
class ActivePageNotifier extends Notifier<String> {
  @override
  String build() => 'history';

  void setPage(String id) => state = id;
}

final activePageProvider = NotifierProvider<ActivePageNotifier, String>(
  ActivePageNotifier.new,
);

// ---------------------------------------------------------------------------
// Settings scroll-target provider
// ---------------------------------------------------------------------------

/// Optional settings section to scroll to after navigating to Settings.
/// Set before calling [activePageProvider.notifier.setPage]('settings') —
/// SettingsPage consumes & clears it on mount.
class SettingsScrollTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsScrollTargetProvider =
    NotifierProvider<SettingsScrollTargetNotifier, String?>(
      SettingsScrollTargetNotifier.new,
    );

// ---------------------------------------------------------------------------
// Settings highlight-target provider
// ---------------------------------------------------------------------------

/// Optional settings section key to briefly highlight after a scroll-jump.
///
/// The settings search field sets this alongside [settingsScrollTargetProvider]
/// when the user selects a suggestion. [SettingsPage] listens and renders a
/// temporary border around the target section, then clears the provider.
class SettingsHighlightTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsHighlightTargetProvider =
    NotifierProvider<SettingsHighlightTargetNotifier, String?>(
      SettingsHighlightTargetNotifier.new,
    );

// ---------------------------------------------------------------------------
// Notes editor-target provider
// ---------------------------------------------------------------------------

/// Optional note id the Notizen area should open in its editor after
/// navigating there — the notes-side twin of [settingsScrollTargetProvider]
/// (a note id instead of a section key).
///
/// Set before calling [activePageProvider.notifier].setPage('notes');
/// `NotesPage` consumes it on mount and via `ref.listen`, and **clears it
/// synchronously as it reads it**. Clearing matters twice over: a later
/// manual visit to the Notizen area must not jump to the note again, and
/// re-setting the same id (two quick-note runs against the same note) would
/// otherwise be a silent no-op — a `Notifier` skips notification when the new
/// state equals the old one.
class NotesEditorTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? noteId) => state = noteId;
}

final notesEditorTargetProvider =
    NotifierProvider<NotesEditorTargetNotifier, String?>(
      NotesEditorTargetNotifier.new,
    );
